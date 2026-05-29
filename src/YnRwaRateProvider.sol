// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IProvider} from "yieldnest-vault/src/interface/IProvider.sol";

error UnsupportedAsset(address asset);
error ZeroAddress();

interface IYnRwaPreviewRedeem {
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
}

contract YnRwaRateProvider is IProvider {
    uint256 internal constant SHARE_UNIT = 1 ether;
    uint256 internal constant USDC_BASE_SCALE = 1e12;

    address public immutable wrappedUsdc;
    address public immutable usdc;
    address public immutable ynRwa;

    constructor(address wrappedUsdc_, address usdc_, address ynRwa_) {
        if (wrappedUsdc_ == address(0) || usdc_ == address(0) || ynRwa_ == address(0)) {
            revert ZeroAddress();
        }

        wrappedUsdc = wrappedUsdc_;
        usdc = usdc_;
        ynRwa = ynRwa_;
    }

    function getRate(address asset) external view returns (uint256) {
        if (asset == wrappedUsdc || asset == usdc) {
            return 1e18;
        }

        if (asset == ynRwa) {
            return IYnRwaPreviewRedeem(ynRwa).previewRedeem(SHARE_UNIT) * USDC_BASE_SCALE;
        }

        revert UnsupportedAsset(asset);
    }
}
