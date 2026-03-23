## 0.1.0

> Note: This release has breaking changes.

 - **PERF**(logs): reduce market metrics log verbosity and duplication (#223).
 - **FIX**(sdk): close balance and pubkeysubscriptions on auth state changes (#232).
 - **FIX**(binance): use the per-coin supported quote currency list instead of the global cache (#224).
 - **FEAT**(cex-market-data): add CoinPaprika API provider as a fallback option (#215).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

## 0.0.3+1

 - Update a dependency to the latest release.

## 0.0.3

 - **FIX**(cex-market-data): coingecko ohlc parsing (#203).
 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

## 0.0.2+1

 - **FEAT**(market-data): add support for multiple market data providers (#145).
 - **FEAT**: offline private key export (#160).
 - **FEAT**: migrate komodo_cex_market_data from komod-wallet (#37).

## 0.0.1

- Initial version.

## 0.0.2

- docs: README with bootstrap, config, and SDK integration examples
