// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Base} from "../../src/TermRedeemer.sol";

contract MockERC20 is ERC20Base {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20Base(name_, symbol_, decimals_) {}

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }
}
