// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestTermRedeemerController} from "./utils/TestTermRedeemerController.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Constants} from "./Constants.sol";
import {console2} from "forge-std/Script.sol";

contract ResetRedeemerStage is BaseTestScript {
    function run() external {
        address controllerAddress = _loadAddress(Constants.TERM_NAMESPACE, Constants.TERM_CONTROLLER_KEY);

        vm.startBroadcast();
        TestTermRedeemerController(controllerAddress).resetToInitialStage();
        vm.stopBroadcast();

        console2.log("Reset term vault to initial deposit stage.");
    }
}
