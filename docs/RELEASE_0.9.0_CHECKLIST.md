# SDK 0.9.0 release checklist

Prepared 28 October 2026. This is a candidate record, not publication approval.

## Scope and immutable inputs

- Integration source: `03a3cb1adf666952a16f0cd80e67b8173076f4c1` (SDK #407),
  including SDK #405 activation fixes. Preparation adds release metadata and
  dependency constraints; it does not change the engine or swap implementation.
- Previous distribution: `a96398ba9ae72efbe654de7c3edc0bfe2b05dda0` (SDK 0.8.1,
  merged #398). Latest published release: `komodo_defi_sdk-v0.8.0`.
- `main` and its merge parent `331a6879` have identical trees. A normal merge
  records `main` in this preparation history without overwriting source changes.
  Promote with merge commits to preserve ancestry and avoid repeating the
  0.8.0 squash-history conflict. Recheck ancestry after integration/preparation.
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
- [ ] Complete the app consumer unit run (recorded separately in app preparation).
- [x] Full consumer/workspace analysis after dependency setup: zero errors,
  55 warnings and 2,130 infos in unchanged code. No Dart implementation changed.
- [ ] SDK #407 and this preparation reach `dev`; retarget preparation to `dev`
  after the integration merges if required. Verify source/tree equivalence when
  squash merges change commit identities.
- [ ] Final `dev` → `main` promotion contains this preparation; record its SHA,
  complete CI and obtain release review. Keep the promotion PR draft until then.

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
