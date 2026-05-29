// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseStrategy} from "yieldnest-vault/src/strategy/BaseStrategy.sol";

contract RedeemableToken is BaseStrategy {
    string public constant TERM_REDEEMER_VERSION = "1.0.0";

    struct InitParams {
        address admin;
        string name;
        string symbol;
        uint8 decimals_;
        bool countNativeAsset_;
        bool alwaysComputeTotalAssets_;
        uint256 defaultAssetIndex_;
    }

    /**
     * @notice Initializes the strategy.
     * @param params The struct containing all initialization parameters.
     */
    function initialize(InitParams calldata params) external virtual initializer {
        _initialize(
            params.admin,
            params.name,
            params.symbol,
            params.decimals_,
            true, // Start paused so roles, assets, provider, and hooks can be configured safely post-init.
            params.countNativeAsset_,
            params.alwaysComputeTotalAssets_,
            params.defaultAssetIndex_
        );
    }

    function _feeOnRaw(uint256, address) public pure override returns (uint256) {
        return 0;
    }

    function _feeOnTotal(uint256, address) public pure override returns (uint256) {
        return 0;
    }
}
