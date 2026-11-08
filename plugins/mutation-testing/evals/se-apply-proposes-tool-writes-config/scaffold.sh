#!/usr/bin/env bash
# A Python repo with no mutation-testing config.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" unconfigured
