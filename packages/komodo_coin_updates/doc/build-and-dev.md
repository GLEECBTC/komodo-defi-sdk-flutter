# Build and local development

This package uses code generation for Freezed, JSON serialization, Hive CE
adapters, and index barrels.

## Setup

- Ensure you have a suitable Flutter SDK (via FVM if you prefer).
- From the repo root or package directory, run `flutter pub get`.

## Code generation

From the package directory:

```bash
dart run build_runner build -d
```

- Regenerates Freezed (`*.freezed.dart`), JSON (`*.g.dart`), and Hive
  adapters.

Generate index barrels:

```bash
dart run index_generator
```

- Uses `index_generator.yaml` to keep `lib/src/**/_index.dart` files up to date.

## Analyze

```bash
dart analyze .
```

- Uses `very_good_analysis` and `lints` rules.

## Running example/tests locally

See `testing.md` for running tests. You can also create a quick integration in
`playground/` or your own app by following `getting-started.md`.

## Publishing

`pubspec.yaml` sets `publish_to: none` for internal development. To publish
externally, you would need to remove that and ensure dependencies meet pub
constraints.
