#!/usr/bin/env bash
set -euo pipefail

fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/scaffold-guard.sh" inventory dumps
mkdir -p inventory dumps
cat "${fixtures}/inventory/sync.py.txt" >inventory/sync.py
cat "${fixtures}/inventory-sync.pyspy-dump.txt" >dumps/inventory-sync.txt
