// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {RedeemableTokenDeployer} from "../common/RedeemableTokenDeployer.sol";
import {BaseDeploymentScript} from "../common/BaseDeploymentScript.s.sol";

/// @notice Example:
/// SENDER=0xYourAddress ACCOUNT=your-keystore-name forge script script/deploy/DeployRedeemableTokenFactory.s.sol:DeployRedeemableTokenFactory --rpc-url $ETH_MAINNET_RPC_URL --account $ACCOUNT --sender $SENDER --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
contract DeployRedeemableTokenFactory is BaseDeploymentScript {
    string internal constant DEPLOY_NAMESPACE = "deploy";

    function run() external {
        vm.startBroadcast();

        RedeemableToken implementation = new RedeemableToken();
        RedeemableTokenDeployer factory = new RedeemableTokenDeployer(address(implementation));

        vm.stopBroadcast();

        string[] memory keys = new string[](2);
        address[] memory values = new address[](2);
        keys[0] = "implementation";
        values[0] = address(implementation);
        keys[1] = "factory";
        values[1] = address(factory);
        _writeAddresses(DEPLOY_NAMESPACE, keys, values);
    }
}
