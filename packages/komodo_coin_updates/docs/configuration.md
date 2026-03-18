# Configuration reference

`RuntimeUpdateConfig` mirrors the `coins` section of `build_config.json` and
controls where and how coin data is fetched at runtime.

## Fields

- **fetchAtBuildEnabled** (bool, default: true): Whether build-time fetch is
  enabled.
- **updateCommitOnBuild** (bool, default: true): Whether to update the bundled
  commit at build time.
- **bundledCoinsRepoCommit** (String, default: `master`): Commit bundled with
  the app; used by `LocalAssetCoinConfigProvider`.
- **coinsRepoApiUrl** (String): GitHub API base URL.
- **coinsRepoContentUrl** (String): Raw content base URL.
- **coinsRepoBranch** (String, default: `master`): Branch to read.
- **runtimeUpdatesEnabled** (bool, default: true): Feature flag for runtime
  fetching.
- **mappedFiles** (Map<String, String>): Asset → repo path mapping.
  - `assets/config/coins_config.json` → path to unfiltered config JSON
  - `assets/config/coins.json` → path to `coins` folder
  - `assets/config/seed_nodes.json` → seed nodes JSON
- **mappedFolders** (Map<String, String>): Asset folder → repo folder mapping.
  - `assets/coin_icons/png/` → `icons`
- **concurrentDownloadsEnabled** (bool, default: false)
- **cdnBranchMirrors** (Map<String, String>): Branch → CDN base URL mapping.

## Examples

```dart
final config = AssetRuntimeUpdateConfig(
  coinsRepoBranch: 'master',
  mappedFiles: {
    'assets/config/coins_config.json': 'utils/coins_config_unfiltered.json',
    'assets/config/coins.json': 'coins',
  },
  cdnBranchMirrors: {
    'master': 'https://gleecbtc.github.io/coins',
  },
);
```

## GitHub authentication

To reduce rate limiting during `getLatestCommit`, pass a token to the
repository or provider constructor. For example:

```dart
final repo = CoinConfigRepository.withDefaults(
  config,
  githubToken: Platform.environment['GITHUB_TOKEN'],
);
```

## CDN mirrors

When a branch is present in `cdnBranchMirrors`, the content URL is constructed
from the CDN base without adding the branch segment.
