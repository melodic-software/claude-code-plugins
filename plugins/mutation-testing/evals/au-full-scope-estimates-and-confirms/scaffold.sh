#!/usr/bin/env bash
# A configured Python repo (tool: manual, test-command set) whose feature branch moves the free-shipping threshold.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" configured
