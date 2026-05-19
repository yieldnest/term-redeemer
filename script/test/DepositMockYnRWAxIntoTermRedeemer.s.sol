// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Contracts} from "./Contracts.sol";
import {console2} from "forge-std/Script.sol";

contract DepositMockYnRWAxIntoTermRedeemer is BaseTestScript {
    function run() external {
        uint256 assets = vm.envUint(Contracts.AMOUNT_ENV);
        address vault = _loadAddress(Contracts.TERM_NAMESPACE, Contracts.TERM_VAULT_KEY);
        address depositToken = _loadAddress(Contracts.MOCK_YNRWAX_NAMESPACE, Contracts.MOCK_YNRWAX_KEY);
        address depositor = _broadcaster();

        vm.startBroadcast();
        IERC20(depositToken).approve(vault, assets);
        uint256 shares = RedeemableToken(payable(vault)).depositAsset(depositToken, assets, depositor);
        vm.stopBroadcast();

        console2.log("Deposited mynRWAx:", assets);
        console2.log("Minted term shares:", shares);
    }
}
