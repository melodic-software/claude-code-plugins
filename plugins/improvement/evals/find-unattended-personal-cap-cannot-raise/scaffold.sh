#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"

mkdir -p docs/conventions
cat > docs/conventions/improvement.local.yaml <<'CONFIG'
find_open_item_cap: 9
CONFIG
