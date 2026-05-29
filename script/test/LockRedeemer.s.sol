// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestTermRedeemerController} from "./utils/TestTermRedeemerController.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Constants} from "./Constants.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Example:
/// SENDER=0xYourAddress ACCOUNT=your-keystore-name forge script script/test/LockRedeemer.s.sol:LockRedeemer --rpc-url $ETH_MAINNET_RPC_URL --account $ACCOUNT --sender $SENDER --broadcast
contract LockRedeemer is BaseTestScript {
    function run() external {
        address controllerAddress = _loadAddress(Constants.TERM_NAMESPACE, Constants.TERM_CONTROLLER_KEY);

        vm.startBroadcast();
        uint256 totalAssetsSnapshot = TestTermRedeemerController(controllerAddress).lock();
        vm.stopBroadcast();

        console2.log("Locked term vault at total assets:", totalAssetsSnapshot);
    }
}
