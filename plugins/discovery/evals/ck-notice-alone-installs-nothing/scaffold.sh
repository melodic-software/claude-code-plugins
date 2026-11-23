#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p plugin
cp -R "$root/lib" "$root/prerequisites.json" plugin/
mkdir -p plugin/scripts
cp -R "$root/scripts/check-hook-registration.sh" plugin/scripts/check-hook-registration.sh
cp -R "$root/hooks" plugin/hooks
