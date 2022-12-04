// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/VanillaVault.sol";
import "../src/Rebalancer.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RebalancerTest is Test {
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public oracleWETH = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public oracleUSDC = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public owner = address(12);
    address public user = address(13);
    VanillaVault vault;
    Rebalancer rebalancer;

    function setUp() public {
        vm.startPrank(owner);
        vault = new VanillaVault();
        rebalancer = new Rebalancer(address(vault));
        vm.stopPrank();
        deal(usdc, user, 200000e6);
        deal(weth, user, 1000e18);
    }

    function test_setter() public {
        vm.expectRevert();
        rebalancer.setRatio(weth, 6000);
        vm.expectRevert();
        rebalancer.setInverval(6000);
        vm.startPrank(owner);
        rebalancer.setRatio(weth, 5000);
        (uint256 RatioUSD, uint256 RatioWETH) = rebalancer.getRatio();
        assertEq(RatioWETH, 5000);
        assertEq(RatioUSD, 5000);
        rebalancer.setInverval(5000);
        assertEq(rebalancer.interval(), 5000);
    }

    function test_balancer() public {
        vm.startPrank(owner);
        vault.addOracle(weth, oracleWETH);
        vault.addOracle(usdc, oracleUSDC);
        vault.addNewERC20(usdc);
        vault.addNewERC20(weth);
        rebalancer.setRatio(usdc, 5000);
        vm.stopPrank();
        vm.startPrank(user);
        IERC20(usdc).approve(address(vault), 200000e6);
        vault.deposit(usdc, 200000e6);
        IERC20(weth).approve(address(vault), 100e18);
        vault.deposit(weth, 100e18);
        vm.stopPrank();

        // get value assets
        uint256 valueA = vault.getValueAssetInVault(usdc);
        uint256 valueB = vault.getValueAssetInVault(weth);
        console.log("value of tokenA", valueA);
        console.log("value of tokenB", valueB);

        // get the ratio of asset of the vault
        (uint256 ratioA, uint256 ratioB) = vault.getVaultCurrentRatio(
            usdc,
            weth
        );
        console.log("ratio of tokenA", ratioA);
        console.log("ratio of tokenB", ratioB);
        assert(ratioA > ratioB);

        // test rebalance
        vm.expectRevert();
        rebalancer.rebalance();
        vm.prank(owner);
        vault.setBalancer(address(rebalancer));
        rebalancer.rebalance();
        (uint256 new_ratioA, uint256 new_ratioB) = vault.getVaultCurrentRatio(
            usdc,
            weth
        );
        console.log("new ratio of tokenA", new_ratioA);
        console.log("new ratio of tokenB", new_ratioB);

        uint256 new_valueA = vault.getValueAssetInVault(usdc);
        uint256 new_valueB = vault.getValueAssetInVault(weth);
        console.log("new value of tokenA", new_valueA);
        console.log("new value of tokenB", new_valueB);
    }
}
