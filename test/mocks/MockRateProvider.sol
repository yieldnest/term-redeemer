// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProvider} from "yieldnest-vault/src/interface/IProvider.sol";

contract MockRateProvider is IProvider {
    mapping(address asset => uint256 rate) public rates;

    function setRate(address asset, uint256 rate) external {
        rates[asset] = rate;
    }

    function getRate(address asset) external view returns (uint256) {
        return rates[asset];
    }
}
