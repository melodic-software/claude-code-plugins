#!/usr/bin/env bash
# Seeds the hung inventory sync: its source at inventory/sync.py and its py-spy dump under dumps/.
set -euo pipefail

fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/scaffold-guard.sh" inventory dumps
mkdir -p inventory dumps
cat "${fixtures}/inventory/sync.py.txt" >inventory/sync.py
cat "${fixtures}/inventory-sync.pyspy-dump.txt" >dumps/inventory-sync.txt
