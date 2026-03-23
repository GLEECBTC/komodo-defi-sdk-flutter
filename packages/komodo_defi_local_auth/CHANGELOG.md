## 0.4.0

> Note: This release has breaking changes.

 - **FIX**(test): add missing updateActiveUserMetadataKey to fake auth service (#330).
 - **FIX**(auth): add mutex-protected atomic metadata updates (#328).
 - **FIX**(auth): store bip39 compatibility regardless of wallet type (#216).
 - **FEAT**(sdk): typed error handling, trading streams, and activation refactoring (#312).
 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

## 0.3.1+2

 - Update a dependency to the latest release.

## 0.3.1+1

 - Update a dependency to the latest release.

## 0.3.1

 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

## 0.3.0+1

> Note: This release has breaking changes.

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

