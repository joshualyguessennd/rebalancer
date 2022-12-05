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
    address public immutable weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public rebalancer;
    uint256 private immutable _decimals = 18;
    uint256 private index = 1;
    event Deposit(address indexed user, address token, uint256 amount);
    event Withdrawn(address indexed user, address token, uint256 amount);

    mapping(address => bool) public isAllowedAsset;
    mapping(uint256 => address) public token;
    mapping(address => uint256) public assetWeight;
    mapping(address => mapping(address => uint256)) public userShareAssets;
    mapping(address => address) public oracleAsset;

    error InvalidAsset();
    error InsufficientSharesBalance();
    error unauthorizedAccess();
    error MaxTokenCount();

    constructor() ERC20("VanillaVault", "VV") {}

    function addNewERC20(uint256 _index, address _token) external onlyOwner {
        if (_index > index) revert MaxTokenCount();
        isAllowedAsset[_token] = true;
        token[_index] = _token;
    }

    /**
     *@dev get address of tokens in the vault
     *@param _index index to get the token address
     */
    function getToken(uint256 _index) public view returns (address) {
        return token[_index];
    }

    /**
     *@dev set balancer address for the vault
     */
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
        uint256 tokenDecimals = ERC20(_token).decimals();
        uint256 depositValue = ((_amount / 10**tokenDecimals) *
            getAssetPrice(_token)).div(10**8);
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        // get vault total value
        uint256 mintAmount = _issueShares(depositValue);
        _mint(msg.sender, mintAmount);
        emit Deposit(msg.sender, _token, _amount);
    }

    /**
     *@notice withdraw token using the shares the users have
     *@param _token token to withdraw
     *@param _shares to burn
     */
    function withdraw(address _token, uint256 _shares) external {
        if (!isAllowedAsset[_token]) revert InvalidAsset();
        // uint256 tokenDecimals = ERC20(_token).decimals();
        uint256 amount = _calcShares(_shares, _token);
        // if (_shares > userShareAssets[msg.sender][_token])
        //     revert InsufficientSharesBalance();
        _burn(msg.sender, _shares);
        // userShareAssets[msg.sender][_token] -= _shares;
        IERC20(_token).transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, _token, amount);
    }

    /**
     *@dev execute swap to rebalance the ratio of tokenA and tokenB
     * executeSwap function is only callable by rebalancer contract
     *@param _tokenIn token we want to swap
     *@param _tokenOut token to receive back
     *@param _amount amount of tokenOut to receive
     */
    function executeSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) external {
        if (msg.sender != rebalancer) revert unauthorizedAccess();
        if (_tokenIn == weth || _tokenOut == weth) {
            address[] memory path;
            path = new address[](2);
            path[0] = _tokenIn;
            path[1] = _tokenOut;
            uint256 expectedAmountOut = IUniswapV2Router02(router)
                .getAmountsOut(_amount, path)[1];
            uint256 deadline = block.timestamp;
            IERC20(_tokenIn).approve(router, _amount);
            IUniswapV2Router02(router).swapExactTokensForTokens(
                _amount,
                expectedAmountOut,
                path,
                address(this),
                deadline
            );
        } else {
            address[] memory path;
            path = new address[](3);
            path[0] = _tokenIn;
            path[1] = weth;
            path[2] = _tokenOut;
            uint256 expectedAmountOut = IUniswapV2Router02(router)
                .getAmountsOut(_amount, path)[2];
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
     *@dev function to verify if the token is allowed or not in the vault
     *@param _asset token to verify allowance
     *@return boolean
     */
    function isAllowedToken(address _asset) public view returns (bool) {
        return isAllowedAsset[_asset];
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

    /**
     *@dev get total value USD of aset in a vault
     *@param _asset asset to get the value in USD
     */
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

    /**
     *@dev determine the amount of token corresponding a value in USD
     *@param _asset asset address we want to determine the amount
     *@param _valueUSD value of USD to determine the amount of token
     */
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
    @return shares value
    */
    function _issueShares(uint256 _amount) internal view returns (uint256) {
        address _token0 = token[0];
        address _token1 = token[1];
        uint256 amountToMint;
        uint256 totalVaultValue = getValueAssetInVault(_token0) +
            getValueAssetInVault(_token1);
        if (totalSupply() == 0) {
            amountToMint = (_amount * 10**decimals());
        } else {
            amountToMint = (_amount * totalSupply()) / totalVaultValue;
        }
        return amountToMint;
    }

    /**
     *@dev calculate the token amount corresponding the value
     *@param _shares shares to get the amount
     *@param _token to withdraw
     */
    function _calcShares(uint256 _shares, address _token)
        internal
        view
        returns (uint256)
    {
        address _token0 = token[0];
        address _token1 = token[1];
        uint256 decimal = ERC20(_token).decimals();
        uint256 totalVaultValue = getValueAssetInVault(_token0) +
            getValueAssetInVault(_token1);
        return (_shares * totalVaultValue) / totalSupply();
    }
}
