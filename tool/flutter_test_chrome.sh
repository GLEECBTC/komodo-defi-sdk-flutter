#!/usr/bin/env bash
set -euo pipefail

# Flutter's Wasm test loader needs WebGL. Opt into software rendering for the
# isolated headless test profile; newer Chrome versions disable it by default.
exec "${FLUTTER_TEST_CHROME_BINARY:-google-chrome}" \
  --enable-unsafe-swiftshader "$@"
