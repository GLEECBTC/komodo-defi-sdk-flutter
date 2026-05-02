# Testing

## Unit tests

From the package directory:

```bash
flutter test
```

- Uses Flutter test runner as preferred for this monorepo.

Run a specific test:

```bash
flutter test test/coin_config_repository_test.dart
```

Generate coverage:

```bash
flutter test --coverage
```

## Test utilities

- `test/hive/test_harness.dart`: sets up a temporary directory for Hive to ensure isolated and repeatable tests.
- `test/helpers/*`: asset factories and helpers.

## Mocking and fakes

- Use `mocktail` for HTTP client or provider fakes.
- Inject `http.Client` into `GithubCoinConfigProvider` and `AssetBundle` into
  `LocalAssetCoinConfigProvider` for deterministic responses.

## Integration tests

For app-level tests using this package, ensure `KomodoCoinUpdater.ensureInitialized`
points to a temp directory and that no real network calls are made unless
explicitly desired.
