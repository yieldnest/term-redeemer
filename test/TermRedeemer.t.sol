// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockMaxVault} from "./mocks/MockMaxVault.sol";
import {TermRedeemer, TermReceiptToken} from "../src/TermRedeemer.sol";

contract TermRedeemerTest is Test {
    uint64 internal constant LOCK_START = 100;
    uint64 internal constant LOCK_END = 200;
    uint64 internal constant REDEEM_START = 300;

    MockERC20 internal usdc;
    MockMaxVault internal vault;
    TermRedeemer internal redeemer;
    TermReceiptToken internal receipt;

    address internal constant OWNER = address(0xA11CE);
    address internal constant ALICE = address(0xB0B);
    address internal constant BOB = address(0xCAFE);
    address internal constant RESIDUAL_PULLER = address(0xD00D);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = new MockMaxVault(address(usdc), "ynMAX", "ynMAX", 18);
        redeemer = new TermRedeemer(OWNER, address(vault), RESIDUAL_PULLER, LOCK_START, LOCK_END, REDEEM_START);
        receipt = redeemer.receiptToken();

        vault.mintShares(ALICE, 150 ether);
        vault.mintShares(BOB, 50 ether);
        usdc.mint(address(vault), 1_000_000e6);

        vm.prank(ALICE);
        vault.approve(address(redeemer), type(uint256).max);

        vm.prank(BOB);
        vault.approve(address(redeemer), type(uint256).max);
    }

    function test_LockMintsOneToOneReceiptDuringWindow() public {
        vm.warp(LOCK_START);

        vm.prank(ALICE);
        uint256 minted = redeemer.lock(10 ether, ALICE);

        assertEq(minted, 10 ether);
        assertEq(receipt.balanceOf(ALICE), 10 ether);
        assertEq(vault.balanceOf(ALICE), 140 ether);
        assertEq(vault.balanceOf(address(redeemer)), 10 ether);
    }

    function test_LockRevertsOutsideWindow() public {
        vm.expectRevert("TermRedeemer: lock not started");
        vm.prank(ALICE);
        redeemer.lock(1 ether, ALICE);

        vm.warp(LOCK_END);
        vm.expectRevert("TermRedeemer: lock closed");
        vm.prank(ALICE);
        redeemer.lock(1 ether, ALICE);
    }

    function test_RedemptionUsesRateLockedAtEndOfLockPhase() public {
        vm.warp(LOCK_START);
        vm.prank(ALICE);
        redeemer.lock(100 ether, ALICE);

        vault.setAssetsPerShare(2e6);

        vm.warp(LOCK_END);
        uint256 lockedRate = redeemer.lockRedemptionRate();
        assertEq(lockedRate, 2e6);

        vault.setAssetsPerShare(3e6);

        vm.warp(REDEEM_START);
        vm.prank(OWNER);
        redeemer.prepareRedemption();

        vm.prank(ALICE);
        uint256 redeemed = redeemer.redeem(100 ether, ALICE);

        assertEq(redeemed, 200e6);
        assertEq(usdc.balanceOf(ALICE), 200e6);
    }

    function test_PrepareRedemptionWithdrawsExactAssetsAndApprovesResidualShares() public {
        vm.warp(LOCK_START);

        vm.prank(ALICE);
        redeemer.lock(100 ether, ALICE);

        vm.prank(BOB);
        redeemer.lock(50 ether, BOB);

        vault.setAssetsPerShare(2e6);

        vm.warp(REDEEM_START);

        vm.prank(OWNER);
        (uint256 assetsNeeded, uint256 residualShares) = redeemer.prepareRedemption();

        assertEq(assetsNeeded, 300e6);
        assertEq(usdc.balanceOf(address(redeemer)), 300e6);
        assertEq(residualShares, 0);
        assertEq(vault.allowance(address(redeemer), RESIDUAL_PULLER), 0);
    }

    function test_PrepareRedemptionLeavesResidualSharesForTrustedSpenderWhenYieldAccruedAfterSnapshot() public {
        vm.warp(LOCK_START);
        vm.prank(ALICE);
        redeemer.lock(100 ether, ALICE);

        vault.setAssetsPerShare(2e6);

        vm.warp(LOCK_END);
        redeemer.lockRedemptionRate();

        vault.setAssetsPerShare(4e6);

        vm.warp(REDEEM_START);
        vm.prank(OWNER);
        (, uint256 residualShares) = redeemer.prepareRedemption();

        assertEq(usdc.balanceOf(address(redeemer)), 200e6);
        assertEq(residualShares, 50 ether);
        assertEq(vault.allowance(address(redeemer), RESIDUAL_PULLER), 50 ether);
    }

    function test_RedeemRevertsBeforeMaturity() public {
        vm.warp(LOCK_START);
        vm.prank(ALICE);
        redeemer.lock(10 ether, ALICE);

        vm.warp(LOCK_END);
        redeemer.lockRedemptionRate();

        vm.expectRevert("TermRedeemer: redeem not started");
        vm.prank(ALICE);
        redeemer.redeem(10 ether, ALICE);
    }

    function test_ReceiptCanTradeBeforeRedemptionAndHolderCanRedeem() public {
        vm.warp(LOCK_START);
        vm.prank(ALICE);
        redeemer.lock(40 ether, ALICE);

        vm.prank(ALICE);
        receipt.transfer(BOB, 15 ether);

        vault.setAssetsPerShare(2e6);

        vm.warp(REDEEM_START);
        vm.prank(OWNER);
        redeemer.prepareRedemption();

        vm.prank(BOB);
        uint256 redeemed = redeemer.redeem(15 ether, BOB);

        assertEq(redeemed, 30e6);
        assertEq(usdc.balanceOf(BOB), 30e6);
        assertEq(receipt.balanceOf(BOB), 0);
    }
}
