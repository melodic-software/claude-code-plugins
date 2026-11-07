#!/usr/bin/env bash
# The exercised-scope repo: app.py on main, scenario no_assertion (committed).
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-exercised.sh" no_assertion committed
