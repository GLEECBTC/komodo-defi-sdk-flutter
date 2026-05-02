# Providers

Two provider implementations ship with the package.

## GithubCoinConfigProvider

- Reads the raw JSON map (`utils/coins_config_unfiltered.json`) and the `coins`
  directory from the Komodo `coins` repo.
- Applies configured transforms before parsing into `Asset` models.
- Supports authenticated GitHub API calls for `getLatestCommit`.
- CDN support via `cdnBranchMirrors`.

Constructor options:

```dart
GithubCoinConfigProvider(
  branch: 'master',
  coinsGithubContentUrl: 'https://raw.githubusercontent.com/GLEECBTC/coins',
  coinsGithubApiUrl: 'https://api.github.com/repos/GLEECBTC/coins',
  coinsPath: 'coins',
  coinsConfigPath: 'utils/coins_config_unfiltered.json',
  cdnBranchMirrors: {'master': 'https://gleecbtc.github.io/coins'},
  githubToken: envToken,
  transformer: const CoinConfigTransformer(),
);
```

From config:

```dart
final provider = GithubCoinConfigProvider.fromConfig(
  config,
  githubToken: envToken,
);
```

## LocalAssetCoinConfigProvider

- Loads the coins config from an asset bundled with your app.
- Forwards the JSON through the transform pipeline before parsing.

From config:

```dart
final provider = LocalAssetCoinConfigProvider.fromConfig(
  config,
  packageName: 'komodo_defi_framework',
);
```

## Testing providers

- Inject `http.Client` in GitHub provider and `AssetBundle` in local provider to
  supply fakes/mocks in tests.
