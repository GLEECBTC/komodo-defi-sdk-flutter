## 3.0.0 (unreleased)

> Note: This version has breaking storage and logger interfaces.

 - **BREAKING** **FEAT**(storage): `LogStorage.init` and `LoggerInterface.init`
   take `storageNamespace` and `purgeLegacy`, both interfaces gained `dispose`,
   and `FileLogStorage` is no longer a process-wide singleton. `DragonLogs.init`
   mirrors the new parameters and every API now fails closed before it runs.
 - **FEAT**(storage): version persisted storage by namespace and purge records
   written by an older, unversioned client before the new epoch is created.
 - **FEAT**(diagnostics): add `DragonLogs.writeRecord` for one caller-sanitized
   JSON object per line, without legacy message or metadata decoration.
 - **FIX**(storage): serialize appends, snapshots, migrations and disposal
   behind one queue and a cross-process lock, using Web Locks in the browser.
 - **FEAT**(export): `DragonLogs.clearLogs` also removes cached exports.
 - **FIX**(export): keep the artefacts of a running export out of that clear.
   Writing and sharing deliberately run outside the storage queue, so a clear
   could otherwise delete the snapshot being read or the file being shared.
 - **FIX**(export): share native export ownership across storage instances in
   one isolate using canonical paths, and serialize snapshot cleanup with clear.
   Retention survives disposal; concurrent shares use separate cache directories.

## 2.0.1 — preparation history

 - **FIX**(web): improve wasm JS interop bindings (#315).
 - **FIX**(zhltc): zhltc activation fixes (#227).

## 2.0.0

> Note: This release has breaking changes.

 - **FIX**(deps): misc deps fixes.
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

## 1.2.1

> Note: This release has breaking changes.

 - **FIX**(deps): misc deps fixes.
 - **FIX**: unify+upgrade Dart/Flutter versions.
 - **FEAT**(rpc): trading-related RPCs/types (#191).
 - **BREAKING** **FEAT**: add Flutter Web WASM support with OPFS interop extensions (#176).
 - **BREAKING** **FEAT**: add dragon_logs package with Wasm-compatible logging.
 - **BREAKING** **CHORE**: unify Dart SDK (^3.9.0) and Flutter (>=3.35.0 <3.36.0) constraints across workspace.

## 1.2.0

- **BREAKING**: Add WASM web support with OPFS-only storage
- **BREAKING**: Remove `file_system_access_api` and `js` dependencies
- **BREAKING**: Require Dart SDK `>=3.3.0` for extension types support
- Add `package:web` for modern web APIs compatibility
- Migrate from `dart:html` and `dart:js` to `dart:js_interop` and `package:web`
- Add WASM-specific platform detection using `dart.tool.dart2wasm`
- Implement Origin Private File System (OPFS) using modern JS interop
- Maintain full API compatibility while supporting both regular web and WASM compilation

## 1.1.0

- Bump packages to latest versions.
- Apply new Dart format styling introduced in Dart `3.27`.

## 1.0.4

- Fix log message sorting bug. Thanks to @takenagain for their first contribution to this project.

## 1.0.2

- Bump `intl` dependency to latest version of `0.19.0`.

## 1.0.1

- Refactor to share more code with web and native platforms.
- Fix date parsing bug.
- Add public API to clear all logs.

Refactor to share more code between web and native platforms (focused mainly on file name and directory handling) and fix a bug where logs belonging to days with a single digit month or day could not be parsed.

## 1.0.0

- Stable release
- Tweak: Localisation initialisation no longer needs to be inialised before logs.

## 0.1.1-preview.1

- Memory improvement for log flushing.
- Bug fixes.

## 0.1.0-preview.1

- Bug fixes.

## 0.0.1-preview.1

- Initial preview version.
