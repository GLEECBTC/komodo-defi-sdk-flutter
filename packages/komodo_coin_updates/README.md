# Komodo Coin Updates

Utilities for retrieving, storing, and updating the Komodo coins configuration at runtime.

This package fetches the unified coins configuration JSON from the `GLEECBTC/coins` repository (`utils/coins_config_unfiltered.json` by default), converts entries into `Asset` models (from `komodo_defi_types`), persists them to Hive, and tracks the source commit so you can decide when to refresh.

## Features

- Fetch latest commit from the `GLEECBTC/coins` repo
- Retrieve the latest coins_config JSON and parse to strongly-typed `Asset` models
- Persist assets in Hive (`assets` lazy box) and store the current commit hash in `coins_settings`
- Check whether the stored commit is up to date and update when needed
- Configurable repo URLs, branch/commit, CDN mirrors, and optional GitHub token
- Initialize in the main isolate or a background isolate

## Installation

Preferred (adds the latest compatible version):

```sh
dart pub add komodo_coin_updates
```

Or manually in `pubspec.yaml`:

```yaml
dependencies:
  komodo_coin_updates: ^latest
```

Then import:

```dart
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
```

## Quick start (standalone)

1. Initialize Hive storage (only once, early in app startup):

```dart
await KomodoCoinUpdater.ensureInitialized(appSupportDirPath);
```

1. Provide runtime update configuration (derive from build / environment):

```dart
final config = AssetRuntimeUpdateConfig(
  fetchAtBuildEnabled: false,
  updateCommitOnBuild: false,
  bundledCoinsRepoCommit: 'abcdef123456',
  coinsRepoApiUrl: 'https://api.github.com/repos/GLEECBTC/coins',
  coinsRepoContentUrl: 'https://raw.githubusercontent.com/GLEECBTC/coins',
  coinsRepoBranch: 'master',
  runtimeUpdatesEnabled: true,
  mappedFiles: {
    // App asset → Repo path (used to locate coins_config in the repo)
    'assets/config/coins_config.json': 'utils/coins_config_unfiltered.json',
    'assets/config/coins.json': 'coins',
  },
  mappedFolders: {},
  concurrentDownloadsEnabled: true,
  cdnBranchMirrors: {},
);
```

1. Create a repository with sensible defaults and use it to load/update data:

```dart
final repo = CoinConfigRepository.withDefaults(
  config,
  githubToken: String.fromEnvironment('GITHUB_TOKEN', defaultValue: ''),
);

// First-run or app start logic
if (await repo.coinConfigExists()) {
  final isUpToDate = await repo.isLatestCommit();
  if (!isUpToDate) {
    await repo.updateCoinConfig();
  }
} else {
  await repo.updateCoinConfig();
}

final assets = await repo.getAssets(); // List<Asset>
```

## Using via the SDK (recommended)

In most apps you shouldn't call `KomodoCoinUpdater.ensureInitialized` directly. Instead use the high-level SDK which initializes both `komodo_coins` (parses bundled config) and `komodo_coin_updates` (runtime updates) for you.

```dart
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';

Future<void> main() async {
  final sdk = await KomodoDefiSdk.init(
    // optional: pass configuration enabling runtime updates; otherwise defaults used
  );

  // Access unified assets view (naming subject to SDK API)
  final assets = sdk.assets; // e.g., List<Asset> or repository wrapper

  // If runtime updates are enabled, assets may refresh automatically or via explicit call:
  // await sdk.assetsRepository.checkForUpdates(); // (example – confirm actual method name)
}
```

Benefits of using the SDK layer:

- Single initialization call (`KomodoDefiSdk.init()`) sets up storage, coins, and updates
- Consistent filtering / ordering across packages
- Centralized error handling, logging, and update strategies
- Future-proof: interface adjustments propagate through the SDK

Use the standalone package only if you have a very narrow need (e.g., a CLI or build script) and don't want the full SDK dependency.

## Provider-only usage

If you only need to fetch from the repo without persistence:

```dart
// Direct provider construction
final provider = LocalAssetCoinConfigProvider.fromConfig(config);
final latestCommit = await provider.getLatestCommit();
final latestAssets = await provider.getLatestAssets();

// Or using the factory pattern
final factory = const DefaultCoinConfigDataFactory();
final provider = factory.createLocalProvider(config);
final latestCommit = await provider.getLatestCommit();
final latestAssets = await provider.getLatestAssets();
```

## Notes

- `KomodoCoinUpdater.ensureInitializedIsolate(fullPath)` is available for background isolates; call it before accessing Hive boxes there.
- The repository persists `Asset` models in a lazy box (default name `assets`) and tracks the upstream commit in `coins_settings`.
- Enable concurrency via `concurrentDownloadsEnabled: true` for faster large updates (ensure acceptable for your platform & network conditions).

- The package reads from `utils/coins_config_unfiltered.json` by default. You can override this via `AssetRuntimeUpdateConfig.mappedFiles['assets/config/coins_config.json']`.
- Assets are stored in a Hive lazy box named `assets`; the current commit hash is stored in a box named `coins_settings` with key `coins_commit`.
- Provide a GitHub token to reduce the likelihood of rate limiting when calling the GitHub API for commit information.

## License

MIT
