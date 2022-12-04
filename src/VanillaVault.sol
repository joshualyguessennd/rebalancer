// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// todo verify is the vault will work as curve vault where user can withraw the token he desires
// reevaluate the test for the vault withdraw
contract VanillaVault is Ownable, ERC20 {
    using SafeMath for uint256;
    address public immutable router =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public immutable usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public rebalancer;
    uint256 private immutable _decimals = 18;
    event Deposit(address indexed user, address token, uint256 amount);
    event Withdrawn(address indexed user, address token, uint256 amount);

    mapping(address => bool) public isAllowedAsset;
    mapping(address => uint256) public assetWeight;
    mapping(address => mapping(address => uint256)) public userShareAssets;
    mapping(address => address) public oracleAsset;

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

    function addOracle(address _asset, address _oracle) external onlyOwner {
        oracleAsset[_asset] = _oracle;
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
        path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint256 expectedAmountOut = IUniswapV2Router02(router).getAmountsOut(
            _amount,
            path
        )[1];
        uint256 deadline = block.timestamp;
        IERC20(_tokenIn).approve(router, _amount);
        IUniswapV2Router02(router).swapExactTokensForTokens(
            _amount,
            expectedAmountOut,
            path,
            address(this),
            deadline
        );
    }

    /**
    @dev get the current ratio of weth and usd in the vault
    for a contract that can take n token we need to set add more oracle price
    *@param _tokenA address of tokenA
    *@param _tokenB address of token
    *@return ratio of token A and ratio of token B, price of tokenA and price of tokenB    
    */
    function getVaultCurrentRatio(address _tokenA, address _tokenB)
        public
        view
        returns (uint256, uint256)
    {
        uint256 priceTokenA = getAssetPrice(_tokenA);
        uint256 priceTokenB = getAssetPrice(_tokenB);
        uint256 decimalsA = ERC20(_tokenA).decimals();
        uint256 decimmalsB = ERC20(_tokenB).decimals();
        uint256 totalWeightA = IERC20(_tokenA)
            .balanceOf(address(this))
            .div(10**decimalsA)
            .mul(priceTokenA)
            .div(10**8);
        uint256 totalWeightB = IERC20(_tokenB)
            .balanceOf(address(this))
            .div(10**decimmalsB)
            .mul(priceTokenB)
            .div(10**8);
        uint256 ratioB = totalWeightB.mul(10000).div(
            totalWeightA + totalWeightB
        );
        uint256 ratioA = totalWeightA.mul(10000).div(
            totalWeightA + totalWeightB
        );
        return (ratioA, ratioB);
    }

    /**
    @dev get the latest price of a token
    @param _asset asset to get the price 
    */
    function getAssetPrice(address _asset) internal view returns (uint256) {
        address _oracle = oracleAsset[_asset];
        (, int256 price, , , ) = AggregatorV3Interface(_oracle)
            .latestRoundData();
        return uint256(price);
    }

    function getValueAssetInVault(address _asset)
        public
        view
        returns (uint256)
    {
        uint256 decimal = ERC20(_asset).decimals();
        uint256 balance = IERC20(_asset).balanceOf(address(this));
        uint256 price = getAssetPrice(_asset);
        return balance.mul(price).div(10**decimal).div(10**8);
    }

    function getAmountOfByPrice(address _asset, uint256 _valueUSD)
        public
        view
        returns (uint256)
    {
        uint256 price = getAssetPrice(_asset);
        uint256 decimal = ERC20(_asset).decimals();
        uint256 amount = _valueUSD.mul(10**decimal).mul(10**8).div(price);
        return amount;
    }

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