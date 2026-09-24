## 0.4.0

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

## 0.3.2+1

 - Update a dependency to the latest release.

## 0.3.2

 - **PERF**(logs): reduce market metrics log verbosity and duplication (#223).
 - **FIX**(zhltc): zhltc activation fixes (#227).
 - **FEAT**(coin-config): add custom token support to coin config manager (#225).

## 0.3.1+2

 - Update a dependency to the latest release.

## 0.3.1+1

 - **FIX**: add missing deps.

## 0.3.1

 - **FIX**: pub submission errors.
 - **FEAT**(coin-updates): integrate komodo_coin_updates into komodo_coins (#190).

## 0.3.0+1

> Note: This release has breaking changes.

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

## 0.3.0+0

- chore: set homepage to https URL; switch to hosted deps; add LICENSE
