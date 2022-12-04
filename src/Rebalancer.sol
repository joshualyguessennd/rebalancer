// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IVanillaVault.sol";

// todo add logic for more pair
// write the tests
// add keeper
contract Rebalancer is Ownable {
    using SafeMath for uint256;
    // use uniswap v2

    address public immutable tokenA =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // usdc
    address public immutable tokenB =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // weth

    address public immutable oraclePriceTokenB =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // oracle ETH // add more oracle for more tokens

    address public vault;

    uint256 public interval;

    mapping(address => uint256) public targetRatio; // ratio tokens

    constructor(address _vault) {
        vault = _vault;
    }

    /**
     *@dev set the desire ratio to rebalance the vault
     *@param _token token we want set the ratio
     *@param _ratio desired ratio for the _token
     */
    function setRatio(address _token, uint256 _ratio) public onlyOwner {
        targetRatio[_token] = _ratio;
        if (_token == tokenA) {
            targetRatio[tokenB] = 10000 - targetRatio[tokenA];
        } else {
            targetRatio[tokenA] = 10000 - targetRatio[tokenB];
        }
    }

    /**
     *@dev function to set the interval the keep will call the rebalance function
     *@param _interval interval of time the rebalancer will rebalance the vault
     */
    function setInverval(uint256 _interval) public onlyOwner {
        interval = _interval;
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice(address _oracle_address)
        internal
        view
        returns (uint256)
    {
        (, int256 price, , , ) = AggregatorV3Interface(_oracle_address)
            .latestRoundData();
        return uint256(price);
    }

    /**
     *@dev rebalance ratio of token A and tokenB in the vault
     * the function get the desired ratio for token A and token B
     * verify the current ratio in the vault and execute the swap following the outcome of the current ratio
     */
    function rebalance() external {
        uint256 tokenADesiredRatio = targetRatio[tokenA];
        uint256 tokenBDesiredRatio = targetRatio[tokenB];
        (uint256 ratioA, uint256 ratioB) = IVanillaVault(vault)
            .getVaultCurrentRatio(tokenA, tokenB);
        uint256 valueTokenA = IVanillaVault(vault).getValueAssetInVault(tokenA);
        uint256 valueTokenB = IVanillaVault(vault).getValueAssetInVault(tokenB);
        uint256 totalVaultValue = valueTokenA + valueTokenB;
        address[] memory path;
        path = new address[](2);
        path[0] = tokenA;
        path[0] = tokenB;
        if (ratioA > tokenADesiredRatio) {
            uint256 amountA = (totalVaultValue * tokenADesiredRatio);
            uint256 amountUSDToSwap = valueTokenA - amountA.div(10**4);
            uint256 amount = IVanillaVault(vault).getAmountOfByPrice(
                tokenA,
                amountUSDToSwap
            );
            IVanillaVault(vault).executeSwap(tokenA, tokenB, amount);
        } else if (ratioB > tokenBDesiredRatio) {
            uint256 amountA = (totalVaultValue * tokenBDesiredRatio);
            uint256 amountUSDToSwap = valueTokenB - amountA.div(10**4);
            uint256 amount = IVanillaVault(vault).getAmountOfByPrice(
                tokenB,
                amountUSDToSwap
            );
            IVanillaVault(vault).executeSwap(tokenB, tokenA, amount);
        }
    }

    function getRatio() external view returns (uint256, uint256) {
        uint256 ratioWETH = targetRatio[tokenB];
        uint256 ratioUSD = targetRatio[tokenA];
        return (ratioUSD, ratioWETH);
    }
}
