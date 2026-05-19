// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IHooks} from "yieldnest-vault/src/interface/IHooks.sol";
import {FeeHooks} from "yieldnest-vault/src/hooks/FeeHooks.sol";
import {RedeemableToken} from "./RedeemableToken.sol";
import {TermRedeemerController} from "./TermRedeemerController.sol";

error ZeroAddress();
error InvalidRedemptionWindow(uint64 lockEnd, uint64 redeemStart);

contract RedeemableTokenFactory {
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
        bool unrestrictedController;
        uint256 defaultAssetIndex;
        uint64 lockEnd;
        uint64 redeemStart;
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

        hooks = new FeeHooks(address(vault), address(this), 0, params.feeRecipient, config);
        controller = new TermRedeemerController(
            address(vault),
            address(hooks),
            params.admin,
            params.depositToken,
            params.redemptionAsset,
            params.lockEnd,
            params.redeemStart,
            params.unrestrictedController
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
}
