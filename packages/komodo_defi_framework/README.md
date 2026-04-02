# Komodo DeFi Framework (Flutter)

Low-level Flutter client for the Komodo DeFi Framework (KDF). This package powers the high-level SDK and can also be used directly for custom integrations or infrastructure tooling.

It supports multiple backends:

- Local Native (FFI) on desktop/mobile
- Local Web (WASM) in the browser
- Remote RPC (connect to an external KDF node)

## Install

```sh
flutter pub add komodo_defi_framework
```

## Create a client

```dart
import 'package:komodo_defi_framework/komodo_defi_framework.dart';

// Local (FFI/WASM)
final framework = KomodoDefiFramework.create(
  hostConfig: LocalConfig(https: false, rpcPassword: 'your-secure-password'),
  externalLogger: print, // optional
);

// Or remote
final remote = KomodoDefiFramework.create(
  hostConfig: RemoteConfig(
    ipAddress: 'example.org',
    port: 7783,
    rpcPassword: '...',
    https: true,
  ),
);
```

## Starting and stopping KDF (local mode)

```dart
// Build a startup configuration (no wallet, for diagnostics)
final startup = await KdfStartupConfig.noAuthStartup(
  rpcPassword: 'your-secure-password',
);

final result = await framework.startKdf(startup);
if (!result.isStartingOrAlreadyRunning()) {
  throw StateError('Failed to start KDF: $result');
}

final status = await framework.kdfMainStatus();
final version = await framework.version();

await framework.kdfStop();
```

## Direct RPC access

The framework exposes `ApiClient` with typed RPC namespaces:

```dart
final client = framework.client;
final balance = await client.rpc.wallet.myBalance(coin: 'KMD');
final check = await client.rpc.address.validateAddress(
  coin: 'BTC',
  address: 'bc1q...',
);
```

## Logging

- Pass `externalLogger: print` when creating the framework to receive log lines
- Toggle verbosity via `KdfLoggingConfig.verboseLogging = true`
- Listen to `framework.logStream`

## Seed nodes and P2P

From KDF v2.5.0-beta, seed nodes are required unless P2P is disabled. Use `SeedNodeService.fetchSeedNodes()` to fetch defaults and `SeedNodeValidator.validate(...)` to validate your config. Errors are thrown for invalid combinations (e.g., bootstrap without seed, disable P2P with seed nodes, etc.).

## Build artifacts and coins at build time

This package integrates with a Flutter asset transformer to fetch the correct KDF binaries, coins, seed nodes, and icons at build time. Add the following to your app’s `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/config/
    - assets/coin_icons/png/
    - app_build/build_config.json
    - path: assets/transformer_invoker.txt
      transformers:
        - package: komodo_wallet_build_transformer
          args:
            [
              --fetch_defi_api,
              --fetch_coin_assets,
              --copy_platform_assets,
              --artifact_output_package=komodo_defi_framework,
              --config_output_path=app_build/build_config.json,
            ]
```

You can customize sources and checksums via `app_build/build_config.json` in this package. See `packages/komodo_wallet_build_transformer/README.md` for CLI flags, environment variables, and troubleshooting.

On macOS, the build pipeline accepts both release-style static archives
(`libkdf-macos-universal2-<hash>.zip`) and CI-style executable archives
(`kdf-macos-universal2-<hash>.zip`). The transformer normalizes them into the
package layout consumed by the plugin podspec before Xcode builds.

## Web (WASM)

On Web, the plugin registers a WASM implementation automatically (see `lib/web/kdf_plugin_web.dart`). The WASM bundle and bootstrap scripts are provided via the build transformer.

## APIs and enums

- `IKdfHostConfig` with `LocalConfig`, `RemoteConfig` (and WIP: `AwsConfig`, `DigitalOceanConfig`)
- `KdfStartupConfig` helpers: `generateWithDefaults(...)`, `noAuthStartup(...)`
- Lifecycle: `startKdf`, `kdfMainStatus`, `kdfStop`, `version`, `logStream`
- Errors: `JsonRpcErrorResponse`, `ConnectionError`

## License

MIT
