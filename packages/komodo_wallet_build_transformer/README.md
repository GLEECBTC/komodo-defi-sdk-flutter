# Gleec Wallet Build Transformer

Flutter asset transformer and CLI to fetch KDF artifacts (binaries/WASM), coins config, seed nodes, and icons at build time, and to copy platform-specific assets.

This package powers the build hooks used by `komodo_defi_framework` and the SDK to make local (FFI/WASM) usage seamless.

## How it works

- Runs as a Flutter asset transformer via a special asset file entry
- Executes configured build steps:
  - `fetch_defi_api`: download KDF artifacts for target platforms
  - `fetch_coin_assets`: download coins list/config, seed nodes, and icons
  - `copy_platform_assets`: copy platform assets into the consuming app

## Add to your app’s pubspec

Add this under `flutter/assets`:

```yaml
flutter:
  assets:
    - assets/config/
    - assets/coin_icons/png/
    - app_build/build_config.json
    - path: assets/transformer_invoker.txt
      transformers:
        - package: komodo_wallet_build_transformer
          args:
            [
              --fetch_defi_api,
              --fetch_coin_assets,
              --copy_platform_assets,
              --artifact_output_package=komodo_defi_framework,
              --config_output_path=app_build/build_config.json,
            ]
```

Artifacts and checksums are configured in `packages/komodo_defi_framework/app_build/build_config.json`.

## CLI

You can run the transformer directly for local testing:

```sh
dart run packages/komodo_wallet_build_transformer/bin/komodo_wallet_build_transformer.dart \
  --all \
  --artifact_output_package=komodo_defi_framework \
  --config_output_path=app_build/build_config.json \
  -i /tmp/input_marker.txt -o /tmp/output_marker.txt
```

Flags:

- `--all` to run all steps, or select specific steps with:
  - `--fetch_defi_api`
  - `--fetch_coin_assets`
  - `--copy_platform_assets`
- `--artifact_output_package` The package receiving downloaded artifacts
- `--config_output_path` Path to config JSON relative to artifact package
- `-i/--input` and `-o/--output` Required by Flutter’s asset transformer interface
- `-l/--log_level` One of: `finest,finer,fine,config,info,warning,severe,shout`
- `-v/--verbose` Verbose output
- `--concurrent` Run steps concurrently when safe

Environment:

- `GITHUB_API_PUBLIC_READONLY_TOKEN` Optional; increases rate limits
- `OVERRIDE_DEFI_API_DOWNLOAD` Force `true` (always fetch) or `false` (always skip) regardless of state

## Troubleshooting

- Missing config: ensure the `--config_output_path` file exists in `artifact_output_package`
- CORS on Web: the KDF WASM and bootstrap files must be present under `web/kdf/bin` in the artifact package
- Checksums mismatch: update `build_config.json` to the new artifact checksums and commit hash

## License

MIT
