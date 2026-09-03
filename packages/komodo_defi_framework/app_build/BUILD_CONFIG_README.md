# Build Config Guide

This directory contains the artifact configuration used by `komodo_wallet_build_transformer` to fetch KDF binaries/WASM and coin assets at build time.

## Files

- `build_config.json` – canonical configuration used by the transformer
- `build_config.yaml` – reference YAML form (not currently consumed by the tool)

## Key fields (JSON)

- `api.api_commit_hash` – commit hash of the KDF artifacts to fetch
- `api.require_full_commit_hash` – reject short or symbolic release pins
- `api.required_platforms` – platforms that must have explicit manifest entries
- `api.source_urls` – list of base URLs to download from (GitHub API, CDN)
- `api.platforms.*.matching_pattern` – regex to match artifact names per platform
- `api.platforms.*.valid_zip_sha256_checksums` – allow-list of artifact checksums
- `api.platforms.*.path` – destination relative to artifact output package
- `coins.bundled_coins_repo_commit` – commit of Komodo coins registry
- `coins.mapped_files` – mapping of output paths to source files in coins repo
- `coins.mapped_folders` – mapping of output dirs to repo folders (e.g. icons)

## Where artifacts are stored

Artifacts are downloaded into the package specified by the transformer flag:

```
--artifact_output_package=komodo_defi_framework
```

Paths in the config are relative to that package directory.

## Updating artifacts

1. Run the strict config updater against the branch-scoped build mirror with an
   exact full commit. It downloads every required platform archive, calculates
   SHA-256 locally, and replaces the manifest allow-lists:

   ```sh
   dart run packages/komodo_wallet_cli/bin/update_api_config.dart \
     --branch feat/tron-gasfree \
     --commit bd413dcfea73c9de2e85903323946a378b180fa7 \
     --source mirror \
     --mirror-url https://devbuilds.gleec.com \
     --platform all \
     --config packages/komodo_defi_framework/app_build/build_config.json \
     --output-dir packages/komodo_defi_framework/app_build/temp_downloads \
     --strict \
     --verbose
   ```

2. Compare the calculated values with each archive's individual `.sha256`
   sidecar. Do not use the mirror's aggregate `SHA256SUMS` file as a release
   authority.
3. Synchronize this directory's reference YAML with the canonical JSON.
4. Run the build transformer (via Flutter asset transformers or CLI). It writes
   an `.api_last_updated_<platform>` marker containing the exact archive name,
   accepted archive SHA-256, manifest checksums, extracted core-artifact
   SHA-256, and complete runtime-set SHA-256 for every platform.
5. Confirm the marker's commit and checksum match the manifest before packaging.
   Future builds recompute both extracted digests; legacy, incomplete, missing,
   or tampered markers are stale and cannot be bypassed by disabling downloads.

`OVERRIDE_DEFI_API_DOWNLOAD=false` disables downloading only. It cannot bypass
provenance validation: a missing, malformed, stale-commit, or checksum-mismatched
marker still fails the build.

Android CMake recalculates `libkdf.a` SHA-256 and compares it with that marker,
so changing or relabelling an extracted library also fails before linking.

## Tips

- Set `GITHUB_API_PUBLIC_READONLY_TOKEN` to increase GitHub API rate limits
- Use `--concurrent` for faster downloads in development
- Override behavior per build via env `OVERRIDE_DEFI_API_DOWNLOAD=true|false`

### Official build mirrors

The committed `api.source_urls` must contain only the official KDF mirrors,
Devbuilds and Nebula, in this fallback order:

```
"source_urls": [
    "https://devbuilds.gleec.com",
    "https://nebula.decker.im"
]
```

- A `https://api.github.com/repos/<owner>/<repo>` entry selects the GitHub
  release downloader instead of a mirror. KDF now lives in the private
  `GLEECBTC/kdf-internal`, whose branches are not reachable without a token, so
  no GitHub entry is configured by default.

- The downloader expects branch-scoped directory listings (e.g.,
  `.../dev/`) on both devbuilds and Nebula mirrors and falls back to the base
  listing when available. Archive names may contain the full commit or its
  seven-character prefix, but `api.api_commit_hash` must remain the resolved
  full 40-character lowercase SHA.
- To pin a specific commit without changing branches, use the strict updater
  with its full SHA:

```bash
dart run packages/komodo_wallet_cli/bin/update_api_config.dart \
  --source mirror \
  --mirror-url https://nebula.decker.im \
  --commit bd413dcfea73c9de2e85903323946a378b180fa7 \
  --config packages/komodo_defi_framework/app_build/build_config.json \
  --output-dir packages/komodo_defi_framework/app_build/temp_downloads \
  --strict \
  --verbose
```

- To switch commits, rerun the updater with a different full `--commit <sha>`.
  Do not hand-edit a short hash into the canonical manifest.

Notes:
- Nebula index includes additional files like `komodo-wallet-*`; these are automatically ignored by the downloader.
- macOS on Nebula uses `kdf-macos-universal2-<hash>.zip` (special case handled in `matching_pattern`). Other platforms use `kdf_<hash>-<platform>.zip`.

## Troubleshooting

- Missing files: verify `config_output_path` points to this folder and the file exists
- Checksum mismatch: update checksums to match newly published artifacts
- Web CORS: ensure WASM bundle and bootstrap JS are present under `web/kdf/bin`
