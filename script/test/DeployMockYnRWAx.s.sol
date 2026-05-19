// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {MockRateProvider} from "../../test/mocks/MockRateProvider.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Contracts} from "./Contracts.sol";

contract DeployMockYnRWAx is BaseTestScript {
    function run() external {
        vm.startBroadcast();

        address admin = _broadcaster();
        MockRateProvider provider = new MockRateProvider();
        provider.setRate(Contracts.USDC, Contracts.ONE);

        RedeemableToken implementation = new RedeemableToken();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeCall(
                RedeemableToken.initialize,
                (RedeemableToken.InitParams({
                    admin: admin,
                    name: Contracts.MOCK_YNRWAX_NAME,
                    symbol: Contracts.MOCK_YNRWAX_SYMBOL,
                    decimals_: Contracts.VAULT_DECIMALS,
                    countNativeAsset_: false,
                    alwaysComputeTotalAssets_: false,
                    defaultAssetIndex_: Contracts.DEFAULT_ASSET_INDEX
                }))
            )
        );

        RedeemableToken vault = RedeemableToken(payable(address(proxy)));
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), admin);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), admin);
        vault.grantRole(vault.UNPAUSER_ROLE(), admin);
        vault.setProvider(address(provider));
        vault.addAsset(Contracts.USDC, true);
        vault.setAssetWithdrawable(Contracts.USDC, true);
        vault.unpause();

        vm.stopBroadcast();

        _recordAddress(Contracts.MOCK_YNRWAX_PROVIDER_KEY, address(provider));
        _recordAddress(Contracts.MOCK_YNRWAX_IMPLEMENTATION_KEY, address(implementation));
        _recordAddress(Contracts.MOCK_YNRWAX_KEY, address(vault));

        _logAddress(Contracts.MOCK_YNRWAX_LABEL, address(vault));
        _logAddress(Contracts.MOCK_YNRWAX_PROVIDER_LABEL, address(provider));
    }
}
