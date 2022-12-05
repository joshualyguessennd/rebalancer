// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../src/interfaces/IRebalancer.sol";

contract KeeperManager is Ownable {
    address public registryContract;
    uint256 public coolDown;
    uint256 public lastTimeStamp;

    error UnauthorizedRight();

    event CoolDownSet(uint256 cooldown);
    event RegistryContractSet(address indexed registryContract);

    function initialize(uint256 _coolDown, address _registryContract)
        external
        onlyOwner
    {
        coolDown = _coolDown;
        registryContract = _registryContract;
    }

    function setCoolDown(uint256 _coolDown) external onlyOwner {
        coolDown = _coolDown;
        emit CoolDownSet(_coolDown);
    }

    function setRegistryContract(address _registryContract) external onlyOwner {
        registryContract = _registryContract;
        emit RegistryContractSet(_registryContract);
    }

    function checkUpkeep(bytes calldata checkData)
        external
        returns (bool isTimeFavorable, bytes memory performData)
    {
        address rebalancer = abi.decode(checkData, (address));
        isTimeFavorable =
            IRebalancer(rebalancer).getNexMinTime() < block.timestamp;
        performData = checkData;
    }

    function performUpkeep(bytes calldata performData) external {
        if (msg.sender != registryContract) revert UnauthorizedRight();
        address rebalancer = abi.decode(performData, (address));
        lastTimeStamp = block.timestamp;
        if (IRebalancer(rebalancer).getNexMinTime() < block.timestamp) {
            IRebalancer(rebalancer).rebalance();
        }
    }
}
