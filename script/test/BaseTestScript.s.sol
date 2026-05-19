// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/Script.sol";
import {BaseDeploymentScript} from "../common/BaseDeploymentScript.s.sol";

abstract contract BaseTestScript is BaseDeploymentScript {
    function _logAddress(string memory label, address value) internal pure {
        console2.log(string.concat(label, ": "), value);
    }
}
