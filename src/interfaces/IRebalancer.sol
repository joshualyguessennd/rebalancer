// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface IRebalancer {
    function rebalance() external;

    function getRatio() external returns (uint256);

    function getNexMinTime() external returns (uint256);
}
