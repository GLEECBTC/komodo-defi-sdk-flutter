# SDK 0.9.0 release checklist

Prepared 28 October 2026. This is a candidate record, not publication approval.

## Scope and immutable inputs

- Integration source: `03a3cb1adf666952a16f0cd80e67b8173076f4c1` (SDK #407),
  including SDK #405 activation fixes. Initial preparation added release
  metadata and dependency constraints. Runtime freeze fixes are SDK #412
  (`97b48556`) and #413 (`56828b91`); the KDF engine input remains unchanged.
- Previous distribution: `a96398ba9ae72efbe654de7c3edc0bfe2b05dda0` (SDK 0.8.1,
  merged #398). Latest published release: `komodo_defi_sdk-v0.8.0`.
- Branch strategy: **squash every PR into `dev`**; use a merge commit for
  `dev` → `main` release promotion. Source-branch reconciliation merges do not
  change this rule. Squashing drops source merge parents, so compare content
  and record the real squash SHA rather than assuming ancestry is retained.
- Previous main `a96398ba` and its merge parent `331a6879` have identical trees. The preparation
  branch's earlier main-history sync is not expected to survive its squash.
  Review the final promotion diff and merge result instead of requiring that
  this source-branch sync become an ancestor of `dev`.
- KDF: `35f0bde438eec2cb0471b19642b9d9c4602fa17d`; specs:
  `7c388ea7b91cb7c657435d416bc03e5349b46162`; coins:
  `2b0aefb78b184091ab086c66e513d8b03f5d5a01`.
- All seven archive checksums are in `app_build/build_config.json` with
  [28 October provenance](KDF_ARTIFACTS_2026-10-28.json). Build-time coin
  advancement is disabled; runtime updates remain enabled.
- Direct source inspection on 28 October confirms the security fix shipped in
  wallet 0.9.7-1: [candidate eth.rs, line 5859](https://github.com/GLEECBTC/kdf-internal/blob/35f0bde438eec2cb0471b19642b9d9c4602fa17d/mm2src/coins/eth.rs#L5859)
  checks the ERC-20 payment amount outside the watcher-reward branch, as in
  [KDF 3.1.1-beta](https://github.com/GLEECBTC/kdf-internal/commit/2023112fa67b28cbebc2a7064d22267fed40310f).
  The branches diverge; this source check does not certify every later main fix.

## Preparation gates

- [x] Version every changed library package and dependency-only consumer.
- [x] Update workspace constraints together; preserve toolchain constraints.
- [x] Date package changelogs and add overview, API migration and engine limits.
- [x] Separate SDK Max behavior from the wallet's native gas-reserve policy.
- [x] Resolve SDK workspace and consumer dependencies offline; consumer lockfile
  changes only 11 local SDK package version lines; enforce-lockfile succeeds.
- [x] Run all 16 SDK package suites on prepared versions.
- [x] App consumer aggregator passed 3,898 tests / four skipped on the prepared
  runtime and dependency graph, as recorded in app preparation #3560.
- [x] Full consumer/workspace analysis after dependency setup: zero errors,
  55 warnings and 2,130 infos in unchanged code. No Dart implementation changed.
- [x] SDK #405 and #407 squash merged into `dev`; the combined resulting tree
  exactly matches tested integration `03a3cb1a`.
- [x] Preparation #409 squash merged into `dev` as `cc9a5855`; generation
  repair #411 is `6038592a`. Ownership/recovery #412 is `97b48556` and EVM
  history #413 is `56828b91`. Source-branch and squash content were compared.
- [x] Resolve the two SDK #410 correlation/session review findings through
  #412 and add native/browser regressions. Both threads are resolved.
- [ ] Final `dev` → `main` promotion contains this preparation; record its SHA,
  complete its required CI/review conditions. The promotion is ready for review;
  its normal merge must still satisfy repository protections.

## Validation record

Fresh preparation results are recorded in the preparation PR. Historical SDK
#407 evidence on `03a3cb1a`: all 16 package suites, both WASM test steps and both
previews passed. Those runs are not evidence for the prepared version graph.
Flutter 3.41.4 / Dart 3.11.1 is the validation toolchain. The all-package runner
is `.github/workflows/flutter-tests.yml`; it intentionally tests `packages/*`,
not every sample/product. Historical sample-test exclusions from 0.8.0 remain
separate; do not silently expand or waive them.

### Fresh preparation results — 28 October 2026

All **16 package suites passed: 3,045 tests, 14 skipped**, using
`flutter test --no-pub --reporter expanded` from each `packages/*` directory
with tests. Workspace resolution used the existing offline package cache.
No Dart source changes were made. No formatting was needed for this metadata
change. Local Markdown targets, dependency minimums and `git diff --check` pass.

| Package | Passed | Skipped |
| --- | ---: | ---: |
| `dragon_charts_flutter` | 17 | 0 |
| `dragon_logs` | 27 | 0 |
| `komodo_cex_market_data` | 362 | 6 |
| `komodo_coin_updates` | 106 | 0 |
| `komodo_coins` | 143 | 0 |
| `komodo_defi_framework` | 101 | 0 |
| `komodo_defi_harness` | 224 | 4 |
| `komodo_defi_local_auth` | 127 | 0 |
| `komodo_defi_rpc_methods` | 379 | 0 |
| `komodo_defi_sdk` | 1200 | 1 |
| `komodo_defi_types` | 191 | 3 |
| `komodo_legacy_wallet_migration` | 14 | 0 |
| `komodo_symbol_converter` | 1 | 0 |
| `komodo_ui` | 4 | 0 |
| `komodo_wallet_build_transformer` | 119 | 0 |
| `komodo_wallet_cli` | 30 | 0 |

Full analysis after resolving both workspaces: **zero errors**, 55 existing
warnings and 2,130 infos. An earlier pass before SDK test dependency setup
reported missing dev packages; resolving the SDK removed those setup errors.
WASM/platform builds and hosted CI must still run on final promotion.

## Before distribution

- [ ] Resolve/review the KDF native bridge-fee restriction, status-error polling,
  specs review and proxy/backend deployment provenance and recovery evidence.
- [ ] Attribute upstream failures `validate_dex_fee_invalid_sender_erc`,
  `firo_lelantus_tx_details`, `test_block_header_utxo_loop` from KDF run
  `39776341104`. An artifact rebuild does not close them.
- [ ] Validate signed consumer artifacts, fresh install/upgrade, Safari and
  hardware/platform behavior on the final commit, with funded checks operated
  by a person. Rebuild/revalidate all seven targets if KDF changes.
- [ ] Merge reviewed SDK promotion with a merge commit; record final SHA.
- [ ] Create `komodo_defi_sdk-v0.9.0` and approved package tags on that SHA.
  Use the reconciled changelog and migration guide for GitHub release notes.
- [ ] Repin the app to the final SDK `main` commit; review its lockfile and
  rerun consumer gates. A preparation branch pin is provisional.
- [ ] If pub.dev is selected later, separately validate publishability and
  dependency order. This checkout preparation does not certify pub.dev.

No tag, release publication, production deploy, ruleset bypass or merge is
performed by these preparation changes.

## Dev merge record — 28 October 2026

- SDK #405: squash `50e4ef025692870f759b47d84ab2ba6c079a93f5`.
- SDK #407: squash `76140abb2312f6c306c3118a2cd619c8985e64a3`.
- Squashing #405 first created one changelog conflict in #407. Reconciliation
  `63b3660d` retains the already combined notes; its complete tree matches
  tested `03a3cb1a`. No runtime implementation or build pin changed.
- The owner explicitly authorized admin bypass for these dev merges. Review
  protections and repository settings were not changed. Final distribution
  gates remain in force on draft SDK release PR #410.
- The preparation source branch is reconciled with the real dev squash before
  #409 is retargeted. Its runtime/dependency files remain those tested at
  `2f6ba724`; subsequent changes only correct the strategy and execution record.

## Melos release validation — 28 October 2026

Workspace Melos 7.8.1 uses Flutter 3.41.4 / Dart 3.11.1. The configured
`bootstrap` post-hook runs `prepare`, which runs indexes then build runners.
The generated workspace lockfile remains ignored; release validation uses its
locked cached dependencies, and consumer lockfile policy stays independent.

```sh
dart run melos --sdk-path /path/to/flutter-3.41.4 bootstrap --offline --enforce-lockfile
dart run melos --sdk-path /path/to/flutter-3.41.4 run prepare --no-select
dart run melos --sdk-path /path/to/flutter-3.41.4 list --json
dart run melos --sdk-path /path/to/flutter-3.41.4 exec --concurrency=1 \
  --dir-exists=test --ignore='*_example' --ignore=dex_dungeon \
  --ignore=komodo_compliance_console -- flutter test --no-pub --reporter expanded
```

The first bootstrap completed but exposed invalid regenerated indexes: direct
exports of routed-swap `part of` files and both native/web lock implementations
caused five analysis errors. Generator exclusions now retain conditional entry
points and export the owning routed-swap library. Bootstrap passes after the
fix; repeating `prepare` produces identical output. Melos resolves 22 packages,
and the test filters select the same 16 package suites as CI. Samples/products
remain explicitly separate, as in the existing release process.

Regenerated Hive registrars use the generator's current `hive_ce.dart` import.
One Freezed file changed only four blank-line spaces; that unrelated whitespace
was restored after generation stability was verified. Formatting changed Dart
files requires no additional edits. Package versions and dependency constraints
are unchanged by this generation repair.

Fresh validation after the repair:

- `melos exec` selected all 16 CI package suites: **3,045 passed / 14 skipped**.
- App aggregator with all four production GasFree defines: **3,898 passed /
  four skipped**, 4m59s, against the regenerated SDK.
- Six SDK wallet-isolation/GasFree files: **176 passed in Chrome/WASM**.
- Two framework WASM transport/diagnostic files: **10 passed**.
- Auth suite after excluding the internal Trezor password-store helper from
  the public generated barrel: **127 passed**. Its public export surface is
  preserved; the service keeps its explicit internal helper import.
- Full analysis: **zero errors**, 55 warnings and 2,146 infos. Generated ignored
  web wrappers account for the added informational notices relative to the
  earliest analysis snapshot. No new changed-line diagnostic remains.
- Changed-file Dart formatting and diff checks pass. Package versions and the
  consumer dependency versions do not change. No tag or publication command
  is needed to validate these already prepared candidate versions.

## Code-freeze validation — runtime `56828b91`

- [x] Enforced offline Melos bootstrap, including index/build-runner hooks,
  completed after the final runtime fixes with no tracked generation drift.
- [x] All 16 package suites: **3,056 passed / 14 skipped**. This supersedes the
  earlier preparation counts above; those remain historical evidence.
- [x] Nine core Chrome/WASM ownership, wallet/history and GasFree files:
  **213 passed**. Both framework transport/diagnostic files also passed in
  [SDK #413 CI](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/413/checks).
- [x] A temporary real browser/WASM probe confirmed ETC Blockscout account API
  reads across origins using only the public burn address. The configured
  proxy ETC route returned 404. Private QA wallet addresses were not sent.
- [x] SDK history analysis: zero errors, 14 existing informational diagnostics;
  no new changed-line diagnostic. Changed Dart formatting and diff checks pass.
- [x] SDK #412 and #413 hosted tests, SDK/playground builds and preview checks
  passed. The promotion head must independently meet its required checks.

SDK runtime changes are complete for this freeze scope. Main promotion and
consumer immutable-main repin remain the ordered steps above. Tags, public
publication, upstream operational signoff and signed-platform certification
retain their separate release gates; no live funds were submitted by an agent.
