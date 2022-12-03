// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IVanillaVault {
    function executeSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 amount
    ) external;
}
