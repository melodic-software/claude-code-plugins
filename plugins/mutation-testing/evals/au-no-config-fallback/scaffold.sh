#!/usr/bin/env bash
# A Python repo with no mutation-testing config whose feature branch moves the free-shipping threshold.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" unconfigured
