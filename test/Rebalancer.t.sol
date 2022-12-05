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

    error TimeRequirementNotMeet();
    error NotKeeper();
    error InvalidAsset();
    error InsufficientSharesBalance();
    error InsufficientBalance();
    error unauthorizedAccess();
    error MaxTokenCount();

    function setUp() public {
        vm.startPrank(owner);
        vault = new VanillaVault();
        rebalancer = new Rebalancer(address(vault));
        rebalancer.setKeeper(owner);
        vm.stopPrank();
        deal(usdc, user, 200000e6);
        deal(weth, user, 1000e18);
    }

    /**
    test setter function 
    */
    function test_setter() public {
        vm.expectRevert();
        rebalancer.setRatio(1, 6000);
        vm.expectRevert();
        rebalancer.setInverval(6000);
        vm.startPrank(owner);
        rebalancer.setRatio(1, 5000);
        (uint256 RatioUSD, uint256 RatioWETH) = rebalancer.getRatio();
        assertEq(RatioWETH, 5000);
        assertEq(RatioUSD, 5000);
        rebalancer.setInverval(5000);
        assertEq(rebalancer.interval(), 5000);
    }

    /**
    test balancer function 
    */
    function test_balancer() public {
        vm.startPrank(owner);
        vault.addOracle(weth, oracleWETH);
        vault.addOracle(usdc, oracleUSDC);
        vault.addNewERC20(0, usdc);
        vault.addNewERC20(1, weth);
        rebalancer.setRatio(0, 5000);
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
        // unauthorized access to vault swap
        vm.startPrank(owner);
        vm.expectRevert(unauthorizedAccess.selector);
        rebalancer.rebalance();
        vault.setBalancer(address(rebalancer));
        rebalancer.rebalance();
        vm.stopPrank();
        (uint256 new_ratioA, uint256 new_ratioB) = vault.getVaultCurrentRatio(
            usdc,
            weth
        );
        console.log("new ratio of tokenA", new_ratioA);
        console.log("new ratio of tokenB", new_ratioB);
        // ratio has some dust due to price of and chainlink price exponent
        assert(new_ratioA - 5000 <= 3);
        assert(5000 - new_ratioB <= 3);
        // test keeper
        vm.prank(user);
        vm.expectRevert(NotKeeper.selector);
        rebalancer.rebalance();

        vm.startPrank(owner);
        rebalancer.setInverval(86400);
        vm.expectRevert(TimeRequirementNotMeet.selector);
        rebalancer.rebalance();
        vm.stopPrank();

        // change ratio
        vm.startPrank(owner);
        rebalancer.setRatio(0, 8000);
        vm.warp(block.timestamp + 86400);
        rebalancer.rebalance();
        (new_ratioA, new_ratioB) = vault.getVaultCurrentRatio(usdc, weth);
        console.log("new ratio of tokenA", new_ratioA);
        console.log("new ratio of tokenB", new_ratioB);
        vm.stopPrank();
    }
}
