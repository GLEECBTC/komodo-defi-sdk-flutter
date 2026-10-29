# LI.FI integration validation — 2026-10-26

Scope: Phase 1 EVM swaps, SDK #407 and wallet #3557. No upstream merges,
production deployment, external recipients, Tron/BTC routing or funded execution.

## Contract and artifact provenance

- Contract: [gleec-specs `7c388ea7b91cb7c657435d416bc03e5349b46162`](https://github.com/GLEECBTC/gleec-specs/blob/7c388ea7b91cb7c657435d416bc03e5349b46162/specs/dex-wallet-routed-swap-contract.md).
- Engine: [KDF `35f0bde438eec2cb0471b19642b9d9c4602fa17d`](https://github.com/GLEECBTC/kdf-internal/commit/35f0bde438eec2cb0471b19642b9d9c4602fa17d), `feat/lifi-integration`.
- [Development builds run 39776954239](https://github.com/GLEECBTC/kdf-internal/actions/runs/39776954239), published 2026-10-22.
  Linux job `119818217142` failed on runner shutdown (exit 137). Its rerun,
  [job 121651086806](https://github.com/GLEECBTC/kdf-internal/actions/runs/39776954239/job/121651086806), succeeded on 2026-10-26.
  All seven platform jobs succeeded; deployment-commitment was skipped.
- The strict updater downloaded all seven archives, calculated SHA-256 digests
  and pinned one revision throughout. The digests also match published `.sha256`
  sidecars (Windows publishes an uppercase PowerShell table).
- The entire coins configuration remains unchanged, including commit
  `2b0aefb78b184091ab086c66e513d8b03f5d5a01`. No artifact gap remains.

| Platform | Archive SHA-256 | Source |
|---|---|---|
| web | `0992678b1d320f727f596dbbe3300799008719dedc2dba5d2203959d5bfa8c24` | [archive](https://devbuilds.gleec.com/feat-lifi-integration/kdf_35f0bde-wasm.zip) |
| ios | `cb069482dc2c64b0b9915af3bfe87bb967b3df5fd1eea4eccc414602f0efde5c` | [archive](https://devbuilds.gleec.com/feat-lifi-integration/kdf_35f0bde-ios-aarch64.zip) |
| macos | `b67d93080bd3dfb87b5614c56cfd7971d3b5463f637f5950d23ed737285e1a17` | [archive](https://devbuilds.gleec.com/feat-lifi-integration/kdf_35f0bde-mac-universal.zip) |
| android-armv7 | `f9cfb4efff5112aa674100d6f930f772d2305a0c8c5b8a3dc4d504d4c873fd75` | [archive](https://devbuilds.gleec.com/feat-lifi-integration/kdf_35f0bde-android-armv7.zip) |
| android-aarch64 | `9073f52b8652b19be34337c9fa9036a195fd104200ba6e0dd5ca5432c071093e` | [archive](https://devbuilds.gleec.com/feat-lifi-integration/kdf_35f0bde-android-aarch64.zip) |
| linux | `cf0cdfc90f36481b645ef034d0a7c775eb8380c4e1386aa82fb8c01640c55724` | [archive](https://devbuilds.gleec.com/feat-lifi-integration/kdf_35f0bde-linux-x86-64.zip) |
| windows | `064298f3e743989630321c05ae02dcd1f95dc8df533cfe6c49d26b28464b2d54` | [archive](https://devbuilds.gleec.com/feat-lifi-integration/kdf_35f0bde-win-x86-64.zip) |

From the SDK root, using Flutter 3.41.4 and its bundled Dart SDK:

```sh
dart run packages/komodo_wallet_cli/bin/update_api_config.dart \
  --branch feat/lifi-integration \
  --commit 35f0bde438eec2cb0471b19642b9d9c4602fa17d \
  --source mirror --mirror-url https://devbuilds.gleec.com --platform all \
  --config packages/komodo_defi_framework/app_build/build_config.json \
  --output-dir packages/komodo_defi_framework/app_build/temp_downloads --strict
```

## SDK validation

Commands used the explicit Flutter 3.41.4 installation, with prefetched locked
packages and `--no-pub`. Each package suite ran from its package directory.

| Suite | Command | Passed | Skipped |
|---|---|---:|---:|
| komodo_defi_rpc_methods | `flutter test --no-pub` | 379 | 0 |
| komodo_defi_types | `flutter test --no-pub` | 191 | 3 |
| komodo_defi_framework | `flutter test --no-pub` | 101 | 0 |
| komodo_defi_local_auth | `flutter test --no-pub` | 127 | 0 |
| komodo_coin_updates | `flutter test --no-pub` | 106 | 0 |
| komodo_defi_sdk | `flutter test --no-pub` (`KDF_HARNESS` unset) | 1192 | 1 |
| komodo_defi_harness, HD replay | `KDF_HARNESS_WALLET_TYPE=hd flutter test --no-pub --exclude-tags bench` | 221 | 3 |
| komodo_defi_harness, iguana replay | `KDF_HARNESS_WALLET_TYPE=iguana flutter test --no-pub --exclude-tags bench` | 221 | 3 |

Coverage includes exact/Max JSON requests, concrete execution amounts and exact
accepted minima, funding totals separate from spending, quote/task locked
balances, optional measured/provider payouts and both gas-estimation error
envelopes. Existing completion, partial/refund, approval/cancellation/restart and
recorded-gas scenarios remain covered. Startup tests cover unauthenticated
bootstrap, wallet creation, login/logout/restart, SDK policy copying/clearing,
and missing/disabled configuration. The coin transform is idempotent, preserves
explicit settings and runs for bundled, refreshed and cached startup data.

Barrels were regenerated with `dart run index_generator` in the affected types
and coin-updates packages. Changed Dart files were formatted. This command completed with zero errors,
17 existing warnings and 1537 informational diagnostics (nonzero exit due to
those diagnostics). No diagnostics intersect added lines or new Dart files:

```sh
flutter analyze --no-pub packages/komodo_coin_updates \
  packages/komodo_defi_framework packages/komodo_defi_harness \
  packages/komodo_defi_local_auth packages/komodo_defi_rpc_methods \
  packages/komodo_defi_sdk packages/komodo_defi_types
```

The final constructor-only lint cleanup was followed by another pass of the five
exact/Max/locked-balance RPC contract tests. `git diff --check` also passed.

## Read-only native checks

A new, unfunded, disposable wallet ran the pinned macOS binary. `version`
returned `3.1.1-beta_35f0bde`, built `2026-10-22T12:17:08.432718+00:00`.
Startup used `https://quicknode.gleec.com/lifi` and global `lifi_integrator`
`{name: gleec-dex-staging, fee_bps: 178, lifi_fee_bps: 22}`. The proxy retains
its API key. No `init`, approval, send or other fund-committing RPC was called.

| Exact quote | Receive / minimum (USDC) | Estimated gas (ETH) | Required gas balance (ETH) |
|---|---|---|---|
| 0.05 ETH-ARB20 → USDC-ARB20 | 114.430529 / 113.858376 | 0.00001070666 | 0.00007764378615 |
| 0.05 ETH-BASE → USDC-BASE | 114.367978 / 113.796138 | 0.000008161173672726 | 0.000015381878386716 |

Both routes reported one included `LIFI Fixed Fee` of `0.001 ETH` (2% combined).
No client-side commission calculation or second deduction is needed. Base
activation used the normalized `op_stack` fee model. Each `max: true` request
omitted `amount` and returned typed `InsufficientBalance`, with available `0`
and required `0.000000000000000001`, as expected for an unfunded wallet.
These observations establish proxy/engine quoting, not funded execution.

## Upstream CI is not passing

[KDF Test run 39776341104](https://github.com/GLEECBTC/kdf-internal/actions/runs/39776341104)
has these separate unit failures:

- `validate_dex_fee_invalid_sender_erc`: missing Ethereum transaction versus
  the expected invalid-sender result.
- `firo_lelantus_tx_details`: observed fee `0.00003793` versus expected zero.
- `test_block_header_utxo_loop`: observed count 2 versus expected 6.

WASM passed; dependent jobs were skipped. Recovering Linux artifacts does not
resolve these failures. Funded execution remains a separate human-operated round
on the wallet PR preview under `docs/SWAP_LIVE_TEST_BRIEF.md`.
