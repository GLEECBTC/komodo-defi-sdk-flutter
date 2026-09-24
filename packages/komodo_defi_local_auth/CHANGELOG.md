## 0.6.0 (unreleased)

Prepared for SDK 0.8.0 with verified metadata writes, session contexts, atomic
wallet creation and reviewed deletion. Callers and custom authentication
implementations must migrate before adopting this version.

 - **BREAKING** **FIX**(auth): require `expectedWalletId` on metadata setters
   and atomic updates, including custom auth implementations. Capture the
   original wallet identity before asynchronous work and forward it through
   every write. See [migration guidance](README.md#migrating-metadata-writes).
 - **FIX**(auth): reject metadata writes when either identity lacks a verified
   public-key hash, preventing stale confirmations from reaching a different
   wallet recreated under the same name during an identity lookup outage.
 - **BREAKING** **FEAT**(auth): add `authGeneration` and `authGenerationChanges`
   to `KomodoDefiAuth` and the auth service interface. A capability holder can
   revoke synchronously as the generation advances, before an authentication
   transition completes; custom implementations must provide both members,
   transition state and
   the session invalidation/transition methods. See the
   [authentication lifecycle migration](README.md#migrating-authentication-lifecycle).
 - **FIX**(auth): run sign-in, registration, sign-out, session restore and
   disposal through one serialized authentication transition, so a transition
   cannot interleave with another or with KDF lifecycle changes.
 - **BREAKING** **FEAT**(auth): add session contexts to `KomodoDefiAuth` and the
   auth service interface: `captureSessionContext`, `isSessionContextCurrent`,
   `ensureSessionContextCurrent`, `watchSessionContext` and
   `updateMetadataForSession`. A context survives metadata and identity
   refreshes but not a sign-out, a wallet switch or reauthentication.
   `AuthSessionContext`, `AuthSessionChangedException` and
   `AuthIdentityUnavailableException` are exported, and custom implementations
   must provide the new members. See the
   [migration guide](../../docs/RELEASE_0.8.0.md#wallet-identity-and-authentication).
 - **BREAKING** **FEAT**(auth): `register` and `registerStream` accept
   `initialMetadata`, saved with the new wallet's first record before it is
   published. A name that already exists fails with `walletAlreadyExists`
   instead of signing into that wallet.
 - **BREAKING** **FEAT**(auth): `deleteWallet` accepts a one-use
   `WalletDeletionPermit`. Once `requireWalletDeletionReview` installs a
   coordinator, deletion without a permit from `authorizeWalletDeletion` throws
   `WalletDeletionReviewRequiredException`. The permit's check runs against the
   fresh catalog record before the RPC, and the auth service's `deleteWallet`
   gains `beforeDelete` and `afterDelete`. See the
   [migration guide](../../docs/RELEASE_0.8.0.md#wallet-deletion-and-retained-recovery).
 - **FIX**(auth): serialize wallet creation, listing and deletion across local
   SDK instances and browser tabs with a catalog lock, and stored-user writes
   with a record lock; both are Web Locks in the browser. Stored users change
   through atomic read-modify-write updates. `onWalletDeletion` hooks run
   inside the deletion's catalog transaction, so a hook must not wait on
   `getUsers`, registration or another deletion.
 - **FEAT**(auth): stamp each stored wallet with an SDK-owned entry identity
   (`walletEntryIdMetadataKey`), renewed when the wallet is recreated, so a
   deletion review cannot apply to a replacement with the same name. Metadata
   updates cannot write that key.
 - **FIX**(auth): report a KDF outage during mnemonic retrieval as
   `apiConnectionError`, so callers can retry, without the failed RPC's text.

 - **CHORE**(deps): align workspace requirements with SDK 0.8.0:
   `komodo_defi_framework` `^0.6.0`, `komodo_defi_types` `^0.6.0`,
   `komodo_defi_rpc_methods` `^0.7.0`.
 - **CHORE**(deps): add `web` `^1.1.1` for the browser Web Locks.

## 0.5.0 — preparation history

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

## 0.4.1 — preparation history

 - **FIX**(auth,migration): wait for KDF RPC readiness and guard unsupported platforms during migration.
 - **FEAT**(migration): add local-auth integration for legacy wallet verification and import flows.

## 0.4.0 — preparation history

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
