// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Contracts} from "./Contracts.sol";
import {Constants} from "./Constants.sol";
import {console2} from "forge-std/Script.sol";

contract DepositUsdcIntoMockYnRWAx is BaseTestScript {
    function run() external {
        uint256 assets = vm.envUint(Constants.AMOUNT_ENV);
        address vault = _loadAddress(Constants.MOCK_YNRWAX_NAMESPACE, Constants.MOCK_YNRWAX_KEY);
        address depositor = _broadcaster();

        vm.startBroadcast();
        IERC20(Contracts.USDC).approve(vault, assets);
        uint256 shares = RedeemableToken(payable(vault)).depositAsset(Contracts.USDC, assets, depositor);
        vm.stopBroadcast();

        console2.log("Deposited USDC:", assets);
        console2.log("Minted mynRWAx shares:", shares);
    }
}
