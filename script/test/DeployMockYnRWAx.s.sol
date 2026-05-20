// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {MockRateProvider} from "../../test/mocks/MockRateProvider.sol";
import {MockERC20} from "../../test/mocks/MockERC20.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Contracts} from "./Contracts.sol";
import {Constants} from "./Constants.sol";

/// @notice Example:
/// SENDER=0xYourAddress ACCOUNT=your-keystore-name forge script script/test/DeployMockYnRWAx.s.sol:DeployMockYnRWAx --rpc-url $ETH_MAINNET_RPC_URL --account $ACCOUNT --sender $SENDER --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
contract DeployMockYnRWAx is BaseTestScript {
    function run() external {
        vm.startBroadcast();

        address admin = _broadcaster();
        MockRateProvider provider = new MockRateProvider();
        MockERC20 wrappedUsdc = new MockERC20("Wrapped USDC", "wUSDC", 18);
        provider.setRate(address(wrappedUsdc), Constants.ONE);
        provider.setRate(Contracts.USDC, Constants.ONE);

        RedeemableToken implementation = new RedeemableToken();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            admin,
            abi.encodeCall(
                RedeemableToken.initialize,
                (RedeemableToken.InitParams({
                    admin: admin,
                    name: Constants.MOCK_YNRWAX_NAME,
                    symbol: Constants.MOCK_YNRWAX_SYMBOL,
                    decimals_: Constants.VAULT_DECIMALS,
                    countNativeAsset_: false,
                    alwaysComputeTotalAssets_: false,
                    defaultAssetIndex_: Constants.DEFAULT_ASSET_INDEX
                }))
            )
        );

        RedeemableToken vault = RedeemableToken(payable(address(proxy)));
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), admin);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), admin);
        vault.grantRole(vault.UNPAUSER_ROLE(), admin);
        vault.setProvider(address(provider));
        vault.addAsset(address(wrappedUsdc), false);
        vault.setAssetWithdrawable(address(wrappedUsdc), false);
        vault.addAsset(Contracts.USDC, true);
        vault.setAssetWithdrawable(Contracts.USDC, true);
        vault.unpause();

        vm.stopBroadcast();

        string[] memory keys = new string[](3);
        address[] memory values = new address[](3);
        keys[0] = Constants.MOCK_YNRWAX_PROVIDER_KEY;
        values[0] = address(provider);
        keys[1] = Constants.MOCK_YNRWAX_IMPLEMENTATION_KEY;
        values[1] = address(implementation);
        keys[2] = Constants.MOCK_YNRWAX_KEY;
        values[2] = address(vault);
        _writeAddresses(Constants.MOCK_YNRWAX_NAMESPACE, keys, values);

        string[] memory sharedKeys = new string[](1);
        address[] memory sharedValues = new address[](1);
        sharedKeys[0] = Constants.WRAPPED_USDC_KEY;
        sharedValues[0] = address(wrappedUsdc);
        _writeAddresses(Constants.SHARED_NAMESPACE, sharedKeys, sharedValues);

        _logAddress(Constants.MOCK_YNRWAX_LABEL, address(vault));
        _logAddress(Constants.MOCK_YNRWAX_PROVIDER_LABEL, address(provider));
        _logAddress(Constants.WRAPPED_USDC_LABEL, address(wrappedUsdc));
    }
}
