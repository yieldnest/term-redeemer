// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVault} from "yieldnest-vault/src/interface/IVault.sol";
import {IFeeHooks} from "yieldnest-vault/src/interface/IFeeHooks.sol";
import {RedeemableToken} from "./RedeemableToken.sol";

error LockNotReady(uint256 timestamp, uint64 lockEnd);
error RedeemNotReady(uint256 timestamp, uint64 redeemStart);
error AlreadyLocked();
error NotLocked();
error RedemptionAlreadyActivated();
error TransitionAdminOnly(address caller);
error RestrictedController();
error RedemptionNotActivated();

contract TermRedeemerController {
    uint256 internal constant FEE_DENOMINATOR = 1 ether;

    RedeemableToken public immutable vault;
    IFeeHooks public immutable hooks;
    address public immutable transitionAdmin;
    address public immutable depositToken;
    address public immutable redemptionAsset;
    uint64 public immutable lockEnd;
    uint64 public immutable redeemStart;
    bool public immutable unrestrictedTransitions;

    bool public locked;
    bool public redemptionActivated;

    event Locked(uint256 totalAssetsSnapshot);
    event RedemptionActivated(uint256 requiredAssets);
    event ResetToInitialStage();

    constructor(
        address vault_,
        address hooks_,
        address transitionAdmin_,
        address depositToken_,
        address redemptionAsset_,
        uint64 lockEnd_,
        uint64 redeemStart_,
        bool unrestrictedTransitions_
    ) {
        vault = RedeemableToken(payable(vault_));
        hooks = IFeeHooks(hooks_);
        transitionAdmin = transitionAdmin_;
        depositToken = depositToken_;
        redemptionAsset = redemptionAsset_;
        lockEnd = lockEnd_;
        redeemStart = redeemStart_;
        unrestrictedTransitions = unrestrictedTransitions_;
    }

    function lock() external returns (uint256 totalAssetsSnapshot) {
        if (!unrestrictedTransitions && block.timestamp < lockEnd) {
            revert LockNotReady(block.timestamp, lockEnd);
        }
        totalAssetsSnapshot = _lock();
    }

    function activateRedemption() external returns (uint256 requiredAssets) {
        if (!unrestrictedTransitions && block.timestamp < redeemStart) {
            revert RedeemNotReady(block.timestamp, redeemStart);
        }
        requiredAssets = _activateRedemption();
    }

    function resetToInitialStage() external {
        if (!unrestrictedTransitions) {
            revert RestrictedController();
        }
        if (msg.sender != transitionAdmin) {
            revert TransitionAdminOnly(msg.sender);
        }
        if (!redemptionActivated) {
            revert RedemptionNotActivated();
        }

        vault.setAssetWithdrawable(redemptionAsset, false);

        IVault.AssetParams memory params = vault.getAsset(depositToken);
        IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
        vault.updateAsset(params.index, fields);
        hooks.setPerformanceFee(0);

        locked = false;
        redemptionActivated = false;

        emit ResetToInitialStage();
    }

    function _lock() internal returns (uint256 totalAssetsSnapshot) {
        if (locked) {
            revert AlreadyLocked();
        }

        vault.processAccounting();

        IVault.AssetParams memory params = vault.getAsset(depositToken);
        IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: false});
        vault.updateAsset(params.index, fields);
        hooks.setPerformanceFee(FEE_DENOMINATOR);

        locked = true;
        totalAssetsSnapshot = vault.totalAssets();

        emit Locked(totalAssetsSnapshot);
    }

    function _activateRedemption() internal returns (uint256 requiredAssets) {
        if (redemptionActivated) {
            revert RedemptionAlreadyActivated();
        }
        if (!locked) {
            revert NotLocked();
        }

        requiredAssets = vault.previewRedeem(vault.totalSupply());
        vault.setAssetWithdrawable(redemptionAsset, true);
        redemptionActivated = true;

        emit RedemptionActivated(requiredAssets);
    }
}
