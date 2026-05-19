// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Contracts} from "./Contracts.sol";

error MissingDeployment(string name, string path);

abstract contract BaseTestScript is Script {
    function _broadcaster() internal view returns (address) {
        return tx.origin;
    }

    function _recordAddress(string memory name, address value) internal {
        vm.writeFile(_path(name), vm.toString(value));
    }

    function _loadAddress(string memory name) internal view returns (address value) {
        string memory path = _path(name);
        if (!vm.isFile(path)) {
            revert MissingDeployment(name, path);
        }
        value = vm.parseAddress(vm.readFile(path));
    }

    function _path(string memory name) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/test/", name, "-", vm.toString(block.chainid), ".txt");
    }

    function _logAddress(string memory label, address value) internal pure {
        console2.log(string.concat(label, ": "), value);
    }
}
