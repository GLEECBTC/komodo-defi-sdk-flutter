# Getting started

This guide helps you set up `komodo_coin_updates` in a Flutter/Dart app or
SDK and load the latest Komodo coins configuration at runtime.

## Prerequisites

- Dart SDK ^3.8.1
- Flutter >=3.29.0 <3.36.0
- Access to a writable app data folder for Hive
- Optional: GitHub token to reduce API rate limiting

## Install

Add the dependency. If you are using this package inside this monorepo, it's
already referenced via a relative path. For external usage, add a Git
dependency or path dependency as appropriate.

```bash
dart pub add komodo_coin_updates
```

Import the library:

```dart
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
```

## Initialize storage (once at startup)

```dart
await KomodoCoinUpdater.ensureInitialized(appStoragePath);
```

Use `ensureInitializedIsolate(fullPath)` inside background isolates.

## Provide runtime configuration

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
    'assets/config/coins_config.json': 'utils/coins_config_unfiltered.json',
    'assets/config/coins.json': 'coins',
    'assets/config/seed_nodes.json': 'seed-nodes.json',
  },
  mappedFolders: {
    'assets/coin_icons/png/': 'icons',
  },
  concurrentDownloadsEnabled: true,
  cdnBranchMirrors: {
    'master': 'https://gleecbtc.github.io/coins',
  },
);
```

## Fetch and persist assets

```dart
final repo = CoinConfigRepository.withDefaults(
  config,
  githubToken: String.fromEnvironment('GITHUB_TOKEN', defaultValue: ''),
);

if (await repo.coinConfigExists()) {
  final upToDate = await repo.isLatestCommit();
  if (!upToDate) await repo.updateCoinConfig();
} else {
  await repo.updateCoinConfig();
}

final assets = await repo.getAssets();
```

## Provider-only usage

If you just need to fetch without storing in Hive:

```dart
final provider = GithubCoinConfigProvider.fromConfig(config,
  githubToken: String.fromEnvironment('GITHUB_TOKEN', defaultValue: ''),
);
final latestCommit = await provider.getLatestCommit();
final latestAssets = await provider.getAssetsForCommit(latestCommit);
```

See `usage.md` for more patterns and `configuration.md` for all options.
