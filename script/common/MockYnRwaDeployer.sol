// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {RedeemableToken} from "contracts/RedeemableToken.sol";

error ZeroAddress();

contract MockYnRwaDeployer {
    address public immutable implementation;

    event Deployed(address indexed vault, address admin);

    struct DeployParams {
        address admin;
        address provider;
        address wrappedAsset;
        address redemptionAsset;
        string name;
        string symbol;
        uint8 decimals;
        bool countNativeAsset;
        bool alwaysComputeTotalAssets;
        uint256 defaultAssetIndex;
    }

    constructor(address implementation_) {
        if (implementation_ == address(0)) {
            revert ZeroAddress();
        }

        implementation = implementation_;
    }

    function deploy(DeployParams calldata params) external returns (RedeemableToken vault) {
        if (
            params.admin == address(0) || params.provider == address(0) || params.wrappedAsset == address(0)
                || params.redemptionAsset == address(0)
        ) {
            revert ZeroAddress();
        }

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

        _grantTemporaryRoles(vault);
        _configureVault(vault, params);
        _handoffRoles(vault, params.admin);

        emit Deployed(address(vault), params.admin);
    }

    function _grantTemporaryRoles(RedeemableToken vault) internal {
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.UNPAUSER_ROLE(), address(this));
    }

    function _configureVault(RedeemableToken vault, DeployParams calldata params) internal {
        vault.setProvider(params.provider);
        vault.addAsset(params.wrappedAsset, false);
        vault.setAssetWithdrawable(params.wrappedAsset, false);
        vault.addAsset(params.redemptionAsset, true);
        vault.setAssetWithdrawable(params.redemptionAsset, true);
        vault.unpause();
    }

    function _handoffRoles(RedeemableToken vault, address admin) internal {
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), admin);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), admin);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), admin);
        vault.grantRole(vault.UNPAUSER_ROLE(), admin);

        vault.renounceRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.renounceRole(vault.UNPAUSER_ROLE(), address(this));
        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), address(this));
    }
}
