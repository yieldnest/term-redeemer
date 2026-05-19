// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestTermRedeemerController} from "./utils/TestTermRedeemerController.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Contracts} from "./Contracts.sol";
import {console2} from "forge-std/Script.sol";

contract LockRedeemer is BaseTestScript {
    function run() external {
        address controllerAddress = _loadAddress(Contracts.TERM_NAMESPACE, Contracts.TERM_CONTROLLER_KEY);

        vm.startBroadcast();
        uint256 totalAssetsSnapshot = TestTermRedeemerController(controllerAddress).lock();
        vm.stopBroadcast();

        console2.log("Locked term vault at total assets:", totalAssetsSnapshot);
    }
}
