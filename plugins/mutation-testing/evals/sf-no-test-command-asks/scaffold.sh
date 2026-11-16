#!/usr/bin/env bash
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" unconfigured
