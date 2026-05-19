// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FeeHooks} from "yieldnest-vault/src/hooks/FeeHooks.sol";
import {RedeemableToken} from "contracts/RedeemableToken.sol";
import {TermRedeemerController} from "contracts/TermRedeemerController.sol";

error ZeroAddress();
error InvalidRedemptionWindow(uint64 lockEnd, uint64 redeemStart);

contract RedeemableTokenDeployer {
    address public immutable implementation;

    event Deployed(address indexed vault, address indexed hooks, address indexed controller, address admin);

    struct DeployParams {
        address admin;
        address provider;
        address wrappedAsset;
        address redemptionAsset;
        address depositToken;
        address feeRecipient;
        string name;
        string symbol;
        uint8 decimals;
        bool countNativeAsset;
        bool alwaysComputeTotalAssets;
        uint256 defaultAssetIndex;
        uint64 lockEnd;
        uint64 redeemStart;
    }

    struct HookConfig {
        bool beforeDeposit;
        bool afterDeposit;
        bool beforeMint;
        bool afterMint;
        bool beforeRedeem;
        bool afterRedeem;
        bool beforeWithdraw;
        bool afterWithdraw;
        bool beforeProcessAccounting;
        bool afterProcessAccounting;
    }

    constructor(address implementation_) {
        if (implementation_ == address(0)) {
            revert ZeroAddress();
        }

        implementation = implementation_;
    }

    function deploy(DeployParams calldata params)
        external
        returns (RedeemableToken vault, FeeHooks hooks, TermRedeemerController controller)
    {
        _validate(params);

        vault = RedeemableToken(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        implementation,
                        params.admin,
                        abi.encodeCall(
                            RedeemableToken.initialize,
                            (RedeemableToken.InitParams({
                                admin: address(this),
                                name: params.name,
                                symbol: params.symbol,
                                decimals_: params.decimals,
                                countNativeAsset_: params.countNativeAsset,
                                alwaysComputeTotalAssets_: params.alwaysComputeTotalAssets,
                                defaultAssetIndex_: params.defaultAssetIndex
                            }))
                        )
                    )
                )
            )
        );

        HookConfig memory config = HookConfig({
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

        hooks = _deployFeeHooks(address(vault), params.feeRecipient, config);
        controller = new TermRedeemerController(
            address(vault),
            address(hooks),
            params.depositToken,
            params.redemptionAsset,
            params.lockEnd,
            params.redeemStart
        );

        _grantTemporaryRoles(vault);
        _configureVault(vault, hooks, controller, params);
        _handoffRoles(vault, params.admin);

        emit Deployed(address(vault), address(hooks), address(controller), params.admin);
    }

    function _validate(DeployParams calldata params) internal pure {
        if (
            params.admin == address(0) || params.provider == address(0) || params.redemptionAsset == address(0)
                || params.depositToken == address(0) || params.feeRecipient == address(0)
        ) {
            revert ZeroAddress();
        }
        if (params.redeemStart < params.lockEnd) {
            revert InvalidRedemptionWindow(params.lockEnd, params.redeemStart);
        }
    }

    function _grantTemporaryRoles(RedeemableToken vault) internal {
        vault.grantRole(vault.PROCESSOR_ROLE(), address(this));
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.PAUSER_ROLE(), address(this));
        vault.grantRole(vault.UNPAUSER_ROLE(), address(this));
    }

    function _configureVault(
        RedeemableToken vault,
        FeeHooks hooks,
        TermRedeemerController controller,
        DeployParams calldata params
    ) internal {
        vault.setProvider(params.provider);
        if (
            params.wrappedAsset != address(0) && params.wrappedAsset != params.redemptionAsset
                && params.wrappedAsset != params.depositToken
        ) {
            vault.addAsset(params.wrappedAsset, false);
            vault.setAssetWithdrawable(params.wrappedAsset, false);
        }
        vault.addAsset(params.redemptionAsset, false);
        vault.setAssetWithdrawable(params.redemptionAsset, false);
        vault.addAsset(params.depositToken, true);
        vault.setAssetWithdrawable(params.depositToken, false);
        vault.setHooks(address(hooks));
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(controller));
        hooks.transferOwnership(address(controller));
        vault.unpause();
    }

    function _handoffRoles(RedeemableToken vault, address admin) internal {
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), admin);
        vault.grantRole(vault.PROCESSOR_ROLE(), admin);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), admin);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), admin);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), admin);
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), admin);
        vault.grantRole(vault.PAUSER_ROLE(), admin);
        vault.grantRole(vault.UNPAUSER_ROLE(), admin);

        vault.renounceRole(vault.PROCESSOR_ROLE(), address(this));
        vault.renounceRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.HOOKS_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.PAUSER_ROLE(), address(this));
        vault.renounceRole(vault.UNPAUSER_ROLE(), address(this));
        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function _deployFeeHooks(address vault, address feeRecipient, HookConfig memory config) internal returns (FeeHooks hooks) {
        bytes memory initCode =
            abi.encodePacked(type(FeeHooks).creationCode, abi.encode(vault, address(this), 0, feeRecipient, config));
        address deployed;
        assembly {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        if (deployed == address(0)) {
            revert ZeroAddress();
        }
        hooks = FeeHooks(deployed);
    }
}
