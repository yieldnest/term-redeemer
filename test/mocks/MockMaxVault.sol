// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMaxVault} from "../../src/TermRedeemer.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

error MockMaxVaultZeroReceiver();

contract MockMaxVault is ERC20, IMaxVault {
    using SafeERC20 for IERC20;

    address public immutable override asset;
    uint256 public assetsPerShare;

    IERC20 internal immutable assetToken;
    uint8 private immutable tokenDecimals;

    constructor(address asset_, string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        asset = asset_;
        assetToken = IERC20(asset_);
        tokenDecimals = decimals_;
        assetsPerShare = 10 ** uint256(decimals_);
    }

    function setAssetsPerShare(uint256 newAssetsPerShare) external {
        assetsPerShare = newAssetsPerShare;
    }

    function mintShares(address to, uint256 shares) external {
        _mint(to, shares);
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return tokenDecimals;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares * assetsPerShare / (10 ** uint256(tokenDecimals));
    }

    function withdrawAsset(address, uint256 assets, address receiver, address owner)
        external
        returns (uint256 sharesBurned)
    {
        if (receiver == address(0)) {
            revert MockMaxVaultZeroReceiver();
        }

        uint256 shareScale = 10 ** uint256(tokenDecimals);
        sharesBurned = (assets * shareScale + assetsPerShare - 1) / assetsPerShare;

        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, sharesBurned);
        }
        _burn(owner, sharesBurned);
        assetToken.safeTransfer(receiver, assets);
    }
}
