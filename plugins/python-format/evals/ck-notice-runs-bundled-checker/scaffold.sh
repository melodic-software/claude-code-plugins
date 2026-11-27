#!/usr/bin/env bash
# The checker at a path a committed prompt can name.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p plugin
cp -R "$root/lib" "$root/prerequisites.json" plugin/
printf 'line-length = 88\n' >ruff.toml
