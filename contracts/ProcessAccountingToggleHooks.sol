// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IHooks} from "yieldnest-vault/src/interface/IHooks.sol";
import {IVault} from "yieldnest-vault/src/interface/IVault.sol";

error ProcessAccountingBlocked();

contract ProcessAccountingToggleHooks is AccessControl, IHooks {
    bytes32 public constant TOGGLER_ROLE = keccak256("TOGGLER_ROLE");

    IVault public immutable VAULT;
    Config public config;
    bool public processAccountingBlocked;

    event SetProcessAccountingBlocked(bool blocked);

    constructor(address vault_, address admin_, Config memory config_) {
        VAULT = IVault(payable(vault_));
        config = config_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(TOGGLER_ROLE, admin_);
    }

    modifier onlyVault() {
        if (msg.sender != address(VAULT)) {
            revert CallerNotVault();
        }
        _;
    }

    function name() external pure returns (string memory) {
        return "ProcessAccountingToggleHooks";
    }

    function setConfig(Config memory config_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Config memory oldConfig = config;
        config = config_;
        emit SetConfig(oldConfig, config_);
    }

    function getConfig() external view returns (Config memory) {
        return config;
    }

    function setProcessAccountingBlocked(bool blocked) external onlyRole(TOGGLER_ROLE) {
        processAccountingBlocked = blocked;
        emit SetProcessAccountingBlocked(blocked);
    }

    function beforeProcessAccounting(BeforeProcessAccountingParams calldata) external view onlyVault {
        if (processAccountingBlocked) {
            revert ProcessAccountingBlocked();
        }
    }

    function beforeDeposit(DepositParams calldata) external onlyVault {}

    function afterDeposit(DepositParams calldata) external onlyVault {}

    function beforeMint(MintParams calldata) external onlyVault {}

    function afterMint(MintParams calldata) external onlyVault {}

    function beforeRedeem(RedeemParams calldata) external onlyVault {}

    function afterRedeem(RedeemParams calldata) external onlyVault {}

    function beforeWithdraw(WithdrawParams calldata) external onlyVault {}

    function afterWithdraw(WithdrawParams calldata) external onlyVault {}

    function afterProcessAccounting(AfterProcessAccountingParams calldata) external onlyVault {}
}
