# TERM REDEEMER

The term redeemer module  provides redemption functionality for MAX vault with a fixed redemption term.

It works in multiples stages.


At time T0, the module starts allowing locking of MAX vault shares for redemption. It issues a receipt token, Withdrawable ynMYVAULTx. wynMYVAULTx.

These receipt tokens are minted 1:1.

This is allowed up until time T1.

At time T1 locking ynMYVAULTx for wynMYVAULTx stops. At this point, the rate for redemption of wynMYVAULTx is locked in terms of the underyling ynMYVAULTx.asset().

This locked in rate is the redemption rate at time T2.

All this time wynMYVAULTx can move and trade freely, but going back through the system to ynMYVAULTx is not allowed.

T3 is the time at which wynMYVAULTx can be burned forthe underlying asset.

This effectively means that yield stops for wynMYVAULTx yholders at time T2.


AT t3, the module can call withrawAsset onto the MAX Vault. for the exact amount of USDC needed. then it approves the extra ynRWAx to a trusted address to pull and use as it sees fit.

At T3 the users can start burning their wynMYVAULTx for the underlying asset indefinitely.

Do a very slick, simple implementation of this.

assume all the T times are known ahead of time and setup at initialization.

Obviously it needs to be configurable in terms of the asset.


