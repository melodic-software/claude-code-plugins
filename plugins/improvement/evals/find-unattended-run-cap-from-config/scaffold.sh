#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"

mkdir -p docs/conventions
cat > docs/conventions/improvement.yaml <<'CONFIG'
find_run_item_cap: 1
CONFIG
