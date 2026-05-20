// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Constants {
    string internal constant AMOUNT_ENV = "AMOUNT";

    string internal constant MOCK_YNRWAX_NAMESPACE = "test-mock-ynrwax";
    string internal constant SHARED_NAMESPACE = "test-shared";
    string internal constant WRAPPED_USDC_KEY = "wrappedUsdc";
    string internal constant TERM_NAMESPACE = "test-term-redeemer";
    string internal constant MOCK_YNRWAX_PROVIDER_KEY = "mockYnRwaProvider";
    string internal constant MOCK_YNRWAX_IMPLEMENTATION_KEY = "mockYnRwaImplementation";
    string internal constant MOCK_YNRWAX_KEY = "mockYnRwa";

    string internal constant TERM_PROVIDER_KEY = "termProvider";
    string internal constant TERM_IMPLEMENTATION_KEY = "termImplementation";
    string internal constant TERM_FACTORY_KEY = "termFactory";
    string internal constant TERM_VAULT_KEY = "termVault";
    string internal constant TERM_HOOKS_KEY = "termHooks";
    string internal constant TERM_CONTROLLER_KEY = "termController";

    string internal constant MOCK_YNRWAX_NAME = "Mock ynRWAx";
    string internal constant MOCK_YNRWAX_SYMBOL = "mynRWAx";
    string internal constant TERM_VAULT_NAME = "Withdrawable Mock ynRWAx";
    string internal constant TERM_VAULT_SYMBOL = "wmynRWAx";

    string internal constant MOCK_YNRWAX_LABEL = "Mock ynRWAx";
    string internal constant MOCK_YNRWAX_PROVIDER_LABEL = "Mock ynRWAx provider";
    string internal constant WRAPPED_USDC_LABEL = "Wrapped USDC";
    string internal constant TERM_VAULT_LABEL = "Term vault";
    string internal constant TERM_HOOKS_LABEL = "Term hooks";
    string internal constant TERM_CONTROLLER_LABEL = "Term controller";

    uint8 internal constant VAULT_DECIMALS = 18;
    uint256 internal constant ONE = 1e18;
    uint256 internal constant DEFAULT_ASSET_INDEX = 1;
}
