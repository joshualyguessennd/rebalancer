// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IVanillaVault.sol";

contract Rebalancer is Ownable {
    using SafeMath for uint256;

    address public vault;

    uint256 public interval;
    uint256 public lastRebalance;

    mapping(uint256 => uint256) public targetRatio; // ratio tokens

    error TimeRequirementNotMeet();

    constructor(address _vault) {
        vault = _vault;
    }

    /**
     *@dev set the desire ratio to rebalance the vault, vault has 2 tokens
     *@param _index to set the ratio
     *@param _ratio desired ratio for the _token
     */
    function setRatio(uint256 _index, uint256 _ratio) public onlyOwner {
        require(_index < 2, "invalid index");
        targetRatio[_index] = _ratio;
        if (_index == 0) {
            targetRatio[1] = 10000 - targetRatio[0];
        } else {
            targetRatio[0] = 10000 - targetRatio[1];
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
     *@dev rebalance ratio of token A and tokenB in the vault
     * the function get the desired ratio for token A and token B
     * verify the current ratio in the vault and execute the swap following the outcome of the current ratio
     */
    function rebalance() external {
        if (lastRebalance + interval > block.timestamp)
            revert TimeRequirementNotMeet();
        address tokenA = IVanillaVault(vault).getToken(0);
        address tokenB = IVanillaVault(vault).getToken(1);
        uint256 tokenADesiredRatio = targetRatio[0];
        uint256 tokenBDesiredRatio = targetRatio[1];
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
        lastRebalance = block.timestamp;
    }

    /**
    @dev get the ratio desired for the tokens 
    */
    function getRatio() external view returns (uint256, uint256) {
        uint256 ratioToken1 = targetRatio[1];
        uint256 ratioToken0 = targetRatio[0];
        return (ratioToken0, ratioToken1);
    }
}
