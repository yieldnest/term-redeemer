// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Contracts {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    string internal constant AMOUNT_ENV = "AMOUNT";

    string internal constant MOCK_YNRWAX_PROVIDER_KEY = "mock-ynrwax-provider";
    string internal constant MOCK_YNRWAX_IMPLEMENTATION_KEY = "mock-ynrwax-implementation";
    string internal constant MOCK_YNRWAX_KEY = "mock-ynrwax";

    string internal constant TERM_PROVIDER_KEY = "term-provider";
    string internal constant TERM_IMPLEMENTATION_KEY = "term-implementation";
    string internal constant TERM_FACTORY_KEY = "term-factory";
    string internal constant TERM_VAULT_KEY = "term-vault";
    string internal constant TERM_HOOKS_KEY = "term-hooks";
    string internal constant TERM_CONTROLLER_KEY = "term-controller";

    string internal constant MOCK_YNRWAX_NAME = "Mock ynRWAx";
    string internal constant MOCK_YNRWAX_SYMBOL = "mynRWAx";
    string internal constant TERM_VAULT_NAME = "Withdrawable Mock ynRWAx";
    string internal constant TERM_VAULT_SYMBOL = "wmynRWAx";

    string internal constant MOCK_YNRWAX_LABEL = "Mock ynRWAx";
    string internal constant MOCK_YNRWAX_PROVIDER_LABEL = "Mock ynRWAx provider";
    string internal constant TERM_VAULT_LABEL = "Term vault";
    string internal constant TERM_HOOKS_LABEL = "Term hooks";
    string internal constant TERM_CONTROLLER_LABEL = "Term controller";

    uint8 internal constant VAULT_DECIMALS = 18;
    uint256 internal constant ONE = 1e18;
    uint256 internal constant TEST_STAGE_TIME = 0;
    uint256 internal constant DEFAULT_ASSET_INDEX = 0;
}
