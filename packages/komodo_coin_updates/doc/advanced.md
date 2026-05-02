# Advanced topics

<!-- markdownlint-disable MD013 -->

## Transform pipeline

Raw coin JSON entries are processed through a transform pipeline before parsing
into `Asset` models.

Built-in transforms:

- `WssWebsocketTransform`: Filters Electrum servers to WSS-only on web and
  non-WSS on native platforms; normalizes `ws_url` fields.
- `ParentCoinTransform`: Remaps `parent_coin` to a concrete parent (e.g.
  `SLP` → `BCH`).

Provide a custom transformer:

```dart
class RemoveCoinX implements CoinConfigTransform {
  @override
  bool needsTransform(JsonMap config) => config['coin'] == 'COINX';

  @override
  JsonMap transform(JsonMap config) {
    // mark as filtered by adding a property consumed by a later filter step
    return JsonMap.of(config)..['__remove__'] = true;
  }
}

final transformer = CoinConfigTransformer(
  transforms: [const WssWebsocketTransform(), const ParentCoinTransform(), RemoveCoinX()],
);

final repo = CoinConfigRepository.withDefaults(config, transformer: transformer);
```

## Custom providers

Implement `CoinConfigProvider` to source data from anywhere:

```dart
class MyProvider implements CoinConfigProvider {
  @override
  Future<List<Asset>> getAssetsForCommit(String commit) async { /* ... */ }

  @override
  Future<List<Asset>> getAssets({String? branch}) async { /* ... */ }

  @override
  Future<String> getLatestCommit({String? branch, String? apiBaseUrl, String? githubToken}) async {
    return 'custom-ref';
  }
}
```

Use with the repository:

```dart
final repo = CoinConfigRepository(coinConfigProvider: MyProvider());
```

## Filtering coins

`CoinFilter` removes entries based on protocol type/subtype and a few specific
rules. To customize, prefer adding a transform that modifies or removes entries
before parsing.

## Seed nodes

`SeedNodeUpdater.fetchSeedNodes()` fetches from `seed-nodes.json` (CDN) and
filters by `kDefaultNetId` and optionally WSS on web. Convert to string list
with `seedNodesToStringList`.
