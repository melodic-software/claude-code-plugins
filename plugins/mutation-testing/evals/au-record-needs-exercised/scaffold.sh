#!/usr/bin/env bash
# The exercised-scope repo: app.py on main, scenario boundary (committed).
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-exercised.sh" boundary committed
