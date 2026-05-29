// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

error MissingDeployment(string namespace, string path);
error InvalidDeploymentPayload();

abstract contract BaseDeploymentScript is Script {
    function _broadcaster() internal view returns (address) {
        return tx.origin;
    }

    function _writeAddresses(string memory namespace, string[] memory keys, address[] memory values) internal {
        if (keys.length != values.length) {
            revert InvalidDeploymentPayload();
        }

        vm.createDir(_deploymentDirectory(namespace), true);

        string memory objectKey = "deployment";
        for (uint256 i = 0; i < keys.length; ++i) {
            vm.serializeAddress(objectKey, keys[i], values[i]);
        }
        string memory json = vm.serializeUint(objectKey, "chainId", block.chainid);

        vm.writeJson(json, _deploymentPath(namespace));
    }

    function _loadAddress(string memory namespace, string memory key) internal view returns (address value) {
        string memory path = _deploymentPath(namespace);
        if (!vm.isFile(path)) {
            revert MissingDeployment(namespace, path);
        }

        value = vm.parseJsonAddress(vm.readFile(path), string.concat(".", key));
    }

    function _deploymentPath(string memory namespace) internal view returns (string memory) {
        return string.concat(_deploymentDirectory(namespace), "/", vm.toString(block.chainid), ".json");
    }

    function _deploymentDirectory(string memory namespace) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", namespace);
    }
}
