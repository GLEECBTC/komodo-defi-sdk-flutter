# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2026-03-23

### Changes

---

Packages with breaking changes:

 - [`komodo_cex_market_data` - `v0.1.0`](#komodo_cex_market_data---v010)
 - [`komodo_coin_updates` - `v2.0.0`](#komodo_coin_updates---v200)
 - [`komodo_defi_framework` - `v0.4.0`](#komodo_defi_framework---v040)
 - [`komodo_defi_local_auth` - `v0.4.0`](#komodo_defi_local_auth---v040)
 - [`komodo_defi_rpc_methods` - `v0.4.0`](#komodo_defi_rpc_methods---v040)
 - [`komodo_defi_sdk` - `v0.5.0`](#komodo_defi_sdk---v050)
 - [`komodo_defi_types` - `v0.4.0`](#komodo_defi_types---v040)
 - [`komodo_wallet_cli` - `v0.5.0`](#komodo_wallet_cli---v050)

Packages with other changes:

 - [`dragon_charts_flutter` - `v0.1.1-dev.4`](#dragon_charts_flutter---v011-dev4)
 - [`dragon_logs` - `v2.0.1`](#dragon_logs---v201)
 - [`komodo_coins` - `v0.3.2`](#komodo_coins---v032)
 - [`komodo_ui` - `v0.3.1`](#komodo_ui---v031)
 - [`komodo_wallet_build_transformer` - `v0.4.1`](#komodo_wallet_build_transformer---v041)

---

#### `komodo_cex_market_data` - `v0.1.0`

 - **PERF**(logs): reduce market metrics log verbosity and duplication (#223).
 - **FIX**(sdk): close balance and pubkeysubscriptions on auth state changes (#232).
 - **FIX**(binance): use the per-coin supported quote currency list instead of the global cache (#224).
 - **FEAT**(cex-market-data): add CoinPaprika API provider as a fallback option (#215).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_coin_updates` - `v2.0.0`

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

#### `komodo_defi_framework` - `v0.4.0`

 - **REFACTOR**(macos): streamline KDF binary placement; update signing flow (#247).
 - **FIX**(streaming): gate enable_* calls on real SSE first-byte event (#332).
 - **FIX**(auth): add mutex-protected atomic metadata updates (#328).
 - **FIX**(startup): handle 6133 seed fallback and invalid configs (#318).
 - **FIX**(web): improve wasm JS interop bindings (#315).
 - **FIX**(web): complete wasm-safe sdk interop cleanup (#313).
 - **FIX**: re-format build config.
 - **FIX**: swap zcash params primary/backup URLs to use official z.cash as primary (#301).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FIX**(auth): store bip39 compatibility regardless of wallet type (#216).
 - **FIX**(komodo_defi_framework): rename transformer marker and update references\n\n- Use assets/transformer_invoker.txt instead of dotfile\n- Update pubspec and READMEs\n- Remove special .gitignore unignore.
 - **FEAT**(sdk): add token safety and fee support helpers (#319).
 - **FEAT**(sdk): typed error handling, trading streams, and activation refactoring (#312).
 - **FEAT**: add support for ETH-BASE and derived assets (#254).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_defi_local_auth` - `v0.4.0`

 - **FIX**(test): add missing updateActiveUserMetadataKey to fake auth service (#330).
 - **FIX**(auth): add mutex-protected atomic metadata updates (#328).
 - **FIX**(auth): store bip39 compatibility regardless of wallet type (#216).
 - **FEAT**(sdk): typed error handling, trading streams, and activation refactoring (#312).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_defi_rpc_methods` - `v0.4.0`

 - **FIX**(sdk): close balance and pubkeysubscriptions on auth state changes (#232).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**(coins): Add TRON and TRC20 support (#316).
 - **FEAT**(sdk): typed error handling, trading streams, and activation refactoring (#312).
 - **FEAT**(message-signing): Add AddressPath type and refactor to use Asset/PubkeyInfo (#231).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_defi_sdk` - `v0.5.0`

 - **FIX**(streaming): gate enable_* calls on real SSE first-byte event (#332).
 - **FIX**(withdrawals): remove duplicate executeWithdrawal method (#322).
 - **FIX**(sdk): expose custom token cleanup (#321).
 - **FIX**: swap zcash params primary/backup URLs to use official z.cash as primary (#301).
 - **FIX**(sdk): close balance and pubkeysubscriptions on auth state changes (#232).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FIX**(custom-token-import): refresh asset list on import and use lowercase for custom token import (#220).
 - **FEAT**(sdk): add SIA activation and withdrawal support (#320).
 - **FEAT**(sdk): add token safety and fee support helpers (#319).
 - **FEAT**(coins): Add TRON and TRC20 support (#316).
 - **FEAT**(sdk): add high-level balance/transaction manager interfaces (#314).
 - **FEAT**(sdk): typed error handling, trading streams, and activation refactoring (#312).
 - **FEAT**(activation): integrate ActivatedAssetsCache to optimize asset activation checks.
 - **FEAT**: add support for ETH-BASE and derived assets (#254).
 - **FEAT**(message-signing): Add AddressPath type and refactor to use Asset/PubkeyInfo (#231).
 - **FEAT**(coin-config): add custom token support to coin config manager (#225).
 - **FEAT**(cex-market-data): add CoinPaprika API provider as a fallback option (#215).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_defi_types` - `v0.4.0`

 - **FIX**(types): use reified generics in JSON traversal for wasm/minified builds (#329).
 - **FIX**(startup): handle 6133 seed fallback and invalid configs (#318).
 - **FIX**(asset-tagging): correct UTXO coins incorrectly tagged as Smart Chain (#244).
 - **FIX**(sdk): close balance and pubkeysubscriptions on auth state changes (#232).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FIX**(custom-token-import): refresh asset list on import and use lowercase for custom token import (#220).
 - **FEAT**(sdk): add token safety and fee support helpers (#319).
 - **FEAT**(coins): Add TRON and TRC20 support (#316).
 - **FEAT**(sdk): typed error handling, trading streams, and activation refactoring (#312).
 - **FEAT**: add support for ETH-BASE and derived assets (#254).
 - **FEAT**(coin-config): add custom token support to coin config manager (#225).
 - **FEAT**(types): parent display name suffix via subclass (#213).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_wallet_cli` - `v0.5.0`

 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `dragon_charts_flutter` - `v0.1.1-dev.4`

 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**: add configurable sparkline baseline (#248).

#### `dragon_logs` - `v2.0.1`

 - **FIX**(web): improve wasm JS interop bindings (#315).
 - **FIX**(zhltc): zhltc activation fixes (#227).

#### `komodo_coins` - `v0.3.2`

 - **PERF**(logs): reduce market metrics log verbosity and duplication (#223).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**(coin-config): add custom token support to coin config manager (#225).

#### `komodo_ui` - `v0.3.1`

 - **FIX**(ui): detect asset icon precache failures (#326).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FIX**(custom-token-import): refresh asset list on import and use lowercase for custom token import (#220).
 - **FEAT**(coins): Add TRON and TRC20 support (#316).
 - **FEAT**(sdk): typed error handling, trading streams, and activation refactoring (#312).

#### `komodo_wallet_build_transformer` - `v0.4.1`

 - **FIX**: swap zcash params primary/backup URLs to use official z.cash as primary (#301).
 - **FIX**(komodo_defi_framework): rename transformer marker and update references\n\n- Use assets/transformer_invoker.txt instead of dotfile\n- Update pubspec and READMEs\n- Remove special .gitignore unignore.
 - **FEAT**(sdk): typed error handling, trading streams, and activation refactoring (#312).


## 2025-08-25

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`komodo_defi_types` - `v0.3.2+1`](#komodo_defi_types---v0321)
 - [`komodo_wallet_cli` - `v0.4.0+1`](#komodo_wallet_cli---v0401)
 - [`komodo_ui` - `v0.3.0+3`](#komodo_ui---v0303)
 - [`komodo_defi_sdk` - `v0.4.0+3`](#komodo_defi_sdk---v0403)
 - [`komodo_defi_rpc_methods` - `v0.3.1+1`](#komodo_defi_rpc_methods---v0311)
 - [`komodo_defi_local_auth` - `v0.3.1+2`](#komodo_defi_local_auth---v0312)
 - [`komodo_defi_framework` - `v0.3.1+2`](#komodo_defi_framework---v0312)
 - [`komodo_coins` - `v0.3.1+2`](#komodo_coins---v0312)
 - [`komodo_coin_updates` - `v1.1.1`](#komodo_coin_updates---v111)
 - [`komodo_cex_market_data` - `v0.0.3+1`](#komodo_cex_market_data---v0031)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `komodo_ui` - `v0.3.0+3`
 - `komodo_defi_sdk` - `v0.4.0+3`
 - `komodo_defi_rpc_methods` - `v0.3.1+1`
 - `komodo_defi_local_auth` - `v0.3.1+2`
 - `komodo_defi_framework` - `v0.3.1+2`
 - `komodo_coins` - `v0.3.1+2`
 - `komodo_coin_updates` - `v1.1.1`
 - `komodo_cex_market_data` - `v0.0.3+1`

---

#### `komodo_defi_types` - `v0.3.2+1`

 - **DOCS**(komodo_defi_types): update CHANGELOG for 0.3.2 with pub submission fix.

#### `komodo_wallet_cli` - `v0.4.0+1`

 - **REFACTOR**(komodo_wallet_cli): replace print() with stdout/stderr and improve logging.


## 2025-08-25

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`komodo_coins` - `v0.3.1+1`](#komodo_coins---v0311)
 - [`komodo_defi_sdk` - `v0.4.0+2`](#komodo_defi_sdk---v0402)
 - [`komodo_defi_framework` - `v0.3.1+1`](#komodo_defi_framework---v0311)
 - [`komodo_defi_local_auth` - `v0.3.1+1`](#komodo_defi_local_auth---v0311)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `komodo_defi_sdk` - `v0.4.0+2`
 - `komodo_defi_framework` - `v0.3.1+1`
 - `komodo_defi_local_auth` - `v0.3.1+1`

---

#### `komodo_coins` - `v0.3.1+1`

 - **FIX**: add missing deps.


## 2025-08-25

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`komodo_defi_sdk` - `v0.4.0+1`](#komodo_defi_sdk---v0401)

---

#### `komodo_defi_sdk` - `v0.4.0+1`

 - **FIX**: add missing dependency.


## 2025-08-25

### Changes

---

Packages with breaking changes:

 - [`dragon_charts_flutter` - `v0.1.1-dev.3`](#dragon_charts_flutter---v011-dev3)
 - [`dragon_logs` - `v2.0.0`](#dragon_logs---v200)
 - [`komodo_defi_sdk` - `v0.4.0`](#komodo_defi_sdk---v040)
 - [`komodo_wallet_build_transformer` - `v0.4.0`](#komodo_wallet_build_transformer---v040)
 - [`komodo_wallet_cli` - `v0.4.0`](#komodo_wallet_cli---v040)

Packages with other changes:

 - [`komodo_cex_market_data` - `v0.0.3`](#komodo_cex_market_data---v003)
 - [`komodo_coin_updates` - `v1.1.0`](#komodo_coin_updates---v110)
 - [`komodo_coins` - `v0.3.1`](#komodo_coins---v031)
 - [`komodo_defi_framework` - `v0.3.1`](#komodo_defi_framework---v031)
 - [`komodo_defi_local_auth` - `v0.3.1`](#komodo_defi_local_auth---v031)
 - [`komodo_defi_rpc_methods` - `v0.3.1`](#komodo_defi_rpc_methods---v031)
 - [`komodo_defi_types` - `v0.3.1`](#komodo_defi_types---v031)
 - [`komodo_ui` - `v0.3.0+2`](#komodo_ui---v0302)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `komodo_ui` - `v0.3.0+2`

---

#### `dragon_charts_flutter` - `v0.1.1-dev.3`

 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

#### `dragon_logs` - `v2.0.0`

 - **FIX**(deps): misc deps fixes.
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

#### `komodo_defi_sdk` - `v0.4.0`

 - **FIX**(cex-market-data): coingecko ohlc parsing (#203).
 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

#### `komodo_wallet_build_transformer` - `v0.4.0`

 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

#### `komodo_wallet_cli` - `v0.4.0`

 - **FIX**(pub): add non-generic description.
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

#### `komodo_cex_market_data` - `v0.0.3`

 - **FIX**(cex-market-data): coingecko ohlc parsing (#203).
 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

#### `komodo_coin_updates` - `v1.1.0`

 - **FIX**(deps): misc deps fixes.
 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

#### `komodo_coins` - `v0.3.1`

 - **FIX**: pub submission errors.
 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

#### `komodo_defi_framework` - `v0.3.1`

 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

#### `komodo_defi_local_auth` - `v0.3.1`

 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

#### `komodo_defi_rpc_methods` - `v0.3.1`

 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

#### `komodo_defi_types` - `v0.3.1`

 - **FIX**: pub submission errors.
 - **FIX**(deps): resolve deps error.
 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).


## 2025-08-21

### Changes

---

Packages with breaking changes:

- [`dragon_charts_flutter` - `v0.1.1-dev.2`](#dragon_charts_flutter---v011-dev2)
- [`dragon_logs` - `v1.2.1`](#dragon_logs---v121)
- [`komodo_coin_updates` - `v1.0.1`](#komodo_coin_updates---v101)
- [`komodo_coins` - `v0.3.0+1`](#komodo_coins---v0301)
- [`komodo_defi_framework` - `v0.3.0+1`](#komodo_defi_framework---v0301)
- [`komodo_defi_local_auth` - `v0.3.0+1`](#komodo_defi_local_auth---v0301)
- [`komodo_defi_rpc_methods` - `v0.3.0+1`](#komodo_defi_rpc_methods---v0301)
- [`komodo_defi_sdk` - `v0.3.0+1`](#komodo_defi_sdk---v0301)
- [`komodo_defi_types` - `v0.3.0+2`](#komodo_defi_types---v0302)
- [`komodo_symbol_converter` - `v0.3.0+1`](#komodo_symbol_converter---v0301)
- [`komodo_ui` - `v0.3.0+1`](#komodo_ui---v0301)
- [`komodo_wallet_build_transformer` - `v0.3.0+1`](#komodo_wallet_build_transformer---v0301)
- [`komodo_wallet_cli` - `v0.3.0+1`](#komodo_wallet_cli---v0301)

Packages with other changes:

- [`komodo_cex_market_data` - `v0.0.2+1`](#komodo_cex_market_data---v0021)

---

#### `dragon_charts_flutter` - `v0.1.1-dev.2`

- **FEAT**(rpc): trading-related RPCs/types (#191).
- **FEAT**(auth): poll trezor connection status and sign out when disconnected (#126).
- **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

#### `dragon_logs` - `v1.2.1`

- **FIX**(deps): misc deps fixes.
- **FIX**: unify+upgrade Dart/Flutter versions.
- **FEAT**(rpc): trading-related RPCs/types (#191).
- **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).
- **BREAKING** **FEAT**: add dragon_logs package with Wasm-compatible logging.
- **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

#### `komodo_coin_updates` - `v1.0.1`

- **FIX**(deps): misc deps fixes.
- **FIX**: unify+upgrade Dart/Flutter versions.
- **FEAT**(seed): update seed node format (#87).
- **FEAT**: add configurable seed node system with remote fetching (#85).
- **FEAT**: runtime coin updates (#38).
- **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).

#### `komodo_coins` - `v0.3.0+1`

- **REFACTOR**(types): Restructure type packages.
- **PERF**: migrate packages to Dart workspace".
- **PERF**: migrate packages to Dart workspace.
- **FIX**: pub submission errors.
- **FIX**: unify+upgrade Dart/Flutter versions.
- **FIX**(ui): resolve stale asset balance widget.
- **FIX**: remove obsolete coins transformer.
- **FIX**: revert ETH coins config migration transformer.
- **FIX**: breaking tendermint config changes and build transformer not using branch-specific content URL for non-master branches (#55).
- **FEAT**: offline private key export (#160).
- **FEAT**(pubkey): add streamed new address API with Trezor confirmations (#123).
- **FEAT**(ui): adjust error display layout for narrow screens (#114).
- **FEAT**: add configurable seed node system with remote fetching (#85).
- **FEAT**: nft enable RPC and activation params (#39).
- **FEAT**(dev): Install `melos`.
- **FEAT**(hd): HD withdrawal supporting widgets and (WIP) multi-instance example.
- **FEAT**(sdk): Implement remaining SDK withdrawal functionality.
- **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).
- **BREAKING** **FEAT**(sdk): Multi-SDK instance support.

#### `komodo_defi_framework` - `v0.3.0+1`

- **REFACTOR**(types): Restructure type packages.
- **REFACTOR**(komodo_defi_framework): add static, global log verbosity flag (#41).
- **PERF**: migrate packages to Dart workspace.
- **PERF**: migrate packages to Dart workspace".
- **FIX**(rpc-password-generator): update password validation to match KDF password policy (#58).
- **FIX**(komodo-defi-framework): export coin icons (#8).
- **FIX**: resolve bug with dispose logic.
- **FIX**: stop KDF when disposed.
- **FIX**: SIA support.
- **FIX**(kdf_operations): reduce wasm log verbosity in release mode (#11).
- **FIX**: kdf hashes.
- **FIX**(auth_service): hd wallet registration deadlock (#12).
- **FIX**: revert ETH coins config migration transformer.
- **FIX**(kdf): enable p2p in noAuth mode (#86).
- **FIX**(kdf-wasm-ops): response type conversion and migrate to js_interop (#14).
- **FIX**: Fix breaking dependency upgrades.
- **FIX**(debugging): Avoid unnecessary exceptions.
- **FIX**: unify+upgrade Dart/Flutter versions.
- **FIX**(withdrawal-manager): use legacy RPCs for tendermint withdrawals (#57).
- **FIX**: breaking tendermint config changes and build transformer not using branch-specific content URL for non-master branches (#55).
- **FIX**(auth_service): legacy wallet bip39 validation (#18).
- **FIX**(native-auth-ops): remove exceptions from logs in KDF restart function (#45).
- **FIX**(kdf): Rebuild KDF checksums.
- **FIX**(wasm-ops): fix example app login by improving JS call error handling (#185).
- **FIX**(komodo-defi-framework): normalise kdf startup process between native and wasm (#7).
- **FIX**(kdf): Update KDF for HD withdrawal bug.
- **FIX**(bug): Fix JSON list parsing.
- **FIX**(build): update config format.
- **FIX**(native-ops): mobile kdf startup config requires dbdir parameter (#35).
- **FIX**(build_transformer): npm error when building without `package.json` (#3).
- **FIX**(local-exe-ops): local executable startup and registration (#33).
- **FIX**(example): encrypted seed import (#16).
- **FIX**(transaction-history): EVM StackOverflow exception (#30).
- **FEAT**(sdk): Implement remaining SDK withdrawal functionality.
- **FEAT**(build): Add regex support for KDF download.
- **FEAT**(sdk): Balance manager WIP.
- **FEAT**(builds): Add regex pattern support for KDF download.
- **FEAT**(dev): Install `melos`.
- **FEAT**(auth): Add update password feature.
- **FEAT**(auth): Implement new exceptions for update password RPC.
- **FEAT**(withdraw): add ibc source channel parameter (#63).
- **FEAT**(operations): update KDF operations interface and implementations.
- **FEAT**: add configurable seed node system with remote fetching (#85).
- **FEAT**(sdk): add trezor support via RPC and SDK wrappers (#77).
- **FEAT**(ui): adjust error display layout for narrow screens (#114).
- **FEAT**(seed): update seed node format (#87).
- **FEAT**: offline private key export (#160).
- **FEAT**(hd): HD withdrawal supporting widgets and (WIP) multi-instance example.
- **BUG**(windows): Fix incompatibility between Nvidia Windows drivers and Rust.
- **BUG**(wasm): remove validation for legacy methods.
- **BREAKING** **FEAT**(sdk): Multi-SDK instance support.
- **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).

#### `komodo_defi_local_auth` - `v0.3.0+1`

- **REFACTOR**(types): Restructure type packages.
- **PERF**: migrate packages to Dart workspace".
- **PERF**: migrate packages to Dart workspace.
- **FIX**: unify+upgrade Dart/Flutter versions.
- **FIX**(local_auth): ensure kdf running before wallet deletion (#118).
- **FIX**: resolve bug with dispose logic.
- **FIX**(pubkey-strategy): use new PrivateKeyPolicy constructors for checks (#97).
- **FIX**(activation): eth PrivateKeyPolicy enum breaking changes (#96).
- **FIX**(auth): allow custom seeds for legacy wallets (#95).
- **FIX**(withdrawal-manager): use legacy RPCs for tendermint withdrawals (#57).
- **FIX**(auth): Translate KDF errors to auth errors.
- **FIX**(native-auth-ops): remove exceptions from logs in KDF restart function (#45).
- **FIX**(native-ops): mobile kdf startup config requires dbdir parameter (#35).
- **FIX**(local-exe-ops): local executable startup and registration (#33).
- **FIX**(transaction-storage): transaction streaming errors and hanging due to storage error (#28).
- **FIX**(auth_service): legacy wallet bip39 validation (#18).
- **FIX**(auth_service): hd wallet registration deadlock (#12).
- **FEAT**(rpc): trading-related RPCs/types (#191).
- **FEAT**(auth): poll trezor connection status and sign out when disconnected (#126).
- **FEAT**: offline private key export (#160).
- **FEAT**(seed): update seed node format (#87).
- **FEAT**(ui): adjust error display layout for narrow screens (#114).
- **FEAT**(sdk): add trezor support via RPC and SDK wrappers (#77).
- **FEAT**: add configurable seed node system with remote fetching (#85).
- **FEAT**(auth): allow weak password in auth options (#54).
- **FEAT**(auth): Implement new exceptions for update password RPC.
- **FEAT**(auth): Add update password feature.
- **FEAT**(auth): enhance local authentication and secure storage.
- **FEAT**(dev): Install `melos`.
- **FEAT**(sdk): Balance manager WIP.
- **BREAKING** **FEAT**(sdk): Multi-SDK instance support.

#### `komodo_defi_rpc_methods` - `v0.3.0+1`

- **REFACTOR**(tx history): Fix misrepresented fees field.
- **REFACTOR**: improve code quality and documentation.
- **REFACTOR**(types): Restructure type packages.
- **PERF**: migrate packages to Dart workspace".
- **PERF**: migrate packages to Dart workspace.
- **FIX**(rpc): Remove flutter dependency from RPC package.
- **FIX**(activation): eth PrivateKeyPolicy enum breaking changes (#96).
- **FIX**(withdraw): revert temporary IBC channel type changes (#136).
- **FIX**(activation): Fix eth activation parsing exception.
- **FIX**(debugging): Avoid unnecessary exceptions.
- **FEAT**(rpc): support max_connected on activation (#149).
- **FEAT**(pubkey): add streamed new address API with Trezor confirmations (#123).
- **FEAT**(ui): adjust error display layout for narrow screens (#114).
- **FEAT**(rpc): trading-related RPCs/types (#191).
- **FEAT**(sdk): add trezor support via RPC and SDK wrappers (#77).
- **FEAT**(auth): poll trezor connection status and sign out when disconnected (#126).
- **FEAT**(withdraw): add ibc source channel parameter (#63).
- **FEAT**(auth): Implement new exceptions for update password RPC.
- **FEAT**: nft enable RPC and activation params (#39).
- **FEAT**(auth): Add update password feature.
- **FEAT**: enhance balance and market data management in SDK.
- **FEAT**(rpc): implement missing RPCs (#179) (#188).
- **FEAT**(signing): Implement message signing + format.
- **FEAT**(dev): Install `melos`.
- **FEAT**(withdrawals): Implement HD withdrawals.
- **FEAT**: custom token import (#22).
- **FEAT**(sdk): Implement remaining SDK withdrawal functionality.
- **FEAT**: offline private key export (#160).
- **FEAT**(pubkeys): add unbanning support (#161).
- **FEAT**(sdk): Balance manager WIP.
- **FEAT**(fees): integrate fee management (#152).
- **FEAT**(rpc): support max_connected on activation (#149)" (#150).
- **BUG**(tx): Fix broken legacy UTXO tx history.
- **BUG**: fix missing pubkey equality operators.
- **BUG**(tx): Fix and optimise transaction history SDK.
- **BREAKING** **FEAT**(sdk): Multi-SDK instance support.

#### `komodo_defi_sdk` - `v0.3.0+1`

- **REFACTOR**: improve code quality and documentation.
- **REFACTOR**(tx history): Fix misrepresented fees field.
- **REFACTOR**(ui): improve balance text widget implementation.
- **REFACTOR**(sdk): improve transaction history and withdrawal managers.
- **REFACTOR**(sdk): update transaction history manager for new architecture.
- **REFACTOR**(sdk): restructure activation and asset management flow.
- **REFACTOR**(sdk): implement dependency injection with GetIt container.
- **REFACTOR**(types): Restructure type packages.
- **PERF**: migrate packages to Dart workspace.
- **PERF**: migrate packages to Dart workspace".
- **FIX**(activation): track activation status to avoid duplicate activation requests (#80)" (#153).
- **FIX**: unify+upgrade Dart/Flutter versions.
- **FIX**(activation): track activation status to avoid duplicate activation requests (#80).
- **FIX**(withdraw): revert temporary IBC channel type changes (#136).
- **FIX**: resolve bug with dispose logic.
- **FIX**: stop KDF when disposed.
- **FIX**(activation): eth PrivateKeyPolicy enum breaking changes (#96).
- **FIX**(trezor,activation): add PrivateKeyPolicy to AuthOptions (#75).
- **FIX**(withdrawal-manager): use legacy RPCs for tendermint withdrawals (#57).
- **FIX**: breaking tendermint config changes and build transformer not using branch-specific content URL for non-master branches (#55).
- **FIX**(native-auth-ops): remove exceptions from logs in KDF restart function (#45).
- **FIX**(withdraw): update amount when isMaxAmount and show dropdown icon (#44).
- **FIX**(transaction-storage): transaction streaming errors and hanging due to storage error (#28).
- **FIX**(multi-sdk): Fix example app withdrawals SDK instance.
- **FIX**(transaction-history): EVM StackOverflow exception (#30).
- **FIX**(example): Fix registration form regression.
- **FIX**(local-exe-ops): local executable startup and registration (#33).
- **FIX**(asset-manager): add missing ticker index initialization (#24).
- **FIX**(example): encrypted seed import (#16).
- **FIX**(assets): Add ticker-safe asset lookup.
- **FIX**(ui): resolve stale asset balance widget.
- **FIX**(native-ops): mobile kdf startup config requires dbdir parameter (#35).
- **FIX**(auth_service): hd wallet registration deadlock (#12).
- **FIX**(market-data-price): try fetch current price from komodo price repository first before cex repository (#167).
- **FIX**(auth_service): legacy wallet bip39 validation (#18).
- **FIX**(transaction-history): non-hd transaction history support (#25).
- **FEAT**(KDF): Make provision for HD mode signing.
- **FEAT**(auth): Add update password feature.
- **FEAT**: enhance balance and market data management in SDK.
- **FEAT**: add configurable seed node system with remote fetching (#85).
- **FEAT**(ui): improve asset list and authentication UI.
- **FEAT**(error-handling): enhance balance and address loading error states.
- **FEAT**(auth): poll trezor connection status and sign out when disconnected (#126).
- **FEAT**(transactions): add activations and withdrawal priority features.
- **FEAT**(ui): update asset components and SDK integrations.
- **FEAT**(market-data): add support for multiple market data providers (#145).
- **FEAT**(pubkey-manager): add pubkey watch function similar to balance watch (#178).
- **FEAT**(withdrawals): Implement HD withdrawals.
- **FEAT**(sdk): redesign balance manager with improved API and reliability.
- **FEAT**: nft enable RPC and activation params (#39).
- **FEAT**(signing): Implement message signing + format.
- **FEAT**(dev): Install `melos`.
- **FEAT**(auth): Implement new exceptions for update password RPC.
- **FEAT**(ui): Address and fee UI enhancements + formatting.
- **FEAT**(withdraw): add ibc source channel parameter (#63).
- **FEAT**(rpc): trading-related RPCs/types (#191).
- **FEAT**(ui): add AssetLogo widget (#78).
- **FEAT**(sdk): add trezor support via RPC and SDK wrappers (#77).
- **FEAT**(hd): HD withdrawal supporting widgets and (WIP) multi-instance example.
- **FEAT**(asset): add message signing support flag (#105).
- **FEAT**: custom token import (#22).
- **FEAT**(ui): adjust error display layout for narrow screens (#114).
- **FEAT**(ui): add helper constructors for AssetLogo from legacy ticker and AssetId (#109).
- **FEAT**(pubkey): add streamed new address API with Trezor confirmations (#123).
- **FEAT**: protect SDK after disposal (#116).
- **FEAT**(asset): Add legacy asset transition helpers.
- **FEAT**(sdk): Implement remaining SDK withdrawal functionality.
- **FEAT**(HD): Implement GUI utility for asset status.
- **FEAT**: offline private key export (#160).
- **FEAT**(activation): disable tx history when using external strategy (#151).
- **FEAT**(pubkeys): add unbanning support.
- **FEAT**(fees): integrate fee management (#152).
- **FEAT**(sdk): Balance manager WIP.
- **BUG**(assets): Fix missing export for legacy extension.
- **BUG**(tx): Fix broken legacy UTXO tx history.
- **BUG**(auth): Fix registration failing on Windows and Windows web builds (#34).
- **BUG**(tx): Fix and optimise transaction history SDK.
- **BREAKING** **FEAT**(sdk): Multi-SDK instance support.
- **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).
- **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

#### `komodo_defi_types` - `v0.3.0+2`

- **REFACTOR**(tx history): Fix misrepresented fees field.
- **REFACTOR**(types): Restructure type packages.
- **PERF**: migrate packages to Dart workspace".
- **PERF**: migrate packages to Dart workspace.
- **FIX**(debugging): Avoid unnecessary exceptions.
- **FIX**(deps): resolve deps error.
- **FIX**(wasm-ops): fix example app login by improving JS call error handling (#185).
- **FIX**(ui): resolve stale asset balance widget.
- **FIX**(types): export missing RPC types.
- **FIX**(activation): Fix eth activation parsing exception.
- **FIX**(withdraw): revert temporary IBC channel type changes (#136).
- **FIX**: SIA support.
- **FIX**(pubkey-strategy): use new PrivateKeyPolicy constructors for checks (#97).
- **FIX**(activation): eth PrivateKeyPolicy enum breaking changes (#96).
- **FIX**: pub submission errors.
- **FIX**: Add pubkey property needed for GUI.
- **FIX**(trezor,activation): add PrivateKeyPolicy to AuthOptions (#75).
- **FIX**: Fix breaking dependency upgrades.
- **FIX**(fee-info): update tendermint, erc20, and qrc20 `fee_details` response format (#60).
- **FIX**(rpc-password-generator): update password validation to match KDF password policy (#58).
- **FIX**(withdrawal-manager): use legacy RPCs for tendermint withdrawals (#57).
- **FIX**: breaking tendermint config changes and build transformer not using branch-specific content URL for non-master branches (#55).
- **FIX**(native-auth-ops): remove exceptions from logs in KDF restart function (#45).
- **FIX**(types): Fix Sub-class naming.
- **FIX**(bug): Fix JSON list parsing.
- **FIX**(local-exe-ops): local executable startup and registration (#33).
- **FIX**(example): Fix registration form regression.
- **FIX**(transaction-storage): transaction streaming errors and hanging due to storage error (#28).
- **FIX**(types): Make types index private.
- **FIX**(example): encrypted seed import (#16).
- **FEAT**(sdk): add trezor support via RPC and SDK wrappers (#77).
- **FEAT**(auth): Implement new exceptions for update password RPC.
- **FEAT**(signing): Add message signing prefix to models.
- **FEAT**(auth): poll trezor connection status and sign out when disconnected (#126).
- **FEAT**(KDF): Make provision for HD mode signing.
- **FEAT**(market-data): add support for multiple market data providers (#145).
- **FEAT**: enhance balance and market data management in SDK.
- **FEAT**(types): add new models and utility classes for reactive data handling.
- **FEAT**(dev): Install `melos`.
- **FEAT**(sdk): Balance manager WIP.
- **FEAT**(rpc): trading-related RPCs/types (#191).
- **FEAT**(withdrawals): Implement HD withdrawals.
- **FEAT**: add configurable seed node system with remote fetching (#85).
- **FEAT**(hd): HD withdrawal supporting widgets and (WIP) multi-instance example.
- **FEAT**(seed): update seed node format (#87).
- **FEAT**: custom token import (#22).
- **FEAT**(pubkey): add streamed new address API with Trezor confirmations (#123).
- **FEAT**(sdk): Implement remaining SDK withdrawal functionality.
- **FEAT**(types): Iterate on withdrawal-related types.
- **FEAT**(withdraw): add ibc source channel parameter (#63).
- **FEAT**(ui): add helper constructors for AssetLogo from legacy ticker and AssetId (#109).
- **FEAT**: offline private key export (#160).
- **FEAT**(ui): adjust error display layout for narrow screens (#114).
- **FEAT**(asset): add message signing support flag (#105).
- **FEAT**(HD): Implement GUI utility for asset status.
- **FEAT**(auth): allow weak password in auth options (#54).
- **FEAT**(fees): integrate fee management (#152).
- **BUG**(import): Fix incorrect encrypted seed parsing.
- **BUG**: fix missing pubkey equality operators.
- **BUG**(auth): Fix registration failing on Windows and Windows web builds (#34).
- **BREAKING** **FEAT**(sdk): Multi-SDK instance support.
- **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).

#### `komodo_symbol_converter` - `v0.3.0+1`

- **PERF**: migrate packages to Dart workspace".
- **PERF**: migrate packages to Dart workspace.
- **FIX**: unify+upgrade Dart/Flutter versions.
- **FEAT**: offline private key export (#160).
- **BREAKING** **FEAT**(sdk): Multi-SDK instance support.

#### `komodo_ui` - `v0.3.0+1`

- **REFACTOR**: improve code quality and documentation.
- **PERF**: migrate packages to Dart workspace.
- **PERF**: migrate packages to Dart workspace".
- **FIX**(ui): make Divided button min width.
- **FIX**: Fix breaking dependency upgrades.
- **FIX**(fee-info): update tendermint, erc20, and qrc20 `fee_details` response format (#60).
- **FIX**: unify+upgrade Dart/Flutter versions.
- **FIX**(ui): convert error display to stateful widget to toggle detailed error message (#46).
- **FIX**(withdraw): update amount when isMaxAmount and show dropdown icon (#44).
- **FEAT**(ui): Address and fee UI enhancements + formatting.
- **FEAT**(ui): allow customizing SourceAddressField header (#135).
- **FEAT**: offline private key export (#160).
- **FEAT**(ui): add helper constructors for AssetLogo from legacy ticker and AssetId (#109).
- **FEAT**(ui): adjust error display layout for narrow screens (#114).
- **FEAT**(KDF): Make provision for HD mode signing.
- **FEAT**(source-address-field): add show balance toggle (#43).
- **FEAT**: enhance balance and market data management in SDK.
- **FEAT**(ui): add AssetLogo widget (#78).
- **FEAT**(transactions): add activations and withdrawal priority features.
- **FEAT**(ui): update asset components and SDK integrations.
- **FEAT**(ui): enhance withdrawal form components with better validation and feedback.
- **FEAT**(ui): add hero support for coin icons (#159).
- **FEAT**(signing): Implement message signing + format.
- **FEAT**(dev): Install `melos`.
- **FEAT**(sdk): Balance manager WIP.
- **FEAT**(hd): HD withdrawal supporting widgets and (WIP) multi-instance example.
- **FEAT**: custom token import (#22).
- **FEAT**(ui): Migrate withdrawal-related widgets from KW.
- **FEAT**(sdk): Implement remaining SDK withdrawal functionality.
- **FEAT**(UI): Migrate QR code scanner from KW.
- **FEAT**(ui): redesign core input components with improved UX.
- **DOCS**(ui): Document UI package structure.
- **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).
- **BREAKING** **FEAT**(sdk): Multi-SDK instance support.

#### `komodo_wallet_build_transformer` - `v0.3.0+1`

- **REFACTOR**(build_transformer): move api release download and extraction to separate files (#23).
- **PERF**: migrate packages to Dart workspace".
- **PERF**: migrate packages to Dart workspace.
- **FIX**: unify+upgrade Dart/Flutter versions.
- **FIX**: breaking tendermint config changes and build transformer not using branch-specific content URL for non-master branches (#55).
- **FIX**(build-transformer): ios xcode errors (#6).
- **FIX**(build_transformer): npm error when building without `package.json` (#3).
- **FEAT**: offline private key export (#160).
- **FEAT**(wallet_build_transformer): add flexible CDN support (#144).
- **FEAT**(ui): adjust error display layout for narrow screens (#114).
- **FEAT**: enhance balance and market data management in SDK.
- **FEAT**(dev): Install `melos`.
- **FEAT**(hd): HD withdrawal supporting widgets and (WIP) multi-instance example.
- **FEAT**(build): Add regex support for KDF download.
- **FEAT**(builds): Add regex pattern support for KDF download.
- **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).
- **BREAKING** **FEAT**(sdk): Multi-SDK instance support.
- **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

#### `komodo_wallet_cli` - `v0.3.0+1`

- **PERF**: migrate packages to Dart workspace".
- **PERF**: migrate packages to Dart workspace.
- **FIX**(pub): add non-generic description.
- **FIX**: unify+upgrade Dart/Flutter versions.
- **FIX**(cli): Fix encoding for KDF config updater script.
- **FEAT**: offline private key export (#160).
- **FEAT**(dev): Install `melos`.
- **BUG**(auth): Fix registration failing on Windows and Windows web builds (#34).
- **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).
- **BREAKING** **FEAT**(sdk): Multi-SDK instance support.
- **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

#### `komodo_cex_market_data` - `v0.0.2+1`

- **FEAT**(market-data): add support for multiple market data providers (#145).
- **FEAT**: offline private key export (#160).
- **FEAT**: migrate komodo_cex_market_data from komod-wallet (#37).
