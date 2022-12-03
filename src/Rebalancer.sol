// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./interfaces/IVanillaVault.sol";

// todo add logic for more pair
// write the tests
// add keeper
contract Rebalancer is Ownable {
    // use uniswap v2

    address public immutable tokenA =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // usdc
    address public immutable tokenB =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // weth

    address public immutable oraclePriceTokenB =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // oracle ETH // add more oracle for more tokens

    address public vault;

    uint256 interval;

    mapping(address => uint256) public targetRatio; // ratio tokens

    constructor(address _vault) {
        vault = _vault;
    }

    // set the ratio for the pair of token (we should optimize for N tokens)
    function setRatio(address _token, uint256 _ratio) public onlyOwner {
        targetRatio[_token] = _ratio;
    }

    // function to set the interval the keep will call the rebalance function
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
    @dev get the current ratio of weth and usd in the vault
    for a contract that can take n token we need to set add more oracle price 
    */
    function _getVaultCurrentRatio() internal view returns (uint256, uint256) {
        uint256 priceWeth = getLatestPrice(oraclePriceTokenB);
        uint256 totalWeightWeth = IERC20(vault).balanceOf(tokenB) * priceWeth;
        uint256 totalWeightUSD = IERC20(vault).balanceOf(tokenA);

        uint256 ratioUSD = (totalWeightUSD /
            (totalWeightUSD + totalWeightWeth)) * 10000;
        uint256 ratioWeth = 10000 - ratioUSD;
        return (ratioWeth, ratioUSD);
    }

    /**
     *@dev rebalance ratio of token A and tokenB in the vault
     * the function get the desired ratio for token A and token B
     * verify the current ratio in the vault and execute the swap following the outcome of the current ratio
     */
    function rebalance() external {
        uint256 tokenADesiredRatio = targetRatio[tokenA];
        uint256 tokenBDesiredRatio = targetRatio[tokenB];
        (uint256 ratioB, uint256 ratioA) = _getVaultCurrentRatio();
        address[] memory path;
        path = new address[](2);
        path[0] = tokenA;
        path[0] = tokenB;
        // if token ratio is > desired ratio , compute the exceeds amount of token and swap it to the other token
        if (ratioA > tokenADesiredRatio) {
            uint256 amountUSD = IERC20(tokenA).balanceOf(vault);
            uint256 amountToSwap = ((tokenADesiredRatio - ratioA) * amountUSD) /
                10000;
            IVanillaVault(vault).executeSwap(tokenA, tokenB, amountToSwap);
        } else if (ratioB > tokenBDesiredRatio) {
            uint256 price = IERC20(tokenB).balanceOf(vault) *
                getLatestPrice(oraclePriceTokenB);
            uint256 amountToSwap = ((tokenBDesiredRatio - ratioB) * price) /
                10000;
            IVanillaVault(vault).executeSwap(tokenB, tokenA, amountToSwap);
        }
    }
}
