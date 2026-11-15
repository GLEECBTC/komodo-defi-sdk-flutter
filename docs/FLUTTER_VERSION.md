# Flutter and Dart toolchain

The SDK workspace uses **Flutter 3.50.0 / Dart 3.14.0**. The version in the
root `.fvmrc` is shared by FVM and the active GitHub Actions workflows through
`.github/actions/setup-flutter`. Keep the consuming wallet's pin aligned with
this workspace when updating its SDK submodule.

Install and select the workspace toolchain without changing the global SDK:

```sh
fvm install
fvm use 3.50.0 --skip-pub-get
fvm flutter --version
fvm flutter pub get --enforce-lockfile
```

The package manifests require Dart `>=3.14.0 <4.0.0`; Flutter packages require
Flutter `>=3.50.0 <4.0.0`. These are the supported development baseline, including
the workspace examples and products. Historical release checklists retain the
toolchains used to produce their recorded results.

The private workspace tracks `pubspec.lock`, and CI enforces it. When deliberately
changing dependency constraints, resolve with `fvm flutter pub get`, review the
lockfile diff, and then verify `fvm flutter pub get --enforce-lockfile`.
Freezed 4 is required for the analyzer used by Flutter's test packages and to
generate constructors accepted by Dart 3.14. Run the full generator after an
upgrade so JSON serializers and Hive adapters remain present alongside Freezed
outputs; partial build filters can remove companion outputs.

Use the pinned Flutter for tests and its bundled Dart for generation. For Melos,
pass the selected SDK explicitly so subprocesses also use the same toolchain:

```sh
fvm dart run melos --sdk-path .fvm/flutter_sdk bootstrap
fvm dart run melos --sdk-path .fvm/flutter_sdk run prepare --no-select
fvm flutter analyze --no-pub
cd packages/komodo_defi_sdk
KDF_HARNESS='' fvm flutter test --no-pub
```

Run each affected package's full suite, the KDF harness replay suite, and the
browser/WebAssembly suites in `.github/workflows/flutter-tests.yml`. Flutter
builds must also be verified on their native hosts: Android, iOS, macOS, Windows,
Linux, and web. Installing the toolchain or resolving packages does not establish
native build or runtime compatibility.

References: [Flutter 3.50 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.50.0),
[Dart changelog](https://dart.dev/resources/changelog), and
[supported platforms](https://docs.flutter.dev/reference/supported-platforms).

## Upgrade validation (2026-11-15)

Validated locally with Flutter 3.50.0 / Dart 3.14.0:

- All 16 SDK package suites: **3,130 passed, 14 skipped**, including the harness
  replay suite with `--exclude-tags bench`. Process tests remained disabled.
- Chrome WebAssembly CI cases: **215 passed** for SDK wallet isolation and
  GasFree races; **10 passed** for framework transport errors and diagnostics.
- `flutter pub get --enforce-lockfile` passed.
- Full `flutter analyze --no-pub`: **0 errors, 45 warnings, 2,000 infos**.
  The default analyzer command remains nonzero because of those diagnostics;
  this is not a clean-analysis claim. The final changed Trezor test analyzed
  without issues.
- Freezed models were regenerated with Freezed 4.0.3 and formatting enabled.
  All tracked JSON serializers, Hive adapters, and Hive schema outputs remained
  unchanged. `git diff --check` passed.

Fresh-checkout asset preparation required a second harness/browser invocation
after the coin and KDF assets were generated. The results above describe those
completed runs. The initial Trezor test timing failure was fixed by waiting for
the actual stream subscription and completion instead of millisecond delays;
the full local-auth suite then passed all 163 tests.
