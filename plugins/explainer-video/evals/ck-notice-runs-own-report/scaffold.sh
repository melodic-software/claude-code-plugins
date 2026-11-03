#!/usr/bin/env bash
# The plugin's report at a path a committed prompt can name.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p plugin
cp -R "$root/lib" "$root/scripts" "$root/prerequisites.json" plugin/
