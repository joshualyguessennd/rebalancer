// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";

// todo verify is the vault will work as curve vault where user can withraw the token he desires
// reevaluate the test for the vault withdraw
contract VanillaVault is Ownable, ERC20 {
    address public immutable router =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public rebalancer;
    uint256 private immutable _decimals = 18;
    event Deposit(address indexed user, address token, uint256 amount);
    event Withdrawn(address indexed user, address token, uint256 amount);

    mapping(address => bool) public isAllowedAsset;
    mapping(address => uint256) public assetWeight;
    mapping(address => mapping(address => uint256)) userShareAssets;

    error InvalidAsset();
    error InsufficientSharesBalance();
    error unauthorizedAccess();

    constructor() ERC20("VanillaVault", "VV") {}

    function addNewERC20(address _token) external onlyOwner {
        isAllowedAsset[_token] = true;
    }

    function removeERC20(address _token) external onlyOwner {
        isAllowedAsset[_token] = false;
    }

    function setBalancer(address _rebalancer) external onlyOwner {
        rebalancer = _rebalancer;
    }

    /**
    @dev deposit asset to the vault,
    @param _token asset authorized 
    @param _amount amount of asset the user wish to deposit 
    */
    function deposit(address _token, uint256 _amount) external {
        if (!isAllowedAsset[_token]) revert InvalidAsset();
        // get the decimal of the ERC20
        uint256 tokenDecimals = ERC20(_token).decimals();
        // transfer the token to the vault
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        // issue the share of the vault
        uint256 shares = _issueShares(_amount, tokenDecimals);
        // todo update the user share of the specific asset
        userShareAssets[msg.sender][_token] += shares;
        // mint the shares
        _mint(msg.sender, shares);
        emit Deposit(msg.sender, _token, shares);
    }

    function withdraw(address _token, uint256 _shares) external {
        if (!isAllowedAsset[_token]) revert InvalidAsset();

        uint256 tokenDecimals = ERC20(_token).decimals();
        uint256 amount = _calcShares(_shares, tokenDecimals);
        if (_shares > userShareAssets[msg.sender][_token])
            revert InsufficientSharesBalance();
        _burn(msg.sender, _shares);
        userShareAssets[msg.sender][_token] -= _shares;
        IERC20(_token).transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, _token, amount);
    }

    /**
     *@dev execute swap to rebalance the ratio of tokenA and tokenB
     * executeSwap function is only callable by rebalancer contract
     */
    function executeSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) external {
        if (msg.sender != rebalancer) revert unauthorizedAccess();
        address[] memory path;
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint256 deadline = block.timestamp;
        IUniswapV2Router02(router).swapExactTokensForTokens(
            _amount,
            0,
            path,
            address(this),
            deadline
        );
    }

    // /**
    //  *@dev get the vault ratio of token A and tokenB, for this example we are logic for 2 assets
    //  */
    // function getVaultRatio(address _tokenA, address _tokenB)
    //     public
    //     view
    //     returns (uint256, uint256)
    // {
    //     uint256 weigthAssetA = assetWeight[_tokenA];
    //     uint256 weigthAssetB = assetWeight[_tokenB];
    //     uint256 totalWeight = weigthAssetA + weigthAssetB;
    //     uint256 ratioA = (weigthAssetA / totalWeight) * 10000;
    //     uint256 ratioB = 10000 - ratioA;
    //     return (ratioA, ratioB);
    // }

    /**
    @dev issue the share after user deposits
    since assets could have different decimal, 
    _issueShares function set a standard decimals for all the amount decimal,
    this shares will be use for the asset weight in the vault
    @param _amount, amount deposited to the vault
    @param _decim, decimal of the asset the user has deposited
    @return shares value
    */
    function _issueShares(uint256 _amount, uint256 _decim)
        internal
        pure
        returns (uint256)
    {
        uint256 amountToMint = _amount * 10**(_decimals - _decim);
        return amountToMint;
    }

    function _calcShares(uint256 _shares, uint256 _decim)
        internal
        pure
        returns (uint256)
    {
        uint256 decimal = _decimals - _decim;
        uint256 amount = _shares / 10**decimal;
        return amount;
    }
}
