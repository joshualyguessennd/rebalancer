// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/VanillaVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        deal(usdc, user, 1000e6);
        deal(weth, user, 1000e18);
    }

    function test_deposit() public {
        vm.prank(user);
        IERC20(usdc).approve(address(vault), 100e6);
        vm.expectRevert(InvalidAsset.selector);
        vault.deposit(usdc, 100e6);
        _depositToVault(100e6, 100e18);
        uint256 userVaultBalance = IERC20(vault).balanceOf(user);
        // assertEq(IERC20(weth).balanceOf(address(vault)), 100e18);
        assertEq(IERC20(usdc).balanceOf(address(vault)), 100e6);
        console.log(userVaultBalance);
        // assertEq(IERC20(address(vault)).balanceOf(user), 200e18);
    }

    // function test_withdraw() public {
    //     _depositToVault(100e6, 100e18);
    //     // withdraw
    //     vm.startPrank(user);
    //     vault.withdraw(usdc, 100e18);
    //     // withdraw amount > amountDeposited
    //     vm.expectRevert(InsufficientSharesBalance.selector);
    //     vault.withdraw(usdc, 100e18);
    //     // verify is balance usdc of vault is empty
    //     assertEq(IERC20(usdc).balanceOf(address(vault)), 0);
    // }

    function _depositToVault(uint256 amountUSDC, uint256 amountWETH) public {
        vm.startPrank(owner);
        vault.addNewERC20(0, usdc);
        vault.addNewERC20(1, weth);
        vault.addOracle(usdc, oracleUSDC);
        vault.addOracle(weth, oracleWETH);
        vm.stopPrank();
        vm.startPrank(user);
        IERC20(usdc).approve(address(vault), 100e6);
        (uint256 valueUSD, uint256 totalValue1) = vault.deposit(
            usdc,
            amountUSDC
        );
        console.log("value usd", valueUSD, totalValue1);
        IERC20(weth).approve(address(vault), amountWETH);
        (uint256 valueWETH, uint256 totalValue2) = vault.deposit(
            weth,
            amountWETH
        );
        console.log("value weth", valueWETH, totalValue2);
        vm.stopPrank();
    }
}
