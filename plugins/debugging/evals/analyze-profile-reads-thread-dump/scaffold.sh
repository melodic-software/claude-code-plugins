#!/usr/bin/env bash
# Seeds the hung inventory sync: its source at inventory/sync.py and its py-spy dump under dumps/.
set -euo pipefail

fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/analyze-profile/evals/fixtures" && pwd)"
mkdir -p inventory dumps
cp "$fixtures/inventory/sync.py.txt" inventory/sync.py
cp "$fixtures/inventory-sync.pyspy-dump.txt" dumps/inventory-sync.txt
