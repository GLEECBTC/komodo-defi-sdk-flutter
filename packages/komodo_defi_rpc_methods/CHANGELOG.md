## 0.4.0

> Note: This release has breaking changes.

 - **FIX**(sdk): close balance and pubkeysubscriptions on auth state changes (#232).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**(coins): Add TRON and TRC20 support (#316).
 - **FEAT**(sdk): typed error handling, trading streams, and activation refactoring (#312).
 - **FEAT**(message-signing): Add AddressPath type and refactor to use Asset/PubkeyInfo (#231).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

## 0.3.1+1

 - Update a dependency to the latest release.

## 0.3.1

 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

## 0.3.0+1

> Note: This release has breaking changes.

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

## 0.3.0+0

- chore: update dependencies; replace path deps with hosted; add LICENSE
