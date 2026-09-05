## Unreleased

 - **BREAKING** **FIX**(auth): `sdk.auth` metadata setters and atomic updates
   require the original `expectedWalletId`. Writes fail closed when identity
   cannot be verified or the active wallet changes. See the
   [local-auth migration guidance](../komodo_defi_local_auth/README.md#migrating-metadata-writes).

## 0.7.0

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

## 0.6.0

> Note: This release has breaking changes.

 - **FIX**(activation): restore coordinated TRX activation and market-data lookup (#340).
 - **FIX**(explorers): support TRON explorer URL templates in SDK transaction flows (#338).
 - **FIX**(market-data): keep last-known spot prices available while rotating cache snapshots (#335).
 - **FEAT**(migration): add SDK integration for legacy wallet discovery, verification, import, and cleanup.
 - **FEAT**(balances): add balance recovery mode and richer fee information plumbing (#341).
 - **FEAT**(transaction-history): add a Tronscan strategy with address, cursor, and fixed-scale amount codecs (#339).
 - **BREAKING** **FEAT**(sia): route SIA activation and withdrawals through the hardened SIA strategy and RPC namespace (#343).

## 0.5.0

> Note: This release has breaking changes.

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

## 0.4.0+3

 - Update a dependency to the latest release.

## 0.4.0+2

 - Update a dependency to the latest release.

## 0.4.0+1

 - **FIX**: add missing dependency.

## 0.4.0

> Note: This release has breaking changes.

 - **FIX**(cex-market-data): coingecko ohlc parsing (#203).
 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

## 0.3.0+1

> Note: This release has breaking changes.

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
 - **BUG**(auth): Fix registration failing on Windows and Windows web builds  (#34).
 - **BUG**(tx): Fix and optimise transaction history SDK.
 - **BREAKING** **FEAT**(sdk): Multi-SDK instance support.
 - **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

## 0.3.0+0

- chore: switch internal deps to hosted; add LICENSE; pin logging constraint
