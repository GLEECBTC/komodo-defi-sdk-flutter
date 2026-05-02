# Storage details

This package uses Hive CE for local persistence of parsed coin `Asset` models
and associated metadata (the source commit hash).

## Boxes and keys

- **assets**: `LazyBox<Asset>` containing parsed coin assets keyed by
  `AssetId.id`.
- **coins_settings**: `Box<String>` containing metadata.
  - `coins_commit`: the commit hash the assets were sourced from.

These defaults can be customized via `CoinConfigRepository` constructor:

```dart
final repo = CoinConfigRepository(
  coinConfigProvider: GithubCoinConfigProvider.fromConfig(config),
  assetsBoxName: 'assets',
  settingsBoxName: 'coins_settings',
  coinsCommitKey: 'coins_commit',
);
```

## Initialization

Call once at startup:

```dart
await KomodoCoinUpdater.ensureInitialized(appStoragePath);
```

For isolates:

```dart
KomodoCoinUpdater.ensureInitializedIsolate(fullAppFolderPath);
```

## CRUD operations

```dart
final assets = await repo.getAssets(excludedAssets: ['BTC']);
final kmd = await repo.getAsset(AssetId.parse({'coin': 'KMD'}));
final isLatest = await repo.isLatestCommit();
final currentCommit = await repo.getCurrentCommit();

await repo.upsertAssets(assets, 'abcdef');
await repo.deleteAsset(AssetId.parse({'coin': 'KMD'}));
await repo.deleteAllAssets();
```

## Migrations and data lifecycle

- Boxes are opened lazily; first access creates them.
- Deleting all assets also clears the stored commit key.
- Consider providing an in-app "Reset coins data" action that calls
  `deleteAllAssets()`.

## Data model

- `Asset` and `AssetId` are defined in `komodo_defi_types` and used as the
  persisted types. Each coin may expand to multiple `AssetId`s (e.g. child
  assets) and each is stored individually keyed by its `AssetId.id`.
