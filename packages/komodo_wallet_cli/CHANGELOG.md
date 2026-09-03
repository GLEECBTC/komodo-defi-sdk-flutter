## 0.6.0

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

## 0.5.1

 - **FEAT**(build): update API config tooling for the balance recovery and fee-info release inputs (#341).

## 0.5.0

> Note: This release has breaking changes.

 - **BREAKING** **FIX**(rpc): minimise RPC usage with comprehensive caching and streaming support (#262).

## 0.4.0+1

 - **REFACTOR**(komodo_wallet_cli): replace print() with stdout/stderr and improve logging.

## 0.4.0

> Note: This release has breaking changes.

 - **FIX**(pub): add non-generic description.
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

## 0.3.0+1

> Note: This release has breaking changes.

 - **PERF**: migrate packages to Dart workspace".
 - **PERF**: migrate packages to Dart workspace.
 - **FIX**(pub): add non-generic description.
 - **FIX**: unify+upgrade Dart/Flutter versions.
 - **FIX**(cli): Fix encoding for KDF config updater script.
 - **FEAT**: offline private key export (#160).
 - **FEAT**(dev): Install `melos`.
 - **BUG**(auth): Fix registration failing on Windows and Windows web builds  (#34).
 - **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).
 - **BREAKING** **FEAT**(sdk): Multi-SDK instance support.
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

## 0.3.0+0

- fix: add missing dependencies; add LICENSE
