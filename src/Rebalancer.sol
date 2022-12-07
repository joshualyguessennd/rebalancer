// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./interfaces/IVanillaVault.sol";

contract Rebalancer is Ownable {
    address public vault;
    address public keeper;

    uint256 public interval;
    uint256 public lastRebalance;

    mapping(uint256 => uint256) public targetRatio; // ratio tokens

    error TimeRequirementNotMeet();
    error NotKeeper();

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
     *@dev set keeper address, keeper is a chainlink bot like to automate task on the blockchain
     *@param _keeper address of keeper
     */
    function setKeeper(address _keeper) public onlyOwner {
        keeper = _keeper;
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
        if (msg.sender != keeper) revert NotKeeper();
        if (lastRebalance + interval > block.timestamp)
            revert TimeRequirementNotMeet();
        uint256 totalVaultValue;
        // get the two assets present in the vault
        address tokenA = IVanillaVault(vault).getToken(0);
        address tokenB = IVanillaVault(vault).getToken(1);
        // get the desired token ratio
        uint256 tokenADesiredRatio = targetRatio[0];
        uint256 tokenBDesiredRatio = targetRatio[1];
        // get the ratio present of the vault
        (uint256 ratioA, uint256 ratioB) = IVanillaVault(vault)
            .getVaultCurrentRatio(tokenA, tokenB);
        // get the value asset in the vault
        uint256 valueTokenA = IVanillaVault(vault).getValueAssetInVault(tokenA);
        uint256 valueTokenB = IVanillaVault(vault).getValueAssetInVault(tokenB);
        unchecked {
            totalVaultValue = valueTokenA + valueTokenB;
        }
        // verify the ratio and rebalance when necessary
        if (ratioA > tokenADesiredRatio) {
            uint256 amountA = (totalVaultValue * tokenADesiredRatio);
            uint256 amountUSDToSwap = valueTokenA - amountA / 10**4;
            uint256 amount = IVanillaVault(vault).getAmountOfByPrice(
                tokenA,
                amountUSDToSwap
            );
            IVanillaVault(vault).executeSwap(tokenA, tokenB, amount);
        } else if (ratioB > tokenBDesiredRatio) {
            uint256 amountA = (totalVaultValue * tokenBDesiredRatio);
            uint256 amountUSDToSwap = valueTokenB - amountA / 10**4;
            uint256 amount = IVanillaVault(vault).getAmountOfByPrice(
                tokenB,
                amountUSDToSwap
            );
            IVanillaVault(vault).executeSwap(tokenB, tokenA, amount);
        }
        // update last rebalance for interval verification
        lastRebalance = block.timestamp;
    }

    function getNexMinTime() external view returns (uint256) {
        return lastRebalance + interval;
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
