// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IVault} from "yieldnest-vault/src/interface/IVault.sol";
import {HooksLib} from "yieldnest-vault/src/library/HooksLib.sol";
import {RedeemableToken} from "../contracts/RedeemableToken.sol";
import {
    AlreadyLocked,
    DepositTokenNotUnwound,
    InsufficientRedemptionFunding,
    LockNotReady,
    RedeemNotReady,
    TermRedeemerController
} from "../contracts/TermRedeemerController.sol";
import {ProcessAccountingBlocked, ProcessAccountingToggleHooks} from "../contracts/ProcessAccountingToggleHooks.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockRateProvider} from "./mocks/MockRateProvider.sol";
import {MockYnRwa} from "./mocks/MockYnRwa.sol";
import {IHooks} from "yieldnest-vault/src/interface/IHooks.sol";

contract TermRedeemerTest is Test {
    struct ParamRule {
        uint8 paramType;
        bool isArray;
        address[] allowList;
    }

    struct FunctionRule {
        bool isActive;
        ParamRule[] paramRules;
        address validator;
    }

    uint64 internal constant LOCK_END = 200;
    uint64 internal constant REDEEM_START = 300;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant ALICE = address(0xB0B);
    address internal constant BOB = address(0xCAFE);

    MockERC20 internal usdc;
    MockERC20 internal wrappedUsdc;
    MockYnRwa internal ynRwa;
    MockRateProvider internal provider;
    RedeemableToken internal redeemer;
    ProcessAccountingToggleHooks internal accountingHooks;
    TermRedeemerController internal controller;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        wrappedUsdc = new MockERC20("Wrapped USDC", "wUSDC", 18);
        ynRwa = new MockYnRwa(address(usdc));
        provider = new MockRateProvider();

        provider.setRate(address(wrappedUsdc), 1e18);
        provider.setRate(address(usdc), 1e18);
        provider.setRate(address(ynRwa), 11e17);

        RedeemableToken implementation = new RedeemableToken();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            ADMIN,
            abi.encodeCall(
                RedeemableToken.initialize,
                (
                    ADMIN,
                    address(provider),
                    address(wrappedUsdc),
                    address(usdc),
                    address(ynRwa),
                    "Withdrawable ynRWAx",
                    "wynRWAx"
                )
            )
        );
        redeemer = RedeemableToken(payable(address(proxy)));

        IHooks.Config memory config = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: false,
            afterWithdraw: false,
            beforeProcessAccounting: true,
            afterProcessAccounting: false
        });
        accountingHooks = new ProcessAccountingToggleHooks(address(redeemer), ADMIN, config);
        controller = new TermRedeemerController(
            address(redeemer), address(accountingHooks), address(ynRwa), address(usdc), LOCK_END, REDEEM_START
        );

        vm.startPrank(ADMIN);
        redeemer.setHooks(address(accountingHooks));
        redeemer.grantRole(redeemer.ASSET_MANAGER_ROLE(), address(controller));
        accountingHooks.grantRole(accountingHooks.TOGGLER_ROLE(), address(controller));
        vm.stopPrank();

        ynRwa.mint(ALICE, 200 ether);
        ynRwa.mint(BOB, 100 ether);

        vm.prank(ALICE);
        ynRwa.approve(address(redeemer), type(uint256).max);

        vm.prank(BOB);
        ynRwa.approve(address(redeemer), type(uint256).max);
    }

    function test_DepositAssetMintsUsdcDenominatedShares() public {
        vm.prank(ALICE);
        uint256 shares = redeemer.depositAsset(address(ynRwa), 100 ether, ALICE);

        assertEq(shares, 110 ether);
        assertEq(redeemer.balanceOf(ALICE), 110 ether);
        assertEq(ynRwa.balanceOf(address(redeemer)), 100 ether);
        assertEq(redeemer.totalBaseAssets(), 110 ether);
        assertEq(redeemer.previewRedeem(110 ether), 110e6);
    }

    function test_LockRevertsBeforeLockEnd() public {
        vm.expectRevert(abi.encodeWithSelector(LockNotReady.selector, 1, LOCK_END));
        controller.lock();
    }

    function test_LockDisablesDepositsAndBlocksAccounting() public {
        vm.prank(ALICE);
        redeemer.depositAsset(address(ynRwa), 100 ether, ALICE);

        provider.setRate(address(ynRwa), 12e17);

        vm.warp(LOCK_END);
        uint256 totalAssetsSnapshot = controller.lock();

        assertEq(totalAssetsSnapshot, 120e6);
        assertEq(redeemer.totalBaseAssets(), 120 ether);
        assertEq(redeemer.previewRedeem(110 ether), 119_999_999);
        assertTrue(controller.locked());
        assertTrue(accountingHooks.processAccountingBlocked());

        provider.setRate(address(ynRwa), 14e17);

        vm.expectRevert(
            abi.encodeWithSelector(
                HooksLib.HookCallFailed.selector, abi.encodeWithSelector(ProcessAccountingBlocked.selector)
            )
        );
        redeemer.processAccounting();

        vm.prank(BOB);
        vm.expectRevert(IVault.AssetNotActive.selector);
        redeemer.depositAsset(address(ynRwa), 10 ether, BOB);

        vm.expectRevert(AlreadyLocked.selector);
        controller.lock();
    }

    function test_ActivateRedemptionRevertsBeforeRedeemTime() public {
        vm.warp(LOCK_END);
        controller.lock();

        vm.expectRevert(abi.encodeWithSelector(RedeemNotReady.selector, LOCK_END, REDEEM_START));
        controller.activateRedemption();
    }

    function test_RedemptionActivatesOnlyAfterUnwindAndFunding() public {
        vm.prank(ALICE);
        redeemer.depositAsset(address(ynRwa), 100 ether, ALICE);

        provider.setRate(address(ynRwa), 12e17);

        vm.warp(LOCK_END);
        controller.lock();

        vm.warp(REDEEM_START);
        vm.expectRevert(abi.encodeWithSelector(DepositTokenNotUnwound.selector, 100 ether));
        controller.activateRedemption();

        ynRwa.setUsdcPerShare(1_200_000);
        usdc.mint(address(ynRwa), 120e6);

        _allowProcessorRedeem();

        bytes[] memory data = new bytes[](1);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(ynRwa);
        data[0] = abi.encodeWithSelector(MockYnRwa.redeem.selector, 100 ether, address(redeemer), address(redeemer));

        vm.prank(ADMIN);
        redeemer.processor(targets, values, data);

        assertEq(ynRwa.balanceOf(address(redeemer)), 0);
        assertEq(usdc.balanceOf(address(redeemer)), 120e6);

        uint256 requiredAssets = controller.activateRedemption();
        assertEq(requiredAssets, 119_999_999);
        assertTrue(controller.redemptionActivated());
        assertEq(redeemer.maxRedeem(ALICE), 110 ether);

        vm.prank(ALICE);
        uint256 assets = redeemer.redeem(110 ether, ALICE, ALICE);

        assertEq(assets, 119_999_999);
        assertEq(usdc.balanceOf(ALICE), 119_999_999);
        assertEq(redeemer.balanceOf(ALICE), 0);
    }

    function test_ActivateRedemptionRevertsWhenUsdcFundingIsShort() public {
        vm.prank(ALICE);
        redeemer.depositAsset(address(ynRwa), 100 ether, ALICE);

        provider.setRate(address(ynRwa), 12e17);

        vm.warp(LOCK_END);
        controller.lock();

        ynRwa.setUsdcPerShare(1_000_000);
        usdc.mint(address(ynRwa), 100e6);

        _allowProcessorRedeem();

        bytes[] memory data = new bytes[](1);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(ynRwa);
        data[0] = abi.encodeWithSelector(MockYnRwa.redeem.selector, 100 ether, address(redeemer), address(redeemer));

        vm.prank(ADMIN);
        redeemer.processor(targets, values, data);

        vm.warp(REDEEM_START);
        vm.expectRevert(abi.encodeWithSelector(InsufficientRedemptionFunding.selector, 119_999_999, 100e6));
        controller.activateRedemption();
    }

    function _allowProcessorRedeem() internal {
        address[] memory allowList = new address[](1);
        allowList[0] = address(redeemer);
        ParamRule[] memory paramRules = new ParamRule[](3);
        paramRules[1] = ParamRule({paramType: 1, isArray: false, allowList: allowList});
        paramRules[2] = ParamRule({paramType: 1, isArray: false, allowList: allowList});
        FunctionRule memory rule = FunctionRule({isActive: true, paramRules: paramRules, validator: address(0)});

        vm.prank(ADMIN);
        (bool ok,) = address(redeemer)
            .call(
                abi.encodeWithSignature(
                    "setProcessorRule(address,bytes4,(bool,(uint8,bool,address[])[],address))",
                    address(ynRwa),
                    MockYnRwa.redeem.selector,
                    rule
                )
            );
        assertTrue(ok);
    }
}
