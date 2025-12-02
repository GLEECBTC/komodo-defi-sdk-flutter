# Gleec Wallet CLI

Developer CLI wrapper for Gleec wallet tooling. Currently forwards to the build transformer to simplify local usage.

## Install

Run directly via Dart:

```sh
dart run packages/komodo_wallet_cli/bin/komodo_wallet_cli.dart --help
```

## Commands

### 1) Build transformer wrapper (`get`)

Runs the build transformer to fetch KDF artifacts (binaries/WASM), coins config, seed nodes, and icons, and to copy platform assets.

Example:

```sh
dart run packages/komodo_wallet_cli/bin/komodo_wallet_cli.dart get \
  --all \
  --artifact_output_package=komodo_defi_framework \
  --config_output_path=app_build/build_config.json \
  -i /tmp/input_marker.txt -o /tmp/output_marker.txt
```

Flags (proxied to build transformer):

- `--all` – Run all steps
- `--fetch_defi_api` – Fetch KDF artifacts
- `--fetch_coin_assets` – Fetch coins list/config, seed nodes, icons
- `--copy_platform_assets` – Copy platform assets into the app
- `--artifact_output_package=<pkg>` – Target package for artifacts
- `--config_output_path=<rel path>` – Path to build config in target package
- `-i/--input` and `-o/--output` – Required by Flutter asset transformers
- `-l/--log_level=finest|...` – Verbosity
- `--concurrent` – Run steps concurrently

Notes:

- Set `GITHUB_API_PUBLIC_READONLY_TOKEN` to increase GitHub API rate limits
- `OVERRIDE_DEFI_API_DOWNLOAD=true|false` can force update/skip at build time

### 2) Update API config (`update_api_config` executable)

Fetches the latest commit from a branch (GitHub or mirror), locates matching artifacts, computes their SHA-256 checksums, and updates the build config JSON in place. Use when bumping the KDF artifact version/checksums.

Run (direct):

```sh
dart run packages/komodo_wallet_cli/bin/update_api_config.dart \
  --branch dev \
  --source mirror \
  --config packages/komodo_defi_framework/app_build/build_config.json \
  --output-dir packages/komodo_defi_framework/app_build/temp_downloads \
  --verbose
```

If activated globally:

```sh
komodo_wallet_cli update_api_config --branch dev --source mirror --config packages/komodo_defi_framework/app_build/build_config.json
```

Options:

- `-b, --branch <name>` – Branch to fetch commit from (default: master)
- `--repo <owner/repo>` – Repository (default: GLEECBTC/komodo-defi-framework)
- `-c, --config <path>` – Path to build_config.json (default: build_config.json)
- `-o, --output-dir <dir>` – Temp download dir (default: temp_downloads)
- `-t, --token <token>` – GitHub token (or env `GITHUB_API_PUBLIC_READONLY_TOKEN`)
- `-p, --platform <name|all>` – Specific platform to update or `all` (default: all)
- `-s, --source <github|mirror>` – Source for artifacts (default: github)
- `--mirror-url <url>` – Mirror base URL (default: https://sdk.devbuilds.komodo.earth)
- `-v, --verbose` – Verbose logging
- `-h, --help` – Show help

### 3) Upgrade nested Flutter projects (`flutter_upgrade_nested` executable)

Recursively finds Flutter projects (by `pubspec.yaml`) and runs `flutter pub upgrade` in each.

Run:

```sh
flutter_upgrade_nested --dir /path/to/projects --major-versions --unlock-transitive
```

Options:

- `-d, --dir <path>` – Root directory to search (default: current directory)
- `-m, --major-versions` – Allow major version upgrades
- `-t, --unlock-transitive` – Allow upgrading transitive dependencies
- `-h, --help` – Show help

Use `-v/--verbose` (where available) for additional output.

## License

MIT
