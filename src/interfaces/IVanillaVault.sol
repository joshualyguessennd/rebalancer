// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface IVanillaVault {
    function executeSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 amount
    ) external;

    function getVaultCurrentRatio(address _assetA, address _assetB)
        external
        returns (uint256, uint256);

    function getAmountOfByPrice(address _asset, uint256 _amount)
        external
        returns (uint256);

    function getValueAssetInVault(address _asset) external returns (uint256);

    function isAllowedToken(address _asset) external returns (uint256);

    function getToken(uint256 _index) external returns (address);
}
