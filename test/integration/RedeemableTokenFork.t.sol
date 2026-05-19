// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "yieldnest-vault/src/interface/IVault.sol";
import {FeeHooks} from "yieldnest-vault/src/hooks/FeeHooks.sol";
import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {RedeemableTokenFactory} from "../../contracts/RedeemableTokenFactory.sol";
import {TermRedeemerController} from "../../contracts/TermRedeemerController.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockRateProvider} from "../mocks/MockRateProvider.sol";

interface IYnRwa is IERC20 {
    function ASSET_WITHDRAWER_ROLE() external view returns (bytes32);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        external
        returns (uint256 sharesBurned);
}

contract RedeemableTokenForkTest is Test {
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

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant YNRWAX = 0x01Ba69727E2860b37bc1a2bd56999c1aFb4C15D8;
    address internal constant ADMIN = address(0xA11CE);
    address internal constant ALICE = address(0xB0B);
    address internal constant FEE_RECIPIENT = address(0xFEE);
    address internal constant YNRWAX_DEFAULT_ADMIN = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;

    uint64 internal constant LOCK_END = 200;
    uint64 internal constant REDEEM_START = 300;
    uint256 internal constant DEPOSIT_AMOUNT = 100 ether;
    uint256 internal constant SHARE_UNIT = 1 ether;
    uint256 internal constant USDC_BASE_SCALE = 1e12;
    uint256 internal constant HOLDER_PREVIEW_TOLERANCE = 1e6; // 1 USDC

    IYnRwa internal ynRwa;
    IERC20 internal usdc;
    MockERC20 internal wrappedUsdc;
    MockRateProvider internal provider;
    RedeemableToken internal redeemer;
    FeeHooks internal feeHooks;
    TermRedeemerController internal controller;

    function setUp() public {
        ynRwa = IYnRwa(YNRWAX);
        usdc = IERC20(USDC);
        wrappedUsdc = new MockERC20("Wrapped USDC", "wUSDC", 18);
        provider = new MockRateProvider();

        _syncRates();
        _deployRedeemer();
    }

    function test_Fork_LiveYnRwaLifecycleWithUsdcTopUp() public {
        deal(YNRWAX, ALICE, DEPOSIT_AMOUNT);

        vm.prank(ALICE);
        IERC20(YNRWAX).approve(address(redeemer), type(uint256).max);

        vm.prank(ALICE);
        uint256 mintedShares = redeemer.depositAsset(YNRWAX, DEPOSIT_AMOUNT, ALICE);

        uint256 holderPreviewBeforeLock = redeemer.previewRedeem(mintedShares);
        assertGt(holderPreviewBeforeLock, 0);

        vm.warp(LOCK_END);
        controller.lock();
        assertEq(feeHooks.performanceFee(), 1 ether);

        _syncYnRwaRate(_liveUsdcPerShare() + 0.01e18);
        redeemer.processAccounting();
        uint256 holderPreviewAfterLock = redeemer.previewRedeem(mintedShares);
        assertLe(holderPreviewAfterLock, holderPreviewBeforeLock + HOLDER_PREVIEW_TOLERANCE);
        assertGt(redeemer.balanceOf(FEE_RECIPIENT), 0);

        vm.warp(REDEEM_START);
        uint256 requiredAssets = controller.activateRedemption();
        assertLe(requiredAssets, holderPreviewBeforeLock + HOLDER_PREVIEW_TOLERANCE);
        uint256 aliceExpectedAssets = redeemer.previewRedeem(mintedShares);
        assertLe(aliceExpectedAssets, holderPreviewBeforeLock + HOLDER_PREVIEW_TOLERANCE);

        _allowProcessorWithdrawAsset();
        _grantLiveWithdrawRole();

        uint256 liveWithdrawableAssets = ynRwa.previewRedeem(IERC20(YNRWAX).balanceOf(address(redeemer)));
        uint256 assetsToWithdraw = liveWithdrawableAssets < requiredAssets ? liveWithdrawableAssets : requiredAssets;

        uint256 ynRwaUsdcBalance = usdc.balanceOf(YNRWAX);
        if (ynRwaUsdcBalance < assetsToWithdraw) {
            deal(USDC, YNRWAX, assetsToWithdraw);
        }

        bytes[] memory data = new bytes[](1);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = YNRWAX;
        data[0] = abi.encodeWithSelector(
            IYnRwa.withdrawAsset.selector, USDC, assetsToWithdraw, address(redeemer), address(redeemer)
        );

        vm.prank(ADMIN);
        redeemer.processor(targets, values, data);

        if (assetsToWithdraw < requiredAssets) {
            deal(USDC, address(redeemer), requiredAssets);
        }

        assertEq(usdc.balanceOf(address(redeemer)), requiredAssets);
        assertEq(redeemer.maxRedeem(ALICE), mintedShares);

        vm.prank(ALICE);
        uint256 redeemedAssets = redeemer.redeem(mintedShares, ALICE, ALICE);

        assertEq(redeemedAssets, aliceExpectedAssets);
        assertEq(usdc.balanceOf(ALICE), aliceExpectedAssets);
        assertEq(redeemer.balanceOf(ALICE), 0);
    }

    function _deployRedeemer() internal {
        RedeemableToken implementation = new RedeemableToken();
        RedeemableTokenFactory factory = new RedeemableTokenFactory(address(implementation));
        (redeemer, feeHooks, controller) = factory.deploy(
            RedeemableTokenFactory.DeployParams({
                admin: ADMIN,
                provider: address(provider),
                wrappedAsset: address(wrappedUsdc),
                redemptionAsset: USDC,
                depositToken: YNRWAX,
                feeRecipient: FEE_RECIPIENT,
                name: "Withdrawable ynRWAx",
                symbol: "wynRWAx",
                decimals: 18,
                countNativeAsset: false,
                alwaysComputeTotalAssets: false,
                defaultAssetIndex: 1,
                lockEnd: LOCK_END,
                redeemStart: REDEEM_START
            })
        );
    }

    function _syncRates() internal {
        provider.setRate(address(wrappedUsdc), 1e18);
        provider.setRate(USDC, 1e18);
        provider.setRate(YNRWAX, _liveUsdcPerShare());
    }

    function _syncYnRwaRate(uint256 rate) internal {
        provider.setRate(YNRWAX, rate);
    }

    function _liveUsdcPerShare() internal view returns (uint256) {
        return ynRwa.previewRedeem(SHARE_UNIT) * USDC_BASE_SCALE;
    }

    function _allowProcessorWithdrawAsset() internal {
        address[] memory vaultAllowList = new address[](1);
        vaultAllowList[0] = address(redeemer);
        address[] memory assetAllowList = new address[](1);
        assetAllowList[0] = USDC;
        ParamRule[] memory paramRules = new ParamRule[](4);
        paramRules[0] = ParamRule({paramType: 1, isArray: false, allowList: assetAllowList});
        paramRules[2] = ParamRule({paramType: 1, isArray: false, allowList: vaultAllowList});
        paramRules[3] = ParamRule({paramType: 1, isArray: false, allowList: vaultAllowList});
        FunctionRule memory rule = FunctionRule({isActive: true, paramRules: paramRules, validator: address(0)});

        vm.prank(ADMIN);
        (bool ok,) = address(redeemer)
            .call(
                abi.encodeWithSignature(
                    "setProcessorRule(address,bytes4,(bool,(uint8,bool,address[])[],address))",
                    YNRWAX,
                    IYnRwa.withdrawAsset.selector,
                    rule
                )
        );
        assertTrue(ok);
    }

    function _grantLiveWithdrawRole() internal {
        bytes32 role = ynRwa.ASSET_WITHDRAWER_ROLE();
        if (ynRwa.hasRole(role, address(redeemer))) {
            return;
        }

        vm.prank(YNRWAX_DEFAULT_ADMIN);
        ynRwa.grantRole(role, address(redeemer));

        assertTrue(ynRwa.hasRole(role, address(redeemer)));
    }
}
