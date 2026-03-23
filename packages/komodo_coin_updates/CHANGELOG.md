## 2.0.0

> Note: This release has breaking changes.

 - **PERF**(logs): reduce market metrics log verbosity and duplication (#223).
 - **FIX**(startup): handle 6133 seed fallback and invalid configs (#318).
 - **FIX**(config): loosen types for needs transform check and fix lightwalletservers type.
 - **FIX**(config): add ssl-only transform for native platforms.
 - **FIX**(sdk): close balance and pubkeysubscriptions on auth state changes (#232).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**(sdk): add token safety and fee support helpers (#319).
 - **FEAT**(coins): Add TRON and TRC20 support (#316).
 - **FEAT**(message-signing): Add AddressPath type and refactor to use Asset/PubkeyInfo (#231).
 - **FEAT**(coin-config): add custom token support to coin config manager (#225).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

## 1.1.1

 - Update a dependency to the latest release.

## 1.1.0

 - **FIX**(deps): misc deps fixes.
 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

## 1.0.1

> Note: This release has breaking changes.

 - **FIX**(deps): misc deps fixes.
 - **FIX**: unify+upgrade Dart/Flutter versions.
 - **FEAT**(seed): update seed node format (#87).
 - **FEAT**: add configurable seed node system with remote fetching (#85).
 - **FEAT**: runtime coin updates  (#38).
 - **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).

## 1.0.0

- chore: add LICENSE; loosen hive constraints; hosted komodo_defi_types
