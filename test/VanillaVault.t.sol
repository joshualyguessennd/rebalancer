// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/VanillaVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VaultTest is Test {
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public oracleWETH = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public oracleUSDC = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public owner = address(12);
    address public user = address(13);
    VanillaVault vault;

    error InvalidAsset();
    error InsufficientSharesBalance();

    function setUp() public {
        vm.prank(owner);
        vault = new VanillaVault();
        deal(usdc, user, 100200e6);
        deal(weth, user, 1000e18);
    }

    function test_deposit() public {
        vm.prank(user);
        IERC20(usdc).approve(address(vault), 100e6);
        vm.expectRevert(InvalidAsset.selector);
        vault.deposit(usdc, 100e6);
        _depositToVault(100e6);
        uint256 userVaultBalance = IERC20(vault).balanceOf(user);
        assertEq(IERC20(usdc).balanceOf(address(vault)), 100e6);
        console.log(userVaultBalance);
    }

    function test_withdraw() public {
        uint256 balanceUserBefore = IERC20(usdc).balanceOf(user);
        _depositToVault(100e6);
        uint256 vaultValueBefore = vault.getValueAssetInVault(usdc);
        assertEq(vaultValueBefore, 100); // should be equal to 100 USD
        uint256 balanceShare = IERC20(address(vault)).balanceOf(user);
        vm.prank(user);
        vault.withdraw(usdc, balanceShare);
        uint256 balanceUSDVault = IERC20(usdc).balanceOf(address(vault));
        uint256 balanceUserAfter = IERC20(usdc).balanceOf(user);
        console.log(balanceUSDVault);
        uint256 vaultValueAfter = vault.getValueAssetInVault(usdc);
        assertEq(vaultValueAfter, 0);
        // we have some dust because of the chainlink price exponentiel
        assert(balanceUserBefore - balanceUserAfter < 10**2);
        vm.expectRevert();
        vault.withdraw(usdc, balanceShare);
    }

    function _depositToVault(uint256 amountUSDC) public {
        vm.startPrank(owner);
        vault.addNewERC20(0, usdc);
        vault.addNewERC20(1, weth);
        vault.addOracle(usdc, oracleUSDC);
        vault.addOracle(weth, oracleWETH);
        vm.stopPrank();
        vm.startPrank(user);
        IERC20(usdc).approve(address(vault), amountUSDC);
        vault.deposit(usdc, amountUSDC);
        vm.stopPrank();
    }
}
