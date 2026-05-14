// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "yieldnest-vault/src/interface/IVault.sol";
import {TermRedeemer} from "./TermRedeemer.sol";
import {ProcessAccountingToggleHooks} from "./ProcessAccountingToggleHooks.sol";

error LockNotReady(uint256 timestamp, uint64 lockEnd);
error RedeemNotReady(uint256 timestamp, uint64 redeemStart);
error AlreadyLocked();
error NotLocked();
error RedemptionAlreadyActivated();
error DepositTokenNotUnwound(uint256 remainingBalance);
error InsufficientRedemptionFunding(uint256 requiredAssets, uint256 availableAssets);

contract TermRedeemerController {
    TermRedeemer public immutable vault;
    ProcessAccountingToggleHooks public immutable hooks;
    address public immutable depositToken;
    address public immutable redemptionAsset;
    uint64 public immutable lockEnd;
    uint64 public immutable redeemStart;

    bool public locked;
    bool public redemptionActivated;

    event Locked(uint256 totalAssetsSnapshot);
    event RedemptionActivated(uint256 requiredAssets);

    constructor(
        address vault_,
        address hooks_,
        address depositToken_,
        address redemptionAsset_,
        uint64 lockEnd_,
        uint64 redeemStart_
    ) {
        vault = TermRedeemer(payable(vault_));
        hooks = ProcessAccountingToggleHooks(hooks_);
        depositToken = depositToken_;
        redemptionAsset = redemptionAsset_;
        lockEnd = lockEnd_;
        redeemStart = redeemStart_;
    }

    function lock() external returns (uint256 totalAssetsSnapshot) {
        if (block.timestamp < lockEnd) {
            revert LockNotReady(block.timestamp, lockEnd);
        }
        if (locked) {
            revert AlreadyLocked();
        }

        vault.processAccounting();

        IVault.AssetParams memory params = vault.getAsset(depositToken);
        IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: false});
        vault.updateAsset(params.index, fields);
        hooks.setProcessAccountingBlocked(true);

        locked = true;
        totalAssetsSnapshot = vault.totalAssets();

        emit Locked(totalAssetsSnapshot);
    }

    function activateRedemption() external returns (uint256 requiredAssets) {
        if (block.timestamp < redeemStart) {
            revert RedeemNotReady(block.timestamp, redeemStart);
        }
        if (redemptionActivated) {
            revert RedemptionAlreadyActivated();
        }
        if (!locked) {
            revert NotLocked();
        }

        uint256 remainingDepositTokenBalance = IERC20(depositToken).balanceOf(address(vault));
        if (remainingDepositTokenBalance != 0) {
            revert DepositTokenNotUnwound(remainingDepositTokenBalance);
        }

        requiredAssets = vault.previewRedeem(vault.totalSupply());
        uint256 availableAssets = IERC20(redemptionAsset).balanceOf(address(vault));
        if (availableAssets < requiredAssets) {
            revert InsufficientRedemptionFunding(requiredAssets, availableAssets);
        }

        vault.setAssetWithdrawable(redemptionAsset, true);
        redemptionActivated = true;

        emit RedemptionActivated(requiredAssets);
    }
}
