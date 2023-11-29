// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswapV2/contracts/interfaces/IUniswapV2Router02.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// todo verify is the vault will work as curve vault where user can withraw the token he desires
// reevaluate the test for the vault withdraw
contract VanillaVault is Ownable, ERC20 {
    address public immutable router =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public immutable weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public rebalancer;
    uint256 private index = 1;
    event Deposit(address indexed user, address token, uint256 amount);
    event Withdrawn(address indexed user, address token, uint256 amount);

    mapping(address => bool) public isAllowedAsset;
    mapping(uint256 => address) public token;
    mapping(address => address) public oracleAsset;
    mapping(address => mapping(address => uint256)) public sharesForTokens;

    error InvalidAsset();
    error InsufficientSharesBalance();
    error InsufficientBalance();
    error unauthorizedAccess();
    error MaxTokenCount();

    constructor() ERC20("VanillaVault", "VV") Ownable(msg.sender) {}

    /**
     *@dev add new token to the vault of 2 assets o
     *@param _index to position the assets
     *@param _token asset address
     */
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
     *@param  _rebalancer, rebalancer contract address
     */
    function setBalancer(address _rebalancer) external onlyOwner {
        rebalancer = _rebalancer;
    }

    /**
     *@dev add oracle for a token
     *@param _asset asset to add oracle
     *@param _oracle chainlink oracle address
     */
    function addOracle(address _asset, address _oracle) external onlyOwner {
        oracleAsset[_asset] = _oracle;
    }

    /**
    @dev deposit asset to the vault,
    @param _token asset authorized 
    @param _amount amount of asset the user wish to deposit 
    */
    function deposit(address _token, uint256 _amount)
        external
        returns (uint256)
    {
        if (!isAllowedAsset[_token]) revert InvalidAsset();
        uint256 tokenDecimals = ERC20(_token).decimals();
        // usd value of the asset
        uint256 depositValue = ((_amount / 10**tokenDecimals) *
            getAssetPrice(_token)) / 10**8;
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        // get vault total value
        uint256 mintAmount = _issueShares(depositValue);
        _mint(msg.sender, mintAmount);
        sharesForTokens[msg.sender][_token] += mintAmount;
        emit Deposit(msg.sender, _token, _amount);
        return mintAmount;
    }

    /**
     *@notice withdraw token using the shares the users have
     *@param _token token to withdraw
     *@param _shares to burn
     */
    function withdraw(address _token, uint256 _shares) external {
        if (!isAllowedAsset[_token]) revert InvalidAsset();
        if (sharesForTokens[msg.sender][_token] < _shares)
            revert InsufficientSharesBalance();
        // uint256 tokenDecimals = ERC20(_token).decimals();
        uint256 shares = _calcShares(_shares);
        uint256 decimal = ERC20(_token).decimals();
        sharesForTokens[msg.sender][_token] -= _shares;
        _burn(msg.sender, _shares);
        uint256 amountInUSD = (shares / 10**18) * 10**decimal;
        // get amount corresponding the price
        // vault is subject to some dusts because of price exponent
        uint256 amountAsset = getAmountOfByPrice(
            _token,
            amountInUSD / 10**decimal
        );
        // verify if user have enough amount of funds in the vaul
        // the vault could rebalance and the asset amount could be inferior to what the user deposit
        // sends amount if the shares value is > to the vault amount
        if (IERC20(_token).balanceOf(address(this)) < amountAsset)
            amountAsset = IERC20(_token).balanceOf(address(this));
        // transfer the token
        IERC20(_token).transfer(msg.sender, amountAsset);
        emit Withdrawn(msg.sender, _token, amountAsset);
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
    *@return ratioA ratio of tokenA 
    *@return ratioB ratio of tokenB
    */
    function getVaultCurrentRatio(address _tokenA, address _tokenB)
        public
        view
        returns (uint256 ratioA, uint256 ratioB)
    {
        uint256 priceTokenA = getAssetPrice(_tokenA);
        uint256 priceTokenB = getAssetPrice(_tokenB);
        uint256 decimalsA = ERC20(_tokenA).decimals();
        uint256 decimmalsB = ERC20(_tokenB).decimals();
        uint256 totalWeightA = ((IERC20(_tokenA).balanceOf(address(this)) /
            10**decimalsA) * priceTokenA) / 10**8;
        uint256 totalWeightB = ((IERC20(_tokenB).balanceOf(address(this)) /
            10**decimmalsB) * priceTokenB) / 10**8;
        unchecked {
            ratioA = (totalWeightA * 10000) / (totalWeightA + totalWeightB);
            ratioB = 10000 - ratioA;
        }

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
     *@return value value of asset in the vault
     */
    function getValueAssetInVault(address _asset)
        public
        view
        returns (uint256 value)
    {
        uint256 decimal = ERC20(_asset).decimals();
        uint256 balance = IERC20(_asset).balanceOf(address(this));
        uint256 price = getAssetPrice(_asset);
        unchecked {
            value = (balance * price) / 10**(decimal + 8);
        }
    }

    /**
     *@dev determine the amount of token corresponding a value in USD
     *@param _asset asset address we want to determine the amount
     *@param _valueUSD value of USD to determine the amount of token
     */
    function getAmountOfByPrice(address _asset, uint256 _valueUSD)
        public
        view
        returns (uint256 amount)
    {
        uint256 price = getAssetPrice(_asset);
        uint256 decimal = ERC20(_asset).decimals();
        unchecked {
            amount = (_valueUSD * 10**(decimal + 8)) / price;
        }
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
        uint256 amountUpdate = _amount * 10**decimals();
        if (totalSupply() > 0) {
            return (amountUpdate * totalSupply()) / totalAsset();
        } else {
            return amountUpdate;
        }
    }

    /**
     *@dev function to return the shares a user have for a particular asset
     */
    function getSharesForToken(address _token) external view returns (uint256) {
        return sharesForTokens[msg.sender][_token];
    }

    /**
     *@dev calculate the token amount corresponding the value
     *@param _shares shares to get the amount
     */
    function _calcShares(uint256 _shares) internal view returns (uint256) {
        return (_shares * totalAsset()) / totalSupply();
    }

    /**
    determine the total usd value of the assets contains in the vault 
    */
    function totalAsset() public view returns (uint256 totalAssets) {
        address token0 = token[0];
        address token1 = token[1];
        uint256 valueToken0 = getValueAssetInVault(token0);
        uint256 valueToken1 = getValueAssetInVault(token1);
        unchecked {
            totalAssets = (valueToken0 + valueToken1) * 10**decimals();
        }
    }
}
