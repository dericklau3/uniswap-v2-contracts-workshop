# UniswapV2TwapOracleTest

This test forks Ethereum mainnet and deploys `UniswapV2TwapOracle` with USDT as the quote token. By default it forks the latest block so a non-archive RPC can run it. Set `MAINNET_FORK_BLOCK` when using an archive RPC to pin the result.

The setup discovers the canonical Uniswap V2 `WETH/USDT` and `WBTC/USDT` pairs through the mainnet factory, then registers both pairs in the oracle.

The two scenarios advance time by the oracle's 12 hour period, update each token, and print:

- the Uniswap V2 pair address
- the oracle's raw reserve-ratio price scaled by `1e18`
- the normalized display value as USDT per ETH or WBTC, scaled by `1e18`
- the whole-number USDT display value

Because the tests only warp time and do not trade, the TWAP should closely match the pair spot price computed from the same reserves. The display normalization accounts for USDT's 6 decimals, WETH's 18 decimals, and WBTC's 8 decimals.
