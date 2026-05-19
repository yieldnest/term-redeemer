// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TermRedeemerController} from "../../contracts/TermRedeemerController.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Contracts} from "./Contracts.sol";
import {console2} from "forge-std/Script.sol";

contract ResetRedeemerStage is BaseTestScript {
    function run() external {
        address controllerAddress = _loadAddress(Contracts.TERM_CONTROLLER_KEY);

        vm.startBroadcast();
        TermRedeemerController(controllerAddress).resetToInitialStage();
        vm.stopBroadcast();

        console2.log("Reset term vault to initial deposit stage.");
    }
}
