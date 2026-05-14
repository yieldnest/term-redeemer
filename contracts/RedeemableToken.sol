// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {BaseStrategy} from "yieldnest-vault/src/strategy/BaseStrategy.sol";
import {VaultLib} from "yieldnest-vault/src/library/VaultLib.sol";

error ZeroAddress();

contract RedeemableToken is BaseStrategy {
    string public constant TERM_REDEEMER_VERSION = "1.0.0";

    address public baseAsset;
    address public redemptionAsset;
    address public depositToken;

    function initialize(
        address admin,
        address provider_,
        address baseAsset_,
        address redemptionAsset_,
        address depositToken_,
        string memory name_,
        string memory symbol_
    ) external initializer {
        if (
            admin == address(0) || provider_ == address(0) || baseAsset_ == address(0) || redemptionAsset_ == address(0)
                || depositToken_ == address(0)
        ) {
            revert ZeroAddress();
        }

        _initialize(admin, name_, symbol_, IERC20Metadata(baseAsset_).decimals(), false, false, false, 1);

        _grantRole(PROCESSOR_ROLE, admin);
        _grantRole(PROCESSOR_MANAGER_ROLE, admin);
        _grantRole(PROVIDER_MANAGER_ROLE, admin);
        _grantRole(ASSET_MANAGER_ROLE, admin);
        _grantRole(HOOKS_MANAGER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(UNPAUSER_ROLE, admin);

        VaultLib.setProvider(provider_);

        baseAsset = baseAsset_;
        redemptionAsset = redemptionAsset_;
        depositToken = depositToken_;

        _addAsset(baseAsset_, IERC20Metadata(baseAsset_).decimals(), false);
        _setAssetWithdrawable(baseAsset_, false);

        _addAsset(redemptionAsset_, IERC20Metadata(redemptionAsset_).decimals(), false);
        _setAssetWithdrawable(redemptionAsset_, false);

        _addAsset(depositToken_, IERC20Metadata(depositToken_).decimals(), true);
        _setAssetWithdrawable(depositToken_, false);
    }

    function _feeOnRaw(uint256, address) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256, address) public pure override returns (uint256) {
        return 0;
    }
}
