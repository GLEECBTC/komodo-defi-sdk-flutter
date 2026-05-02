# Usage guide

## Initialize Hive once

```dart
await KomodoCoinUpdater.ensureInitialized(appStoragePath);
```

- For isolates: `KomodoCoinUpdater.ensureInitializedIsolate(fullAppFolderPath)`.

## Create a repository with sane defaults

```dart
final repo = CoinConfigRepository.withDefaults(
  config,
  githubToken: String.fromEnvironment('GITHUB_TOKEN', defaultValue: ''),
);
```

- Uses `GithubCoinConfigProvider.fromConfig` under the hood.
- Stores `Asset` models in `assets` lazy box and commit in `coins_settings` box.

## First-run and update flow

```dart
if (await repo.coinConfigExists()) {
  final upToDate = await repo.isLatestCommit();
  if (!upToDate) await repo.updateCoinConfig();
} else {
  await repo.updateCoinConfig();
}
```

## Reading assets

```dart
final assets = await repo.getAssets();
final kmd = await repo.getAsset(AssetId.parse({'coin': 'KMD'}));
```

- Use `excludedAssets` to skip specific tickers: `getAssets(excludedAssets: ['BTC'])`.

## Provider-only retrieval

```dart
final provider = GithubCoinConfigProvider.fromConfig(config,
  githubToken: String.fromEnvironment('GITHUB_TOKEN', defaultValue: ''),
);
final commit = await provider.getLatestCommit();
final assets = await provider.getAssetsForCommit(commit);
```

## Local-asset provider

```dart
final provider = LocalAssetCoinConfigProvider.fromConfig(config,
  packageName: 'komodo_defi_framework',
);
final assets = await provider.getAssets();
```

## Seed nodes

```dart
const config = AssetRuntimeUpdateConfig();
final result = await SeedNodeUpdater.fetchSeedNodes(config: config);
final seedNodes = result.seedNodes;
final netId = result.netId;
final asStrings = SeedNodeUpdater.seedNodesToStringList(seedNodes);
```

- Web filters to WSS-only seed nodes automatically.

## Deleting data

```dart
await repo.deleteAsset(AssetId.parse({'coin': 'KMD'}));
await repo.deleteAllAssets();
```

## Logging

Set `Logger.root.level = Level.FINE;` and add a handler to see debug logs from
`CoinConfigRepository` and providers.
