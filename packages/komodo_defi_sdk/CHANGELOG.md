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
