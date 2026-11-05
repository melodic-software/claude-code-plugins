#!/usr/bin/env bash
# A git repository with no hook log root yet, so check has a guard row to report and nothing to migrate.
set -euo pipefail
git init -q -b main
printf '# demo\n' >README.md
