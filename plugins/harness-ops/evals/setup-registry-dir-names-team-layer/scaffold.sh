#!/usr/bin/env bash
# A git repository whose team file sets registry_dir, so check has a team layer to report.
set -euo pipefail
git init -q -b main
mkdir -p docs/conventions tools/registry
printf 'registry_dir: tools/registry\n' >docs/conventions/harness-ops.yaml
printf '# demo\n' >README.md
