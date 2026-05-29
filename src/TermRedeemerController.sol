// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IFeeHooks} from "yieldnest-vault/src/interface/IFeeHooks.sol";
import {RedeemableToken} from "contracts/RedeemableToken.sol";

error LockNotReady(uint256 timestamp, uint64 lockEnd);
error RedeemNotReady(uint256 timestamp, uint64 redeemStart);
error AlreadyLocked();
error NotLocked();
error RedemptionAlreadyActivated();
error GetAssetFailed();
error UpdateAssetFailed();

contract TermRedeemerController {
    uint256 internal constant FEE_DENOMINATOR = 1 ether;

    RedeemableToken public immutable vault;
    IFeeHooks public immutable hooks;
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
        vault = RedeemableToken(payable(vault_));
        hooks = IFeeHooks(hooks_);
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

        _setDepositAssetActive(false);
        hooks.setPerformanceFee(FEE_DENOMINATOR);

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

        requiredAssets = vault.previewRedeem(vault.totalSupply());
        vault.setAssetWithdrawable(redemptionAsset, true);
        redemptionActivated = true;

        emit RedemptionActivated(requiredAssets);
    }

    function _setDepositAssetActive(bool isActive) internal {
        (bool ok, bytes memory data) = address(vault).staticcall(abi.encodeWithSignature("getAsset(address)", depositToken));
        if (!ok) {
            revert GetAssetFailed();
        }

        (uint256 index,,) = abi.decode(data, (uint256, bool, uint8));
        (ok,) = address(vault).call(abi.encodeWithSignature("updateAsset(uint256,(bool))", index, isActive));
        if (!ok) {
            revert UpdateAssetFailed();
        }
    }
}
