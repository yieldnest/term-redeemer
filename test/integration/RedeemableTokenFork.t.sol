// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "yieldnest-vault/src/interface/IVault.sol";
import {IHooks} from "yieldnest-vault/src/interface/IHooks.sol";
import {FeeHooks} from "yieldnest-vault/src/hooks/FeeHooks.sol";
import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {TermRedeemerController} from "../../contracts/TermRedeemerController.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockRateProvider} from "../mocks/MockRateProvider.sol";

interface IYnRwa is IERC20 {
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
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

    uint64 internal constant LOCK_END = 200;
    uint64 internal constant REDEEM_START = 300;
    uint256 internal constant DEPOSIT_AMOUNT = 100 ether;
    uint256 internal constant SHARE_UNIT = 1 ether;
    uint256 internal constant USDC_BASE_SCALE = 1e12;

    IYnRwa internal ynRwa;
    IERC20 internal usdc;
    MockERC20 internal wrappedUsdc;
    MockRateProvider internal provider;
    RedeemableToken internal redeemer;
    FeeHooks internal feeHooks;
    TermRedeemerController internal controller;
    bool internal forkEnabled;

    function setUp() public {
        if (!vm.envExists("MAINNET_RPC_URL")) {
            return;
        }

        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpcUrl);
        forkEnabled = true;

        ynRwa = IYnRwa(YNRWAX);
        usdc = IERC20(USDC);
        wrappedUsdc = new MockERC20("Wrapped USDC", "wUSDC", 18);
        provider = new MockRateProvider();

        _syncRates();
        _deployRedeemer();
        _configureRedeemer();
    }

    function test_Fork_LiveYnRwaLifecycleWithUsdcTopUp() public {
        if (!forkEnabled) {
            return;
        }

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
        assertEq(redeemer.previewRedeem(mintedShares), holderPreviewBeforeLock);
        assertGt(redeemer.balanceOf(FEE_RECIPIENT), 0);

        vm.warp(REDEEM_START);
        uint256 requiredAssets = controller.activateRedemption();
        assertEq(requiredAssets, holderPreviewBeforeLock);

        _allowProcessorWithdrawAsset();

        uint256 ynRwaUsdcBalance = usdc.balanceOf(YNRWAX);
        if (ynRwaUsdcBalance < requiredAssets) {
            deal(USDC, YNRWAX, requiredAssets);
        }

        bytes[] memory data = new bytes[](1);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = YNRWAX;
        data[0] = abi.encodeWithSelector(
            IYnRwa.withdrawAsset.selector, USDC, requiredAssets, address(redeemer), address(redeemer)
        );

        vm.prank(ADMIN);
        redeemer.processor(targets, values, data);

        assertEq(usdc.balanceOf(address(redeemer)), requiredAssets);
        assertEq(redeemer.maxRedeem(ALICE), mintedShares);

        vm.prank(ALICE);
        uint256 redeemedAssets = redeemer.redeem(mintedShares, ALICE, ALICE);

        assertEq(redeemedAssets, requiredAssets);
        assertEq(usdc.balanceOf(ALICE), requiredAssets);
        assertEq(redeemer.balanceOf(ALICE), 0);
    }

    function _deployRedeemer() internal {
        RedeemableToken implementation = new RedeemableToken();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            ADMIN,
            abi.encodeCall(
                RedeemableToken.initialize,
                (RedeemableToken.InitParams({
                        admin: ADMIN,
                        name: "Withdrawable ynRWAx",
                        symbol: "wynRWAx",
                        decimals_: 18,
                        countNativeAsset_: false,
                        alwaysComputeTotalAssets_: false,
                        defaultAssetIndex_: 1
                    }))
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
            beforeProcessAccounting: false,
            afterProcessAccounting: true
        });
        feeHooks = new FeeHooks(address(redeemer), ADMIN, 0, FEE_RECIPIENT, config);
        controller =
            new TermRedeemerController(address(redeemer), address(feeHooks), YNRWAX, USDC, LOCK_END, REDEEM_START);
    }

    function _configureRedeemer() internal {
        vm.startPrank(ADMIN);
        redeemer.grantRole(redeemer.PROCESSOR_ROLE(), ADMIN);
        redeemer.grantRole(redeemer.PROCESSOR_MANAGER_ROLE(), ADMIN);
        redeemer.grantRole(redeemer.PROVIDER_MANAGER_ROLE(), ADMIN);
        redeemer.grantRole(redeemer.ASSET_MANAGER_ROLE(), ADMIN);
        redeemer.grantRole(redeemer.HOOKS_MANAGER_ROLE(), ADMIN);
        redeemer.grantRole(redeemer.UNPAUSER_ROLE(), ADMIN);

        redeemer.setProvider(address(provider));
        redeemer.addAsset(address(wrappedUsdc), false);
        redeemer.setAssetWithdrawable(address(wrappedUsdc), false);
        redeemer.addAsset(USDC, false);
        redeemer.setAssetWithdrawable(USDC, false);
        redeemer.addAsset(YNRWAX, true);
        redeemer.setAssetWithdrawable(YNRWAX, false);
        redeemer.setHooks(address(feeHooks));
        redeemer.grantRole(redeemer.ASSET_MANAGER_ROLE(), address(controller));
        feeHooks.transferOwnership(address(controller));
        redeemer.unpause();
        vm.stopPrank();
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
}
