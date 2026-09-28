#!/usr/bin/env bash
# Contract tests for the csharp-ls Windows launcher.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node is not on PATH"
  exit 0
fi
node "$here/launch-csharp-ls.test.mjs"
