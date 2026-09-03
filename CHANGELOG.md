# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2026-09-01

### Changes

---

Packages with breaking changes:

 - [`komodo_defi_sdk` - `v0.7.0`](#komodo_defi_sdk---v070)
 - [`komodo_defi_types` - `v0.5.0`](#komodo_defi_types---v050)
 - [`komodo_defi_rpc_methods` - `v0.6.0`](#komodo_defi_rpc_methods---v060)
 - [`komodo_defi_framework` - `v0.5.0`](#komodo_defi_framework---v050)
 - [`komodo_wallet_build_transformer` - `v0.5.0`](#komodo_wallet_build_transformer---v050)
 - [`komodo_wallet_cli` - `v0.6.0`](#komodo_wallet_cli---v060)
 - [`komodo_coins` - `v0.4.0`](#komodo_coins---v040)

Packages with other changes:

 - [`komodo_defi_local_auth` - `v0.5.0`](#komodo_defi_local_auth---v050)
 - [`komodo_coin_updates` - `v2.1.0`](#komodo_coin_updates---v210)
 - [`komodo_ui` - `v0.3.3`](#komodo_ui---v033)
 - [`komodo_legacy_wallet_migration` - `v0.1.1`](#komodo_legacy_wallet_migration---v011)
 - [`komodo_cex_market_data` - `v0.1.0+2`](#komodo_cex_market_data---v0102)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `komodo_cex_market_data` - `v0.1.0+2`

---

#### `komodo_defi_sdk` - `v0.7.0`

> Note: This release has breaking GasFree activation and withdrawal behavior.

 - **BREAKING** **FEAT**(gasfree): derive token enrollment only from activated
   TRC20 `gasless.enabled` configuration and require an authoritative
   account-status check before custody balance or sends become available.
   Applications may amend normalized asset configuration before SDK parsing
   through `assetConfigTransform`.
 - **BREAKING** **FEAT**(gasfree): configure the documented
   `tron_gasless_provider` and per-token `gasless` fields during ordinary TRON
   activation. Remove runtime `gasless::configure`, its restart fallback, and
   the legacy V0/V1/bound compatibility contracts.
 - **BREAKING** **FEAT**(gasfree): adopt the required four-state account status
   contract (`available`, `pending_transfer`, `token_unsupported`, and
   `provider_unreachable`) with endpoint-typed provider, custody-address, and
   token-decimal errors.
 - **SECURITY**(gasfree): persist a wallet-scoped local `journalId` before
   submission, never serialize it to KDF, retain unknown outcomes without
   resubmitting, and migrate accepted records with a trace ID into trace
   recovery.
 - **FEAT**(gasfree): subscribe to `GASLESS_TRACE:<coin>` before submission,
   persist KDF's accepted `trace_id`, reconcile it once immediately, and follow
   matching success/error stream events. Restart and disconnect recovery use a
   one-shot `gasless::trace_status` request.
 - **BREAKING** **FIX**(gasfree): serialize only KDF's documented withdrawal and
   relay fields, report the actual Standard/GasFree submission rail, and obtain
   final fee and finality from trace status rather than preview metadata.
 - **FIX**(gasfree): treat account-status `max_withdrawable` as an advisory
   status value and delegate maximum sends to KDF with `max: true` and no
   amount.
 - **FIX**(gasfree): retain custody/recovery access during provider outages,
   preserve KDF-compatible Iguana, software-HD, and hardware-HD activation
   identities, preserve cross-page address perspectives, and expose final fee
   plus confirmation metadata without enabling resubmission.
 - **FIX**(pubkeys): migrate legacy address metadata conservatively so funded
   and previously used Standard addresses remain visible.
 - **FIX**(gasfree): keep KDF's fresh custody total distinct from provider
   spendability and Standard balances; remove external custody-balance and
   finality readers.
 - **FEAT**(activation): expose per-asset activation state through
   `activationStates`, `watchActivationStates` and `watchActivationStateOf`,
   and reach a terminal state on every path - a progress stream that never
   emits and never closes no longer strands the caller past its deadline.
 - **FEAT**(transaction-history): persist transaction history to disk. A coin's
   history is served from local storage on a cold start and the network walk
   that follows is a refresh rather than a first fetch. On by default, with
   unbounded retention; `KomodoDefiSdkConfig` gates it.
 - **FEAT**(transaction-history): add a Blockscout strategy so GLEEC and GRC-20
   report history instead of returning an empty list.
 - **FEAT**(balances): paint balances from local storage before activation
   completes, and keep the balance watcher alive across a transport blip or a
   degraded wallet identity rather than emitting nothing at all.
 - **PERF**(pubkeys): scale the HD address gap scan through `HdGapLimit` -
   3 addresses, or 1 on a newly generated wallet's first sign-in, against KDF's
   default of 20 - and skip the redundant post-activation scan. Hardware
   wallets keep the full gap of 20. Measured single-coin HD activation falls
   from 46.9s to roughly 13.1s.
 - **PERF**(auth): cut the identity RPCs issued on every sign-in and stop
   activation precaching from blocking first paint.
 - **FIX**(wallets): purge wallet-scoped caches - derived addresses, activation
   config, enabled assets, transaction history - inside `deleteWallet` via the
   new `KomodoDefiAuth.onWalletDeletion` hook, so deleting and immediately
   recreating a wallet cannot race a still-running purge.
 - **FIX**(balances): read cached public keys only after the undelivered
   wallet-switch check, so a balance cannot be painted from the previous wallet.
 - **FIX**(gasfree): discard an untraced pending transfer under a single lock,
   so a reservation belonging to an accepted transfer can no longer be stripped
   between the lookup and the removal.
 - **FIX**(deps): declare `meta`, which `activation_strategy_base.dart`
   imports, and the `flutter_test` and `plugin_platform_interface` dev
   dependencies the tests import. They resolved only through the workspace, so
   `dart pub publish` rejected the package.
 - **FIX**(deps): raise the `flutter_secure_storage` lower bound off the
   `10.0.0-beta.4` pre-release to `^10.0.0`. It already resolved to a stable
   10.x, and pub warns when a stable release depends on a pre-release.

#### `komodo_defi_types` - `v0.5.0`

> Note: This release has breaking GasFree withdrawal interfaces.

 - **BREAKING** **FEAT**(gasfree): align provider activation, fee preview,
   signed relay, submission, and receipt models with the final KDF contract.
 - **BREAKING** **FIX**(gasfree): obtain accepted trace identity and final fee
   from submission/trace status instead of preview or provider echoes.
 - **BREAKING** **FIX**(withdraw): enforce mutually exclusive explicit-amount
   and maximum request modes, omitting `amount` whenever `max` is true.
 - **SECURITY**(gasfree): persist only wallet-scoped journal and trace recovery
   data, never signed authorization material or provider credentials.
 - **FEAT**(gasfree): rename the local reservation identity to `journalId`;
   migrate trace-backed records and keep trace-less records outcome-unknown.
 - **BREAKING** **REFACTOR**(activation): remove `BatchActivationProgress`.
   Multi-asset progress is now tracked by the SDK's activation coordinator and
   surfaced as `AssetActivationState`; `ActivationProgress` itself is unchanged.
 - **FEAT**(activation): add `AssetActivationState` and `AssetActivationStatus`
   for per-asset activation state with a guaranteed terminal value.
 - **FEAT**(pubkeys): add `HdGapLimit`, which resolves the HD address gap to
   scan - 3 by default, 1 on a newly generated wallet's first sign-in, and the
   full 20 for hardware wallets.
 - **FIX**(transactions): make transaction identity and ordering stable enough
   to persist and re-read, so a stored history round-trips without duplicates.
 - **SECURITY**(logging): replace the log-censoring key list with a set that
   also covers authorization headers, bearer/API tokens, cookies and GasFree
   authorization material, and redact to `<redacted>` rather than a run of
   asterisks that leaked the value's length.
 - **FIX**(deps): declare the `flutter_test` dev dependency that
   `sia_protocol_test.dart` imports.
 - **CHORE**(analysis): drop two null assertions the analyzer proves are
   no-ops, which `dart pub publish` reports as warnings.

#### `komodo_defi_rpc_methods` - `v0.6.0`

> Note: This release has breaking GasFree relay response interfaces.

 - **BREAKING** **FEAT**(gasfree): adopt the final activation, four-state account
   status, signed relay, submission, and trace settlement contracts.
 - **FEAT**(gasfree): add typed `stream::gasless_trace::enable` success and
   error events for coin-scoped trace reconciliation.
 - **SECURITY**(gasfree): remove request/fingerprint/expected-authorization
   compatibility fields and reject undocumented relay generations.
 - **FIX**(gasfree): generate endpoint-scoped account, withdrawal, trace, and
   streaming exceptions from the pinned KDF Rust error enums.
 - **FIX**(gasfree): serialize maximum withdrawals with `max: true` and no
   `amount`, and serialize only documented GasFree withdrawal options.
 - **FEAT**(activation): send the HD address `gap_limit` on the wire for the
   activation methods that accept it, so callers can scan fewer addresses than
   KDF's default of 20.
 - **FEAT**(activation): add WebSocket expansion of EVM node entries, gated off
   on both web and native for this release: KDF `main` panics on a `wss://`
   reply that lands after the caller's timeout, so only HTTP nodes are sent.
 - **FIX**(requests): encode request bodies through a single encodable path so
   nested parameter objects serialize consistently.

#### `komodo_defi_framework` - `v0.5.0`

> Note: This release rolls the bundled KDF to the `3.1.0-beta` line.

 - **BREAKING** **BUILD**(kdf): pin the bundled artefact to KDF `main`
   `f3efd2ca10420f2982fa127dde84dcc17891f577` (`3.1.0-beta_f3efd2c`) for all
   seven native/WASM targets. This reprices EVM swap gas under the
   Amsterdam/Bogota fork rules and is visible in fee estimates.
 - **BREAKING** **BUILD**(kdf): require a full 40-character commit hash and
   declare `required_platforms`, so a partial or missing platform fails the
   build instead of shipping a stale artefact.
 - **SECURITY**(build): restrict bundled KDF sources to the official Devbuilds
   and Nebula mirrors. Keep `devbuilds.gleec.com` first for `main/` builds.
 - **FEAT**(streaming): add typed `GASLESS_TRACE` events and rework the web and
   IO event-stream transports around a single service lifecycle.
 - **FEAT**(config): allow an `IKdfOperations` implementation to be injected,
   and export `KdfExecutableFinder` and `KdfOperationsLocalExecutable` so a test
   harness can drive the real binary through the framework's own lifecycle.
 - **FIX**(android): align native LOAD segments to 16 KB pages (#355).
 - **SECURITY**(logging): stop logging full activation parameters, and suppress
   verbose RPC logging for GasFree requests, whose bodies carry provider
   credentials and signed authorization material.
 - **CHORE**(build): drop the committed `CMakeCache.txt`, `Makefile` and
   `cmake_install.cmake`. The cache recorded absolute paths from the machine
   that generated it, and CMake refuses to configure a directory whose cache
   came from elsewhere (#362).

#### `komodo_wallet_build_transformer` - `v0.5.0`

 - **BREAKING** **FEAT**(build): write and verify artefact provenance markers
   next to each extracted KDF artefact. A marker is authoritative only when it
   identifies the pinned commit, the downloaded archive, the extracted core
   artefact and the complete platform runtime set; legacy partial markers fail
   closed and force a re-fetch.
 - **FEAT**(build): support `require_full_commit_hash` and `required_platforms`
   in the API build config, so an incomplete pin fails the build.
 - **FIX**(build): discard the Rust proc-macro DLLs that KDF's Windows archive
   ships, which the owned-runtime guard otherwise rejected - failing every
   `flutter test` that runs the transformer.
 - **FIX**(assets): decide whether a platform asset needs recopying by
   comparing SHA-256 content rather than modification time, which a checkout or
   a restored cache can reorder.

#### `komodo_wallet_cli` - `v0.6.0`

 - **BREAKING** **FEAT**(update-api-config): default to the `main` branch of the
   private `GLEECBTC/kdf-internal` repository. `--source github` against it now
   needs a `--token` with read access.
 - **FEAT**(update-api-config): resolve short commit SHAs remotely and write
   only a full 40-character lowercase SHA; add `--strict` to require
   exact commit-matching artefacts, `--mirror-url` to pin the mirror, and a
   platform update scope that only lets `--platform all` change the pinned
   commit.
 - **FIX**(update-api-config): match a mirror listing's links by the artefact
   filename contract applied to the href's basename, so bare filenames,
   relative paths and absolute URLs all resolve alike.
 - **FIX**(update-api-config): keep an independently trusted checksum set
   unchanged when the pinned commit has not moved, rather than replacing it
   with whatever the current download calculated.

#### `komodo_defi_local_auth` - `v0.5.0`

 - **FEAT**(auth): add `KomodoDefiAuth.onWalletDeletion`, an awaited hook that
   runs inside `deleteWallet` after KDF and secure storage have forgotten the
   wallet but before the call returns. Wallet-scoped cache owners register here
   so deleting and immediately recreating the same wallet cannot race a
   still-running purge; the `walletDeletions` stream remains for passive
   observers.
 - **FIX**(auth): stop treating a transient transport failure as an
   authentication failure - a brief network drop no longer ends the session.
 - **FIX**(auth): resolve the deleted wallet's identity before deletion, since
   it cannot be recovered afterwards.
 - **FIX**(trezor): surface the device's own message in `TrezorException`
   instead of `GeneralErrorResponse.toString()`, which is deliberately reduced
   to its `error_type` to keep request payloads out of logs and so read as
   `GeneralErrorResponse(errorType: ...)` to the user. `error_data` is still
   never included.
 - **FIX**(storage): open Android secure storage with `resetOnError: false`, so
   a read failure surfaces instead of silently clearing stored credentials.
 - **FIX**(deps): raise the `flutter_secure_storage` lower bound off the
   `10.0.0-beta.4` pre-release to `^10.0.0`. It already resolved to a stable
   10.x, and pub warns when a stable release depends on a pre-release.

#### `komodo_coins` - `v0.4.0`

 - **BREAKING** **FIX**(assets): return `filteredAssets` as an ordered snapshot
   keyed by `AssetId` equality rather than the live `SplayTreeMap` behind the
   filter cache. The tree's comparator orders on `AssetId.toString()`, which
   omits the chain id and includes the parent, so lookups on it missed ids that
   were `==` to a stored key - every child-token id parsed without known
   parents, as `Transaction.fromJson` does. The returned map is now a stable,
   unmodifiable snapshot, so it is also safe to iterate across an await.
 - **PERF**(assets): memoise the filtered snapshot per strategy, invalidating it
   with the underlying cache. `filteredAssets` is on every `available` read.
 - **FIX**(tests): correct long-stale expectations - a `type: 'UTXO'` fixture is
   tagged `CoinSubClass.utxo`, not `smartChain`, since #244, and a custom token
   colliding with a bundled asset takes over its slot rather than being stored
   beside it under a renamed id.

#### `komodo_coin_updates` - `v2.1.0`

 - **FEAT**(config): add `CoinConfigTransformer.additionalTransforms`, applied
   after the built-in normalization set so an application can amend normalized
   asset configuration without replacing SDK defaults.
 - **FEAT**(tron): add `TronQuickNodeTransform`, keeping mainnet TRX and TRC20
   assets pointed at the Gleec proxy while preserving upstream fallback nodes.
 - **FIX**(custom-tokens): stop rejecting a re-store of an existing custom token
   as a contract collision. Assets read back through `AssetAdapter` are rebuilt
   without known parent ids, so the stored copy never carries a `parentId`;
   comparing that absence against a live parsed parent made every `upsert` and
   `addCustomTokenIfNotExists` on an existing token throw. Parents are now only
   compared when both sides carry one - a differing contract address still
   conflicts.

#### `komodo_ui` - `v0.3.3`

 - **FEAT**(withdraw): render GasFree fees - provider, transfer fee and optional
   account-activation fee - in `FeeInfoDisplay`.
 - **FEAT**(withdraw): parameterise the withdrawal amount field's labels so host
   applications can localise them, and rework its max/send-maximum controls to
   stay usable at large text scales.
 - **FIX**(addresses): correct address selection and formatting in the address
   select input and recipient/source fields.
 - **CHORE**(analysis): drop two null assertions the analyzer proves are
   no-ops, which `dart pub publish` reports as warnings.

#### `komodo_legacy_wallet_migration` - `v0.1.1`

 - **FIX**(android): open legacy encrypted shared preferences with
   `resetOnError: false`, so a read failure surfaces instead of silently
   clearing the legacy wallet data the migration exists to read.
 - **FIX**(deps): raise the `flutter_secure_storage` lower bound off the
   `10.0.0-beta.4` pre-release to `^10.0.0`. It already resolved to a stable
   10.x, and pub warns when a stable release depends on a pre-release.

#### `komodo_cex_market_data` - `v0.1.0+2`

 - **FIX**(deps): declare `collection`, which `id_resolution_strategy.dart`
   imports. It resolved only through the workspace, so `dart pub publish`
   rejected the package.
 - Update a dependency to the latest release.

## 2026-05-02

### Changes

---

Packages with breaking changes:

 - [`komodo_defi_rpc_methods` - `v0.5.0`](#komodo_defi_rpc_methods---v050)
 - [`komodo_defi_sdk` - `v0.6.0`](#komodo_defi_sdk---v060)

Packages with other changes:

 - [`komodo_cex_market_data` - `v0.1.0+1`](#komodo_cex_market_data---v0101)
 - [`komodo_defi_framework` - `v0.4.1`](#komodo_defi_framework---v041)
 - [`komodo_defi_local_auth` - `v0.4.1`](#komodo_defi_local_auth---v041)
 - [`komodo_defi_types` - `v0.4.1`](#komodo_defi_types---v041)
 - [`komodo_legacy_wallet_migration` - `v0.1.0`](#komodo_legacy_wallet_migration---v010)
 - [`komodo_ui` - `v0.3.2`](#komodo_ui---v032)
 - [`komodo_wallet_build_transformer` - `v0.4.2`](#komodo_wallet_build_transformer---v042)
 - [`komodo_wallet_cli` - `v0.5.1`](#komodo_wallet_cli---v051)
 - [`komodo_coins` - `v0.3.2+1`](#komodo_coins---v0321)
 - [`komodo_coin_updates` - `v2.0.1`](#komodo_coin_updates---v201)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `komodo_coins` - `v0.3.2+1`
 - `komodo_coin_updates` - `v2.0.1`

---

#### `komodo_defi_rpc_methods` - `v0.5.0`

 - **FIX**(errors): preserve RPC method hints when parsing ambiguous KDF error responses (#342).
 - **FIX**(models): accept numeric JSON values encoded as either `int` or `num` across RPC models (#336).
 - **FEAT**(auth): add the RPC request and activation parameter support needed by legacy wallet migration.
 - **BREAKING** **FEAT**(sia): move SIA withdrawal handling onto hardened SIA-specific RPC models and namespace methods (#343).

#### `komodo_defi_sdk` - `v0.6.0`

 - **FIX**(activation): restore coordinated TRX activation and market-data lookup (#340).
 - **FIX**(explorers): support TRON explorer URL templates in SDK transaction flows (#338).
 - **FIX**(market-data): keep last-known spot prices available while rotating cache snapshots (#335).
 - **FEAT**(migration): add SDK integration for legacy wallet discovery, verification, import, and cleanup.
 - **FEAT**(balances): add balance recovery mode and richer fee information plumbing (#341).
 - **FEAT**(transaction-history): add a Tronscan strategy with address, cursor, and fixed-scale amount codecs (#339).
 - **BREAKING** **FEAT**(sia): route SIA activation and withdrawals through the hardened SIA strategy and RPC namespace (#343).

#### `komodo_legacy_wallet_migration` - `v0.1.0`

 - **FEAT**(migration): add legacy wallet discovery, metadata parsing, password verification, import, and cleanup utilities.
 - **FIX**(migration): use a PointyCastle-based Argon2 verifier for WASM compatibility.
 - **FIX**(migration): guard unsupported platforms and wait for KDF RPC readiness before migration work.

#### `komodo_cex_market_data` - `v0.1.0+1`

 - **FIX**(coingecko): add a failure cooldown to avoid repeated failing requests (#346).
 - **FIX**(tron): restore TRX market-data ID resolution and repository fallback behaviour (#340).
 - **FIX**(models): accept numeric API values encoded as either `int` or `num` (#336).

#### `komodo_defi_framework` - `v0.4.1`

 - **CHORE**(build): update bundled KDF to staging commit `52ba4f9` and use the TRON coins source for release builds.
 - **FIX**(config): carry TRON explorer URL support through bundled build configuration (#338).
 - **FIX**(web): harden numeric JS interop parsing for KDF responses (#336).
 - **FEAT**(migration): expose the framework hooks needed for legacy wallet migration.
 - **FEAT**(build): align build configuration with the balance recovery and fee-info release inputs (#341).

#### `komodo_defi_local_auth` - `v0.4.1`

 - **FIX**(auth,migration): wait for KDF RPC readiness and guard unsupported platforms during migration.
 - **FEAT**(migration): add local-auth integration for legacy wallet verification and import flows.

#### `komodo_defi_types` - `v0.4.1`

 - **FIX**(tron): support TRON explorer URL templates and correct TRC20 badge classification (#338, #344).
 - **FIX**(models): accept numeric JSON values encoded as either `int` or `num` (#336).
 - **FEAT**(migration): add auth error and wallet metadata types used by legacy wallet migration.
 - **FEAT**(fees): expose richer fee information for balance recovery flows (#341).
 - **FEAT**(transaction-history): add strategy metadata needed by the Tronscan history provider (#339).

#### `komodo_ui` - `v0.3.2`

 - **FIX**(asset-icons): avoid duplicate icon precache requests (#345).
 - **FIX**(asset-icons): show the correct TRC20 chain badge (#344).
 - **FEAT**(fees): display richer fee information from SDK balance recovery flows (#341).

#### `komodo_wallet_build_transformer` - `v0.4.2`

 - **FIX**(github): accept numeric GitHub API values encoded as either `int` or `num` (#336).
 - **FEAT**(build): support the build inputs needed by balance recovery and fee-info updates (#341).

#### `komodo_wallet_cli` - `v0.5.1`

 - **FEAT**(build): update API config tooling for the balance recovery and fee-info release inputs (#341).


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
 - **FIX**(sdk): close balance and pubkey subscriptions on auth state changes (#232).
 - **FIX**(binance): use the per-coin supported quote currency list instead of the global cache (#224).
 - **FEAT**(cex-market-data): add CoinPaprika API provider as a fallback option (#215).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_coin_updates` - `v2.0.0`

 - **PERF**(logs): reduce market metrics log verbosity and duplication (#223).
 - **FIX**(startup): handle 6133 seed fallback and invalid configs (#318).
 - **FIX**(config): loosen types for `needsTransform` checks and fix `lightwalletservers` typing.
 - **FIX**(config): add SSL-only transforms for native platforms.
 - **FIX**(sdk): close balance and pubkey subscriptions on auth state changes (#232).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**(coins): add TRON/TRC20-aware config and storage handling (#316).
 - **FEAT**(sdk): add token safety and fee support helpers for custom-token flows (#319).
 - **FEAT**(message-signing): add `AddressPath` support and refactor Asset/PubkeyInfo usage (#231).
 - **FEAT**(coin-config): add custom token support to coin config manager (#225).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_defi_framework` - `v0.4.0`

 - **REFACTOR**(macos): streamline KDF binary placement and update the signing flow (#247).
 - **CHORE**(framework): upgrade bundled KDF and coins references for the 3.0.0-beta preview and latest coins roll (#317, #331).
 - **FIX**(streaming): gate enable_* calls on a real SSE first-byte event (#332).
 - **FIX**(auth): add mutex-protected atomic metadata updates (#328).
 - **FIX**(startup): handle 6133 seed fallback and invalid configs (#318).
 - **FIX**(web): improve WASM JS interop bindings (#315).
 - **FIX**(web): complete WASM-safe SDK interop cleanup (#313).
 - **FIX**(build): reformat build config and normalize API source URLs (#301).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FIX**(auth): store bip39 compatibility regardless of wallet type (#216).
 - **FIX**(build): rename the transformer marker to `assets/transformer_invoker.txt`, update pubspec/README references, and remove the old dotfile exception.
 - **FEAT**(sdk): add token safety and fee support helpers (#319).
 - **FEAT**(sdk): add typed error plumbing, trading-stream foundations, and activation refactoring (#312).
 - **FEAT**: add support for ETH-BASE and derived assets (#254).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_defi_local_auth` - `v0.4.0`

 - **FIX**(test): add missing `updateActiveUserMetadataKey` coverage to the fake auth service (#330).
 - **FIX**(auth): add mutex-protected atomic metadata updates (#328).
 - **FIX**(auth): store bip39 compatibility regardless of wallet type (#216).
 - **FEAT**(sdk): add typed error handling, trading streams, and activation refactoring foundations (#312).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_defi_rpc_methods` - `v0.4.0`

 - **FIX**(sdk): close balance and pubkey subscriptions on auth state changes (#232).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**(errors): add generated MM2 exception models and richer task error details (#312).
 - **FEAT**(wallet): extend HD wallet, password change, delete-wallet, and Trezor RPC shapes (#312).
 - **FEAT**(coins): add TRON/TRC20 activation parameters and withdrawal request support (#316).
 - **FEAT**(message-signing): add `AddressPath` type and refactor to use Asset/PubkeyInfo (#231).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_defi_sdk` - `v0.5.0`

 - **FIX**(streaming): gate enable_* calls on a real SSE first-byte event (#332).
 - **FIX**(withdrawals): remove the duplicate `executeWithdrawal` path (#322).
 - **FIX**(sdk): expose custom token cleanup hooks (#321).
 - **FIX**(build): keep zcash params pointed at official z.cash and align API source inputs (#301).
 - **FIX**(sdk): close balance and pubkey subscriptions on auth state changes (#232).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FIX**(custom-token-import): refresh asset lists on import and use lowercase identifiers for custom token import (#220).
 - **PERF**(streaming): expose managed `orderbook`, `swap_status`, and `order_status` subscriptions for stream-first trading refresh flows (#312, #262).
 - **PERF**(rpc): add in-flight and short-lived result caches for `trade_preimage`, `max_taker_vol`, `max_maker_vol`, and `min_trading_vol` (#262).
 - **PERF**(bridge): dedupe bridge orderbook depth requests, add taker preimage cache parity, and reduce validation retry fan-out (#262).
 - **PERF**(polling): reduce recurring `my_recent_swaps` payload size, slow swaps and orders polling away from active DEX routes, and keep minute-level balance sweeping as fallback only when live watchers are unavailable (#262).
 - **FEAT**(sdk): add SIA activation and withdrawal support (#320).
 - **FEAT**(sdk): add token safety checks, fee helpers, and custom-token cleanup hooks (#319, #321).
 - **FEAT**(coins): add TRON/TRC20 activation support, protocol wiring, and withdrawal coverage (#316).
 - **FEAT**(sdk): add asset, balance, and transaction-history manager interfaces (#314).
 - **FEAT**(sdk): add typed error mapping, trading-manager support, and activation/withdrawal refactoring foundations (#312).
 - **FEAT**(activation): integrate `ActivatedAssetsCache` to optimize asset activation checks.
 - **FEAT**(activation): add subclass token activation strategies and GRC routing for derived assets.
 - **FEAT**: add support for ETH-BASE and derived assets (#254).
 - **FEAT**(message-signing): add `AddressPath` type and refactor to use Asset/PubkeyInfo (#231).
 - **FEAT**(coin-config): add custom token support to coin config manager (#225).
 - **FEAT**(cex-market-data): add CoinPaprika API provider as a fallback option (#215).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_defi_types` - `v0.4.0`

 - **FIX**(types): use reified generics in JSON traversal for WASM and minified builds (#329).
 - **FIX**(startup): handle 6133 seed fallback and invalid configs (#318).
 - **FIX**(asset-tagging): correct UTXO coins incorrectly tagged as Smart Chain (#244).
 - **FIX**(sdk): close balance and pubkey subscriptions on auth state changes (#232).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FIX**(custom-token-import): refresh asset lists on import and use lowercase identifiers for custom token import (#220).
 - **FEAT**(sdk): add token safety helpers and custom token exceptions (#319).
 - **FEAT**(coins): add TRON/TRC20 protocols, protocol-type utilities, and derived-asset routing (#316).
 - **FEAT**(sdk): add typed error support, updated activation progress, and refreshed withdrawal/fee types (#312).
 - **FEAT**: add support for ETH-BASE and derived assets (#254).
 - **FEAT**(coin-config): add custom token support to coin config manager (#225).
 - **FEAT**(types): add parent display-name suffixes via subclasses (#213).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `komodo_wallet_cli` - `v0.5.0`

 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

#### `dragon_charts_flutter` - `v0.1.1-dev.4`

 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**: add configurable sparkline baseline (#248).

#### `dragon_logs` - `v2.0.1`

 - **FIX**(web): improve WASM JS interop bindings (#315).
 - **FIX**(zhltc): zhltc activation fixes (#227).

#### `komodo_coins` - `v0.3.2`

 - **PERF**(logs): reduce market metrics log verbosity and duplication (#223).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**(coin-config): add custom token support to coin config manager (#225).

#### `komodo_ui` - `v0.3.1`

 - **FIX**(ui): detect asset icon precache failures (#326).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FIX**(custom-token-import): refresh asset lists on import and use lowercase identifiers for custom token import (#220).
 - **FEAT**(coins): add TRON and TRC20 support (#316).
 - **FEAT**(sdk): add typed error handling, trading streams, and activation refactoring foundations (#312).

#### `komodo_wallet_build_transformer` - `v0.4.1`

 - **FIX**(build): keep zcash params pointed at official z.cash and align API source inputs (#301).
 - **FIX**(build): rename the transformer marker to `assets/transformer_invoker.txt`, update pubspec/README references, and remove the old dotfile exception.
 - **FEAT**(build): refresh GitHub asset downloading and typed build-transform plumbing for the new SDK generation flow (#312).


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
