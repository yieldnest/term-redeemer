// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {MockYnRwaDeployer} from "../common/MockYnRwaDeployer.sol";
import {MockRateProvider} from "../../test/mocks/MockRateProvider.sol";
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
        provider.setRate(Contracts.WRAPPED_USDC, Constants.ONE);
        provider.setRate(Contracts.USDC, Constants.ONE);

        RedeemableToken implementation = new RedeemableToken();
        MockYnRwaDeployer deployer = new MockYnRwaDeployer(address(implementation));
        RedeemableToken vault = deployer.deploy(
            MockYnRwaDeployer.DeployParams({
                admin: admin,
                provider: address(provider),
                wrappedAsset: Contracts.WRAPPED_USDC,
                redemptionAsset: Contracts.USDC,
                name: Constants.MOCK_YNRWAX_NAME,
                symbol: Constants.MOCK_YNRWAX_SYMBOL,
                decimals: Constants.VAULT_DECIMALS,
                countNativeAsset: false,
                alwaysComputeTotalAssets: false,
                defaultAssetIndex: Constants.DEFAULT_ASSET_INDEX
            })
        );

        vm.stopBroadcast();

        string[] memory keys = new string[](4);
        address[] memory values = new address[](4);
        keys[0] = Constants.MOCK_YNRWAX_PROVIDER_KEY;
        values[0] = address(provider);
        keys[1] = Constants.MOCK_YNRWAX_IMPLEMENTATION_KEY;
        values[1] = address(implementation);
        keys[2] = Constants.MOCK_YNRWAX_KEY;
        values[2] = address(vault);
        keys[3] = "mockYnRwaFactory";
        values[3] = address(deployer);
        _writeAddresses(Constants.MOCK_YNRWAX_NAMESPACE, keys, values);

        _logAddress(Constants.MOCK_YNRWAX_LABEL, address(vault));
        _logAddress(Constants.MOCK_YNRWAX_PROVIDER_LABEL, address(provider));
    }
}
