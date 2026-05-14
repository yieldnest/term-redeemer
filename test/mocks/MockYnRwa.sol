// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MockYnRwa is ERC20 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    uint256 public usdcPerShare;

    constructor(address usdc_) ERC20("YieldNest RWA", "ynRWAx") {
        usdc = IERC20(usdc_);
    }

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }

    function setUsdcPerShare(uint256 usdcPerShare_) external {
        usdcPerShare = usdcPerShare_;
    }

    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        assets = shares.mulDiv(usdcPerShare, 10 ** decimals());
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        assets = previewRedeem(shares);
        _burn(owner, shares);
        usdc.safeTransfer(receiver, assets);
    }
}
