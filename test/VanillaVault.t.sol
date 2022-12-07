// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/VanillaVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/Rebalancer.sol";

contract VaultTest is Test {
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public oracleWETH = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public oracleUSDC = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public owner = address(12);
    address public user = address(13);

    mapping(address => address) public oracleAsset;

    VanillaVault vault;
    Rebalancer rebalancer;

    error InvalidAsset();
    error InsufficientSharesBalance();

    function setUp() public {
        vm.startPrank(owner);
        vault = new VanillaVault();
        rebalancer = new Rebalancer(address(vault));
        rebalancer.setRatio(0, 4000);
        vault.setBalancer(address(rebalancer));
        rebalancer.setKeeper(owner);
        vm.stopPrank();
        deal(usdc, user, 100200e6);
        deal(weth, user, 1000e18);
        oracleAsset[usdc] = oracleUSDC;
        oracleAsset[weth] = oracleWETH;
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

    function test_deposit_withdraw_fuzz(uint256 a) public {
        vm.assume(a != 1);
        _depositToVault(100e6);
        assertEq(IERC20(usdc).balanceOf(address(vault)), 100e6);
        console.log("deposit", IERC20(usdc).balanceOf(address(vault)));
        vm.startPrank(user);
        uint256 balanceShares = vault.getSharesForToken(usdc);
        console.log("shares", balanceShares);
        vault.withdraw(usdc, balanceShares);
        // add decimals for dust
        assertEq(IERC20(usdc).balanceOf(address(vault)) / 10**6, 0);
        // deposit two tokens
        vm.stopPrank();

        _depositToVault(20000e6);
        vm.startPrank(user);
        IERC20(weth).approve(address(vault), 100e18);
        vault.deposit(weth, 100e18);
        uint256 shares = vault.getSharesForToken(usdc);
        uint256 sharesweth = vault.getSharesForToken(weth);
        // take in count dust for the last deposit
        assertEq(
            IERC20(usdc).balanceOf(address(vault)) / 10**6,
            20000e6 / 10**6
        );
        assertEq(IERC20(weth).balanceOf(address(vault)), 100e18);
        vault.withdraw(usdc, shares);
        vault.withdraw(weth, sharesweth);
        assertEq(IERC20(usdc).balanceOf(address(vault)) / 10**6, 0);
        // dust on price due to price 10**8 div
        assert(IERC20(weth).balanceOf(address(vault)) < 10**16);
        vm.stopPrank();
    }

    function test_getToken() public {
        vm.startPrank(owner);
        vault.addNewERC20(0, usdc);
        vault.addNewERC20(1, weth);
        assertEq(usdc, vault.getToken(0));
        assertEq(weth, vault.getToken(1));
    }

    function test_withdraw_default() public {
        uint256 balanceUserBefore = IERC20(usdc).balanceOf(user);
        _depositToVault(100e6);
        uint256 vaultValueBefore = vault.getValueAssetInVault(usdc);
        uint256 price = getAssetPrice(usdc);
        uint256 balanceVault = IERC20(usdc).balanceOf(address(vault));
        uint256 value = ((balanceVault / 10**6) * price) / 10**8;
        assertEq(vaultValueBefore, value); // should be equal to 100 USD
        vm.startPrank(user);
        uint256 balanceShare = vault.getSharesForToken(usdc);
        console.log("les balances shares", balanceShare);
        vault.withdraw(usdc, balanceShare);
        uint256 balanceUSDVault = IERC20(usdc).balanceOf(address(vault));
        uint256 balanceUserAfter = IERC20(usdc).balanceOf(user);
        console.log(balanceUSDVault);
        uint256 vaultValueAfter = vault.getValueAssetInVault(usdc);
        assertEq(vaultValueAfter, 0);
        // we have some dust because of the chainlink price exponentiel
        assert((balanceUserBefore - balanceUserAfter) / 10**6 < 10);
        console.log(balanceUserBefore, balanceUserAfter);
        vm.expectRevert();
        vault.withdraw(usdc, balanceShare);
        vm.stopPrank();
    }

    /**
    test deposit 2 assets and withdraw one of them, 
    */
    function test_withdraw_with_2_assets() public {
        _depositToVault(50000e6);
        console.log("usdc shares", vault.getSharesForToken(usdc));
        uint256 vaultValueBefore = vault.getValueAssetInVault(usdc);
        uint256 price = getAssetPrice(usdc);
        uint256 balanceVault = IERC20(usdc).balanceOf(address(vault));
        uint256 value = ((balanceVault / 10**6) * price) / 10**8;
        assertEq(vaultValueBefore, value); // should be equal to 100 USD
        vm.startPrank(user);
        IERC20(weth).approve(address(vault), 100e18);
        vault.deposit(weth, 100e18);
        // get value price
        IERC20(usdc).approve(address(vault), 50000e6);
        vault.deposit(usdc, 50000e6);
        // get the different shares
        uint256 sharesUSDC = vault.getSharesForToken(usdc);
        uint256 sharesETH = vault.getSharesForToken(weth);
        assertEq(IERC20(weth).balanceOf(address(vault)), 100e18);
        // withdraw usdc and see if vault is empty
        vault.withdraw(usdc, sharesUSDC);
        assertEq(IERC20(usdc).balanceOf(address(vault)), 0);
        // withdraw more than shares for a token in the vault
        vm.expectRevert();
        vault.withdraw(weth, sharesUSDC + sharesETH);
        vm.stopPrank();
    }

    /**
     * test vault withdraw after rebalancing
     * the amount of tokenA and tokenB is split following rebalancer desired ratio
     * user should have inferior or > amount following the ratio
     */
    function test_withdraw_after_rebalancing() public {
        uint256 balanceUserBefore = IERC20(usdc).balanceOf(user);
        _depositToVault(50000e6);
        uint256 balanceUSD = IERC20(usdc).balanceOf(address(vault));
        vm.prank(user);
        uint256 shares = vault.getSharesForToken(usdc);
        console.log("shares usdc", shares);
        console.log("balanceUSD", balanceUSD);
        vm.prank(owner);
        rebalancer.rebalance();
        console.log(
            "new balance usdc vault",
            IERC20(usdc).balanceOf(address(vault))
        );
        console.log("user shares", IERC20(address(vault)).balanceOf(user));
        vm.prank(user);
        vault.withdraw(usdc, shares);

        uint256 balanceAfter = IERC20(usdc).balanceOf(user);
        assert(balanceAfter < balanceUserBefore);
        assertEq(IERC20(usdc).balanceOf(address(vault)), 0);
        console.log("new user usd balance", IERC20(usdc).balanceOf(user));
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
        uint256 amount = vault.deposit(usdc, amountUSDC);
        console.log("deposit mint", amount);
        vm.stopPrank();
    }

    function getAssetPrice(address _asset) internal view returns (uint256) {
        address _oracle = oracleAsset[_asset];
        (, int256 price, , , ) = AggregatorV3Interface(_oracle)
            .latestRoundData();
        return uint256(price);
    }
}
