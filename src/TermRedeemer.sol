// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

interface IMaxVault is IERC20Metadata {
    function asset() external view returns (address);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function withdrawAsset(address asset, uint256 assets, address receiver, address owner)
        external
        returns (uint256 sharesBurned);
}

error ZeroAddress();
error ZeroAmount();
error InvalidLockWindow(uint64 lockStart, uint64 lockEnd);
error InvalidRedeemTime(uint64 lockEnd, uint64 redeemStart);
error LockNotStarted(uint256 timestamp, uint64 lockStart);
error LockClosed(uint256 timestamp, uint64 lockEnd);
error LockWindowActive(uint256 timestamp, uint64 lockEnd);
error RateAlreadyLocked();
error ZeroRate();
error RedeemNotStarted(uint256 timestamp, uint64 redeemStart);
error RedemptionAlreadyPrepared();
error RateNotLocked();

contract TermReceiptToken is ERC20 {
    error ReceiptUnauthorized(address caller);

    address public immutable minter;
    uint8 private immutable tokenDecimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address minter_) ERC20(name_, symbol_) {
        if (minter_ == address(0)) {
            revert ZeroAddress();
        }

        minter = minter_;
        tokenDecimals = decimals_;
    }

    function mint(address to, uint256 value) external {
        if (msg.sender != minter) {
            revert ReceiptUnauthorized(msg.sender);
        }

        _mint(to, value);
    }

    function burn(address from, uint256 value) external {
        if (msg.sender != minter) {
            revert ReceiptUnauthorized(msg.sender);
        }

        _burn(from, value);
    }

    function burnFrom(address from, address spender, uint256 value) external {
        if (msg.sender != minter) {
            revert ReceiptUnauthorized(msg.sender);
        }

        _spendAllowance(from, spender, value);
        _burn(from, value);
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }
}

contract TermRedeemer is Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    struct Schedule {
        uint64 lockStart;
        uint64 lockEnd;
        uint64 redeemStart;
    }

    IMaxVault public immutable vault;
    IERC20 public immutable asset;
    TermReceiptToken public immutable receiptToken;
    address public immutable residualSharesSpender;
    uint256 public immutable shareScale;
    Schedule public schedule;

    uint256 public lockedAssetPerShare;
    bool public rateLocked;
    bool public redemptionPrepared;

    event Locked(address indexed account, address indexed receiver, uint256 shareAmount);
    event RedemptionRateLocked(uint256 assetPerShare);
    event RedemptionPrepared(uint256 assetsWithdrawn, uint256 residualSharesApproved);
    event Redeemed(address indexed account, address indexed receiver, uint256 receiptAmount, uint256 assetAmount);

    constructor(
        address owner_,
        address vault_,
        address residualSharesSpender_,
        uint64 lockStart_,
        uint64 lockEnd_,
        uint64 redeemStart_
    ) Ownable(owner_) {
        if (vault_ == address(0) || residualSharesSpender_ == address(0)) {
            revert ZeroAddress();
        }
        if (lockStart_ >= lockEnd_) {
            revert InvalidLockWindow(lockStart_, lockEnd_);
        }
        if (lockEnd_ > redeemStart_) {
            revert InvalidRedeemTime(lockEnd_, redeemStart_);
        }

        vault = IMaxVault(vault_);
        asset = IERC20(IMaxVault(vault_).asset());
        residualSharesSpender = residualSharesSpender_;
        schedule = Schedule({lockStart: lockStart_, lockEnd: lockEnd_, redeemStart: redeemStart_});

        uint8 shareDecimals = IERC20Metadata(vault_).decimals();
        shareScale = 10 ** uint256(shareDecimals);

        receiptToken = new TermReceiptToken(
            string.concat("Withdrawable ", IERC20Metadata(vault_).name()),
            string.concat("w", IERC20Metadata(vault_).symbol()),
            shareDecimals,
            address(this)
        );
    }

    function deposit(uint256 shareAmount, address receiver) external returns (uint256 receiptAmount) {
        if (block.timestamp < schedule.lockStart) {
            revert LockNotStarted(block.timestamp, schedule.lockStart);
        }
        if (block.timestamp >= schedule.lockEnd) {
            revert LockClosed(block.timestamp, schedule.lockEnd);
        }
        if (receiver == address(0)) {
            revert ZeroAddress();
        }
        if (shareAmount == 0) {
            revert ZeroAmount();
        }

        receiptAmount = shareAmount;
        IERC20(address(vault)).safeTransferFrom(msg.sender, address(this), shareAmount);
        receiptToken.mint(receiver, receiptAmount);

        emit Locked(msg.sender, receiver, shareAmount);
    }

    function lockRedemptionRate() public returns (uint256 assetPerShare) {
        if (block.timestamp < schedule.lockEnd) {
            revert LockWindowActive(block.timestamp, schedule.lockEnd);
        }
        if (rateLocked) {
            revert RateAlreadyLocked();
        }

        assetPerShare = vault.convertToAssets(shareScale);
        if (assetPerShare == 0) {
            revert ZeroRate();
        }

        lockedAssetPerShare = assetPerShare;
        rateLocked = true;

        emit RedemptionRateLocked(assetPerShare);
    }

    function prepareRedemption() external onlyOwner returns (uint256 assetsNeeded, uint256 residualShares) {
        if (block.timestamp < schedule.redeemStart) {
            revert RedeemNotStarted(block.timestamp, schedule.redeemStart);
        }
        if (redemptionPrepared) {
            revert RedemptionAlreadyPrepared();
        }

        if (!rateLocked) {
            lockRedemptionRate();
        }

        assetsNeeded = previewRedeem(receiptToken.totalSupply());
        if (assetsNeeded > 0) {
            vault.withdrawAsset(address(asset), assetsNeeded, address(this), address(this));
        }

        residualShares = vault.balanceOf(address(this));
        IERC20(address(vault)).forceApprove(residualSharesSpender, residualShares);

        redemptionPrepared = true;

        emit RedemptionPrepared(assetsNeeded, residualShares);
    }

    function redeem(uint256 receiptAmount, address receiver, address owner_) external returns (uint256 assetAmount) {
        if (block.timestamp < schedule.redeemStart) {
            revert RedeemNotStarted(block.timestamp, schedule.redeemStart);
        }
        if (!rateLocked) {
            revert RateNotLocked();
        }
        if (receiver == address(0) || owner_ == address(0)) {
            revert ZeroAddress();
        }
        if (receiptAmount == 0) {
            revert ZeroAmount();
        }

        assetAmount = previewRedeem(receiptAmount);
        if (msg.sender == owner_) {
            receiptToken.burn(owner_, receiptAmount);
        } else {
            receiptToken.burnFrom(owner_, msg.sender, receiptAmount);
        }
        asset.safeTransfer(receiver, assetAmount);

        emit Redeemed(owner_, receiver, receiptAmount, assetAmount);
    }

    function previewRedeem(uint256 receiptAmount) public view returns (uint256) {
        return receiptAmount.mulDiv(lockedAssetPerShare, shareScale);
    }
}
