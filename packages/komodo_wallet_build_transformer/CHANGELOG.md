## 0.5.0

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

## 0.4.2

 - **FIX**(github): accept numeric GitHub API values encoded as either `int` or `num` (#336).
 - **FEAT**(build): support the build inputs needed by balance recovery and fee-info updates (#341).

## 0.4.1

 - **FIX**: swap zcash params primary/backup URLs to use official z.cash as primary (#301).
 - **FIX**(komodo_defi_framework): rename transformer marker and update references\n\n- Use assets/transformer_invoker.txt instead of dotfile\n- Update pubspec and READMEs\n- Remove special .gitignore unignore.
 - **FEAT**(sdk): typed error handling, trading streams, and activation refactoring (#312).

## 0.4.0

> Note: This release has breaking changes.

 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

## 0.3.0+1

> Note: This release has breaking changes.

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

## 0.3.0+0

- chore: align with monorepo versioning; add LICENSE and repository
