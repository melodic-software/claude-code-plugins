#!/usr/bin/env bash
# The checker at a path a committed prompt can name.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p plugin
cp -R "$root/lib" "$root/prerequisites.json" plugin/
# The probe reports biome only where a Biome config is (prerequisites.json when), so the notice
# above can only have fired in a repository that has one.
printf '{}\n' >biome.json
