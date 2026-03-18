# Tech Debt: PR #227 – ZHTLC Activation Fixes

Date: 2025-10-02  
PR: https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/227  
Head commit: 1af4278

This document compiles AI review findings into actionable tech-debt items with severity, impact, and recommended fixes. Items are grouped by concern.

## Build/Web-Safety

- [CRITICAL] Remove `dart:io` and `Platform.*` usage in web-visible factory
  - Files: `packages/komodo_defi_sdk/lib/src/zcash_params/zcash_params_downloader_factory.dart` (import at top, branches at ~49–71, ~121–130)
  - Problem: Unconditional `import 'dart:io';` and `Platform.*` branching break web/wasm builds.
  - Impact: Web builds fail at compile time.
  - Fix:
    - Replace `dart:io` import with `package:flutter/foundation.dart`.
    - Use `kIsWeb` and `defaultTargetPlatform`/`TargetPlatform` for branching.
    - Ensure `detectPlatform()` is web-safe and does not reference `Platform.*`.
    - If a dedicated `WebZcashParamsDownloader` exists, prefer it on `kIsWeb`.
    - Example branching:
      ```dart
      import 'package:flutter/foundation.dart';
      // ...
      if (kIsWeb) {
        return WebZcashParamsDownloader(/* ... */);
      }
      final platform = defaultTargetPlatform;
      if (platform == TargetPlatform.windows) { /* windows */ }
      else if (platform == TargetPlatform.iOS || platform == TargetPlatform.android) { /* mobile */ }
      else { /* unix-like (macOS, linux, fuchsia) */ }
      ```

## Mobile Storage Policy

- [MAJOR] Store Zcash params under Application Support, not Documents
  - File: `packages/komodo_defi_sdk/lib/src/zcash_params/platforms/mobile_zcash_params_downloader.dart` (header comment ~14–20; path resolution ~120–131)
  - Problem: Using Documents risks iCloud/backup violations on iOS and exposes internal assets to users.
  - Impact: Policy violations, user-visible clutter.
  - Fix:
    - Update comments to reference Application Support.
    - Use `getApplicationSupportDirectory()` and join `ZcashParams`.
    - Ensure directory exists before use (create recursively if missing).
    - Example:
      ```dart
      final supportDir = await getApplicationSupportDirectory();
      final paramsDir = Directory(path.join(supportDir.path, 'ZcashParams'));
      if (!(await paramsDir.exists())) {
        await paramsDir.create(recursive: true);
      }
      return paramsDir.path;
      ```

## Networking/Resilience

- [MAJOR] Add timeout to remote HEAD probe to prevent hangs
  - File: `packages/komodo_defi_sdk/lib/src/zcash_params/services/zcash_params_download_service.dart` (~311–319)
  - Problem: `_httpClient.head` is awaited without a timeout; if the server stalls, activation hangs.
  - Impact: Stalled activation; poor UX.
  - Fix:
    - Wrap in `.timeout(...)`; reuse `config.downloadTimeout` if available; otherwise a bounded default.
    - Catch `TimeoutException`, log at least at `fine`/`warning`, and return `null` for size.
    - Example:
      ```dart
      try {
        final response = await _httpClient
            .head(Uri.parse(url))
            .timeout(config.downloadTimeout);
        // ... handle 200 + content-length ...
      } on TimeoutException {
        _logger.warning('HEAD timeout for $url');
        return null;
      }
      ```

## Null-Safety/Defensive Coding

- [CRITICAL] Guard nullable `zcashParamsPath` before `.trim()`
  - File: `packages/komodo_defi_sdk/lib/src/activation/protocol_strategies/zhtlc_activation_strategy.dart` (~55–85)
  - Problem: `userConfig.zcashParamsPath.trim()` dereferences nullable; throws before friendly progress is emitted.
  - Impact: Activation crashes instead of returning error progress.
  - Fix:
    - Sanitize into a local: `final zcashParamsPath = userConfig?.zcashParamsPath?.trim();`
    - If null/empty: yield error `ActivationProgress` with `ActivationStep.error` and return.
    - Pass the sanitized `zcashParamsPath` into `params.copyWith(...)`.

## URL Handling

- [MAJOR] Percent-encode file URLs; fix test expectations
  - Files:
    - `packages/komodo_defi_sdk/lib/src/zcash_params/models/zcash_params_config.dart` (method building URLs ~152–159)
    - `packages/komodo_defi_sdk/test/zcash_params/models/zcash_params_config_test.dart` (URL with spaces ~497–503)
  - Problem: URLs with spaces are not encoded; test expects unencoded URL.
  - Impact: Invalid URLs and brittle tests.
  - Fix:
    - Build with `Uri.parse(baseUrl).resolve(fileName).toString()`.
    - Update tests to expect `%20`-encoded spaces.

## Tests/Determinism

- [MAJOR] Avoid host-dependent APPDATA assumptions in Windows downloader tests

  - File: `packages/komodo_defi_sdk/test/zcash_params/platforms/windows_zcash_params_downloader_test.dart` (~47–57, also ~60–80)
  - Problem: Tests assume `APPDATA` missing; on Windows CI this becomes flaky/non-deterministic.
  - Impact: Intermittent CI failures.
  - Fix:
    - Inject an `environmentProvider` into `WindowsZcashParamsDownloader` (e.g., `Map<String, String> Function()`).
    - Stub in tests with/without `APPDATA` to assert behavior deterministically.

- [MAJOR] Fix invalid string multiplication in Dart test
  - File: `packages/komodo_defi_sdk/test/zcash_params/models/zcash_params_config_test.dart` (~491–495)
  - Problem: Uses Python-style `'string' * 10`; invalid in Dart.
  - Impact: Test compilation error.
  - Fix:
    - Construct repeated string via `List.filled(10, 'very-long-file-name').join() + '.params'` (or similar).

## Nice-to-Have Enhancements

- [MINOR] Logging for timeouts and failures in size probe

  - Context: Same HEAD probe fix above.
  - Suggestion: Log at `warning` on timeout/network errors to aid telemetry.

- [MINOR] Ensure directory creation in mobile path getter
  - Context: Same mobile support path fix above.
  - Suggestion: Create the `ZcashParams` directory if missing before returning.

---

## Checklist (proposed follow-up PR)

- [ ] Factory: remove `dart:io` import; use `kIsWeb`/`defaultTargetPlatform` in all branches
- [ ] Factory: web branch returns `WebZcashParamsDownloader` (or define it if missing)
- [ ] Factory: `detectPlatform()` made web-safe (no `Platform.*`)
- [ ] Mobile downloader: switch to Application Support; ensure dir exists
- [ ] Download service: add timeout + handling to HEAD probe
- [ ] ZHTLC strategy: null-safe trim and sanitized injection of `zcashParamsPath`
- [ ] URL builder: use `Uri.resolve`; update tests to expect encoded URL
- [ ] Windows tests: inject env provider and stub `APPDATA`
- [ ] Dart test: replace string multiplication with `List.filled(...).join()`

Notes: Severity reflects build-breakers (critical), runtime bugs (major), and smaller quality improvements (minor).
