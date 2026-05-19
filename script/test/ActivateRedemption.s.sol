// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RedeemableToken} from "../../contracts/RedeemableToken.sol";
import {TermRedeemerController} from "../../contracts/TermRedeemerController.sol";
import {BaseTestScript} from "./BaseTestScript.s.sol";
import {Contracts} from "./Contracts.sol";
import {console2} from "forge-std/Script.sol";

interface IWithdrawableVault is IERC20 {
    function maxWithdrawAsset(address asset_, address owner) external view returns (uint256);
    function withdrawAsset(address asset_, uint256 assets, address receiver, address owner)
        external
        returns (uint256 sharesBurned);
}

error InsufficientMockYnRWAxLiquidity(uint256 requestedAssets, uint256 maxWithdrawableAssets);

contract ActivateRedemption is BaseTestScript {
    function run() external {
        address controllerAddress = _loadAddress(Contracts.TERM_CONTROLLER_KEY);
        address vaultAddress = _loadAddress(Contracts.TERM_VAULT_KEY);
        address mockYnRWAx = _loadAddress(Contracts.MOCK_YNRWAX_KEY);

        vm.startBroadcast();

        TermRedeemerController controller = TermRedeemerController(controllerAddress);
        RedeemableToken vault = RedeemableToken(payable(vaultAddress));
        uint256 requiredAssets = controller.activateRedemption();

        uint256 maxWithdrawableAssets = IWithdrawableVault(mockYnRWAx).maxWithdrawAsset(Contracts.USDC, vaultAddress);
        if (requiredAssets > maxWithdrawableAssets) {
            revert InsufficientMockYnRWAxLiquidity(requiredAssets, maxWithdrawableAssets);
        }

        bytes[] memory data = new bytes[](1);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = mockYnRWAx;
        data[0] = abi.encodeWithSelector(
            IWithdrawableVault.withdrawAsset.selector, Contracts.USDC, requiredAssets, vaultAddress, vaultAddress
        );

        vault.processor(targets, values, data);

        vm.stopBroadcast();

        console2.log("Activated redemption with required USDC:", requiredAssets);
        console2.log("Term vault USDC balance:", IERC20(Contracts.USDC).balanceOf(vaultAddress));
    }
}
