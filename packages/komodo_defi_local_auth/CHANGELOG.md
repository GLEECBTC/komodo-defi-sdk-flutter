## Unreleased

 - **BREAKING** **FIX**(auth): require `expectedWalletId` on metadata setters
   and atomic updates, including custom auth implementations. Capture the
   original wallet identity before asynchronous work and forward it through
   every write. See [migration guidance](README.md#migrating-metadata-writes).
 - **FIX**(auth): reject metadata writes when either identity lacks a verified
   public-key hash, preventing stale confirmations from reaching a different
   wallet recreated under the same name during an identity lookup outage.

## 0.5.0

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

## 0.4.1

 - **FIX**(auth,migration): wait for KDF RPC readiness and guard unsupported platforms during migration.
 - **FEAT**(migration): add local-auth integration for legacy wallet verification and import flows.

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
