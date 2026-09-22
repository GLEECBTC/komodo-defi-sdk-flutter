# SDK 0.8.0 release checklist

Prepared on 2026-09-11 from `dev` at
`dcf2f85b5c9f826dc7eca4fa50a247f3a4aa0f22`.
This is a release preparation record, not a publication announcement.
Distribution remains a pinned GitHub checkout/submodule.

## Preparation contents

- [x] Remove the temporary TRON/TRC20 private-key export workaround following
  [the September 14 review](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/382#issuecomment-5662538367).
  Structured export reports `unsupportedProtocol`; strict export rejects these
  protocols before an RPC. The earlier token-only export correction is
  superseded by this removal.
- [x] Carry native export retention across storage instances in a separate
  commit, addressing [review r3989814001](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/375#discussion_r3989814001).
- [x] Promote the seven candidates and all 19 dependency constraints that
  reference them. Preserve other versions and supported-version constraints.
- [x] Consolidate candidate notes, retain earlier preparation history, and
  document the complete [0.8.0 overview](../CHANGELOG.md#sdk-080-overview).
- [x] Document [installation and migration](RELEASE_0.8.0.md), including
  authentication identity/generation, diagnostic storage and export coverage.
- [x] Keep generated SDK lockfiles ignored; validate the consumer's own lockfile.
- [x] Restore incidental build configuration and remove newly generated source
  files from the release diff.

| Package | Prepared version |
| --- | --- |
| `komodo_defi_sdk` | `0.8.0` |
| `komodo_defi_local_auth` | `0.6.0` |
| `komodo_defi_framework` | `0.6.0` |
| `komodo_defi_types` | `0.6.0` |
| `komodo_defi_rpc_methods` | `0.7.0` |
| `komodo_coin_updates` | `2.1.1` |
| `dragon_logs` | `3.0.0` |

Unchanged package versions: `dragon_charts_flutter` 0.1.1-dev.4,
`komodo_cex_market_data` 0.1.0+2, `komodo_coins` 0.4.0,
`komodo_defi_harness` 0.1.0, `komodo_legacy_wallet_migration` 0.1.1,
`komodo_symbol_converter` 0.3.0+1, `komodo_ui` 0.3.3,
`komodo_wallet_build_transformer` 0.5.0 and `komodo_wallet_cli` 0.6.0.
Example, playground and product versions also remain unchanged.

## Release inputs

The authoritative input is
[`build_config.json`](../packages/komodo_defi_framework/app_build/build_config.json).
Its full contents, including required platforms, download sources and archive
checksums, are unchanged by the 0.8.0 preparation PR. `add/routed-swap`
changes `api.branch`, `api.api_commit_hash` and all seven
`valid_zip_sha256_checksums` - see
[`packages/komodo_defi_framework/CHANGELOG.md`](../packages/komodo_defi_framework/CHANGELOG.md).

| Input | Pin |
| --- | --- |
| KDF | `f3efd2ca10420f2982fa127dde84dcc17891f577` (`3.1.0-beta_f3efd2c`, `main`) at 0.8.0 preparation; repinned on `add/routed-swap` to `4872ef2e0bb07348673e1578aca4aca53f3d73b6` (`feat/lifi-integration`) |
| Bundled coins | `a4fa5547a2c508223dc4e5c449549699c9049856` |
| Coin repository | `GLEECBTC/coins`, `master` |
| KDF mirrors | `https://devbuilds.gleec.com`, then `https://nebula.decker.im` |
| Validation toolchain | Flutter `3.41.4` / Dart `3.11.1`, macOS arm64 |
| SDK declared minimums | Dart `>=3.9.0 <4.0.0`, Flutter `>=3.35.0` (unchanged) |
| Consumer baseline | Gleec Wallet `d680a82da65e73cb064c0cf88f53155a2504e848` |

Required artefacts remain web, iOS, macOS, Android ARMv7, Android AArch64,
Linux and Windows. Native cache provenance was verified by the transformer;
this is not equivalent to executing the app on all seven targets.

## TRON export removal validation — 2026-09-14

The removal was validated with Flutter 3.41.4 / Dart 3.11.1:

| Check | Result |
| --- | --- |
| Full SDK package suite | 944 passed, 1 existing skip |
| RPC methods package suite | 237 passed |
| Types package suite | 183 passed, 3 existing skips |
| Export regressions within the SDK suite | 26 passed |
| SDK package analysis | No errors; 11 warnings and 822 infos remain in existing code |

The export regressions cover both wallet modes, TRX/TRC20 rejection before
RPC, HD index 777, missing catalog metadata, mixed selections and retained
offline-export/session guards. No changed source has an analysis error or
warning. An independent read-only review found no actionable issues.
This validation covers the removal; the wider release evidence below remains
scoped to the earlier preparation tree.

## Historical validation results — 2026-09-11

These results describe the original release-preparation tree before the
September 14 TRON/TRC20 export removal. Counts include tests for the now-removed
workaround and must not be used as validation of the current tree. The obsolete
pinned-KDF export contract and its execution wrapper have been removed.

The standalone SDK workspace resolved with `flutter pub get --offline` using
Flutter 3.41.4. Each direct package below ran
`KDF_HARNESS="" flutter test --no-pub --reporter expanded` from its directory.
All 16 package suites passed (2,359 tests, 15 existing skips).

| Package | Passed | Skipped |
| --- | ---: | ---: |
| `dragon_charts_flutter` | 17 | 0 |
| `dragon_logs` | 26 | 0 |
| `komodo_cex_market_data` | 334 | 6 |
| `komodo_coin_updates` | 104 | 0 |
| `komodo_coins` | 137 | 0 |
| `komodo_defi_framework` | 69 | 0 |
| `komodo_defi_harness` | 31 | 4 |
| `komodo_defi_local_auth` | 88 | 0 |
| `komodo_defi_rpc_methods` | 241 | 0 |
| `komodo_defi_sdk` | 967 | 2 |
| `komodo_defi_types` | 183 | 3 |
| `komodo_legacy_wallet_migration` | 14 | 0 |
| `komodo_symbol_converter` | 1 | 0 |
| `komodo_ui` | 4 | 0 |
| `komodo_wallet_build_transformer` | 113 | 0 |
| `komodo_wallet_cli` | 30 | 0 |

The historical SDK suite included all 49 private-key export regressions.
Native logging included 24 privacy/retention tests and two existing logger tests.
The SDK's former opt-in KDF contract skip was exercised separately below; that
contract is now removed. Its other skip was the existing balance-cache
reattachment fixture. Market-data live API tests, types benchmarks and opt-in
harness cases retained their existing skip policy.

| Additional check | Result |
| --- | --- |
| Browser logging privacy | 10 passed in Chrome |
| Six CI Wasm wallet/GasFree race files | 164 passed in Chrome/Wasm |
| Former pinned KDF active TRON export, HD indices 0 and 7 | Historical: 1 passed with synthetic local fixtures; workaround and contract test removed on September 14 |
| Harness replay, HD | 28 passed, 3 skipped |
| Harness replay, legacy/Iguana | 28 passed, 3 skipped |
| SDK example web release build | Passed; embedded KDF and coin pins match the table above |
| Playground web release build | Passed; embedded KDF and coin pins match the table above |
| Isolated wallet unit gate | 991 passed, 3 existing skips, all four GasFree defines |
| Compliance console sample | 8 passed |
| Changed Dart formatting / diff whitespace | Passed; four Dart files already formatted |
| Dependency/version consistency | Seven promotions, 19 constraints; other versions and environment constraints unchanged |
| Workspace analysis | No errors; 41 warnings and 1,763 infos, matching unchanged `dev` after normalizing line shifts |

Analysis still exits nonzero for the existing findings. No new diagnostic was
introduced by the release source changes. Build-generated Dart wrappers were
moved out of the source checkout before the final comparison.

Build setup initially stopped four suites because the isolated cache lacked
the iOS provenance marker. Restoring the existing marker resolved this without
a source change. The first example web build stopped with the transformer's
expected `Coin assets were updated` message. Both final web builds were then
run with `coins.update_commit_on_build` temporarily false to retain the reviewed
coin pin; the exact original configuration was restored afterward. KDF fetching
used `OVERRIDE_DEFI_API_DOWNLOAD=false`, which still enforces provenance.
No binaries, checksums or coin pins are changed in this PR.

The isolated consumer initially rejected its old lockfile under
`--enforce-lockfile`, as expected after the version promotions. A normal offline
resolution changed only the seven SDK version records; the subsequent enforced
resolution and unit gate passed. No consumer changes are included in this PR.
Its three skipped tests remain `Get formatted USD balance using SDK balance`,
`getTotal24Change calculates total change`, and `Total fee positive test`.

## Outstanding sample checks

Keep this PR draft until these existing sample-test failures are resolved or
explicitly excluded from the release gate. They do not invalidate the passing
SDK package suites, browser races, web builds or wallet unit gate.

| File / exact failing test | Finding |
| --- | --- |
| `packages/dragon_logs/example/test/widget_test.dart` — `Counter increments smoke test` | No widget is mounted, but the template expects a counter showing `0`. |
| `products/dex_dungeon/test/game/cubit/audio_cubit_test.dart` — `AudioCubit can be instantiated` | The global audio plugin initialization is not mocked. |
| Same file — `AudioCubit toggleVolume mutes the volume when the volume is not 0` | Audio plugin initialization escapes the existing mock setup. |
| Same file — `AudioCubit toggleVolume unmutes the volume when the volume is 0` | Audio plugin initialization escapes the existing mock setup. |
| `playground/test/widget_test.dart` — test-file loading | The entire file is commented out; no `main` exists. |

All five failures also reproduce in a separate checkout of the starting `dev`
commit. These sample test sources are unchanged.
Dex Dungeon's remaining 24 tests pass. The failure is
`MissingPluginException` on `xyz.luan/audioplayers.global`, not an SDK export
failure. The playground application itself builds successfully for web.

## Reproduce the retained additional gates

The deleted TRON export contract is excluded from these commands. Running the
retained gates on the current tree produces new evidence; the historical counts
above are not expected totals for the revised suite.

Use Flutter 3.41.4 on `PATH`. On macOS, configure the existing Chrome wrapper:

```sh
export CHROME_EXECUTABLE="$PWD/tool/flutter_test_chrome.sh"
export FLUTTER_TEST_CHROME_BINARY='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
```

Run browser logging from `packages/dragon_logs`:

```sh
flutter test --no-pub --platform chrome --reporter expanded test/web_log_storage_privacy_test.dart
```

Run the exact Wasm selection from `packages/komodo_defi_sdk`:

```sh
flutter test --no-pub --platform chrome --wasm --reporter expanded \
  test/activation/activation_wallet_race_test.dart \
  test/transaction_history/transaction_history_manager_wallet_race_test.dart \
  test/withdrawals/pending_gasless_transfer_repository_test.dart \
  test/withdrawals/withdrawal_manager_gasless_test.dart \
  test/withdrawals/gasless_submission_lock_web_test.dart \
  test/withdrawals/pending_gasless_transfer_repository_web_test.dart
```

Run replay from `packages/komodo_defi_harness`, leaving `KDF_HARNESS` empty:

```sh
KDF_HARNESS="" KDF_HARNESS_WALLET_TYPE=hd flutter test --no-pub --exclude-tags bench
KDF_HARNESS="" KDF_HARNESS_WALLET_TYPE=iguana flutter test --no-pub --exclude-tags bench
```

Run `flutter build web --no-pub --release` from both
`packages/komodo_defi_sdk/example` and `playground`. The existing build policy
can advance the coin pin; control that policy during pinned validation, inspect
the generated assets, then restore incidental source changes before committing.

Run the wallet gate from the isolated consumer root:

```sh
flutter test --no-pub test_units/main.dart \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
```

## Platform and publication handoff

- [ ] Resolve the sample-test gate above and review CI for the final PR commit.
- [ ] Perform Android/iOS device, Windows/Linux native and hardware-wallet
  smoke checks in their platform environments. Signed mobile/desktop builds,
  the real OS share sheet and cross-browser coverage were not exercised locally.
- [ ] Perform any separately required funded-network harness/benchmark checks.
  This preparation used replay and synthetic pinned-KDF fixtures, with no live
  transaction submission.
- [ ] Merge the preparation PR to `dev`, then follow the repository's release
  promotion process to make the reviewed commit available on the distribution
  branch. Record the full final release commit.
- [ ] Create approved package tags and the GitHub release against that commit,
  using the reconciled notes. Do not mistake earlier preparation headings for
  published releases.
- [ ] If pub.dev publication is later selected, separately validate standalone
  publishability, dependency ordering and hosted availability; this GitHub/
  submodule preparation does not certify that distribution path.
- [ ] In a separate consumer PR, fetch the published SDK commit, check it out
  explicitly, update all path overrides together, resolve/review the consumer
  lockfile, run the four-define unit gate and platform checks, then commit the
  SDK gitlink and lockfile. See the [repinning instructions](RELEASE_0.8.0.md#pin-the-complete-checkout).

Tagging, release publication, package publishing and consumer repinning are
deliberately left for this handoff; none is performed by the preparation PR.
