# Komodo Coin Updates — Developer Docs

A developer-focused guide to building with and contributing to
`komodo_coin_updates`.

- **Package goals**: Retrieve, persist, and update Komodo coins configuration at
  runtime; expose parsed `Asset` models; track source commit for update checks.
- **Primary entrypoints**: `KomodoCoinUpdater`, `RuntimeUpdateConfig`,
  `CoinConfigRepository`, `GithubCoinConfigProvider`,
  `LocalAssetCoinConfigProvider`, `SeedNodeUpdater`.

## Table of contents

- Getting started: `getting-started.md`
- Usage guide: `usage.md`
- Configuration reference: `configuration.md`
- Providers: `providers.md`
- Storage details: `storage.md`
- Build and local development: `build-and-dev.md`
- Testing: `testing.md`
- Advanced topics (transforms, extending): `advanced.md`
- API docs (dartdoc): `api.md`
- FAQ and troubleshooting: `faq.md`

## Audience

- **Package developers**: Maintain and evolve the package.
- **Integrators**: Use the package in your app or SDK.

## Requirements

- Dart SDK ^3.8.1, Flutter >=3.29.0 <3.36.0
- Optional GitHub token to avoid API rate limits when calling GitHub REST API
- Hive storage path for runtime persistence
