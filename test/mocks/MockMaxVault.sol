// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Base, IERC20Minimal, IMaxVault} from "../../src/TermRedeemer.sol";

contract MockMaxVault is ERC20Base, IMaxVault {
    address public immutable override asset;
    uint256 public assetsPerShare;
    IERC20Minimal internal immutable assetToken;

    constructor(address asset_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20Base(name_, symbol_, decimals_)
    {
        asset = asset_;
        assetToken = IERC20Minimal(asset_);
        assetsPerShare = 10 ** uint256(decimals_);
    }

    function setAssetsPerShare(uint256 newAssetsPerShare) external {
        assetsPerShare = newAssetsPerShare;
    }

    function mintShares(address to, uint256 shares) external {
        _mint(to, shares);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares * assetsPerShare / (10 ** uint256(decimals));
    }

    function withdrawAsset(uint256 assets, address receiver) external returns (uint256 sharesBurned) {
        require(receiver != address(0), "MockMaxVault: zero receiver");

        uint256 shareScale = 10 ** uint256(decimals);
        sharesBurned = (assets * shareScale + assetsPerShare - 1) / assetsPerShare;

        _burn(msg.sender, sharesBurned);
        require(assetToken.transfer(receiver, assets), "MockMaxVault: transfer failed");
    }
}
