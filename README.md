## Term Redeemer

This repo contains a simple fixed-term redeemer for a MAX-style vault.

Flow:

1. Between `lockStart` and `lockEnd`, users lock vault shares into `RedeemableToken`.
2. The contract mints a transferable receipt token 1:1 with the locked shares.
3. After `lockEnd`, the contract snapshots a fixed `assetPerShare` redemption rate.
4. At `redeemStart`, the owner can withdraw the exact underlying asset required for all outstanding receipts and approve any residual vault shares to a trusted address.
5. Receipt holders can then burn receipts for the underlying asset indefinitely.

Key files:

- `contracts/RedeemableToken.sol`: core redeemable vault token
- `test/TermRedeemer.t.sol`: timeline and redemption tests
- `test/mocks/MockERC20.sol`, `test/mocks/MockMaxVault.sol`: local test doubles

Commands:

```sh
forge build
forge test
forge fmt
```
