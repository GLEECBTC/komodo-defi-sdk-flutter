## 0.4.0

> Note: This release has breaking changes.

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

## 0.3.1+2

 - Update a dependency to the latest release.

## 0.3.1+1

 - Update a dependency to the latest release.

## 0.3.1

 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

## 0.3.0+1

> Note: This release has breaking changes.

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

## 0.0.1

* TODO: Describe initial release.

## 0.3.0+0

* Documentation overhaul: comprehensive README covering local/remote setup, seed nodes, logging, direct RPC usage, and build transformer integration.
