#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-ledger-cli.sh"

mkdir -p docs/conventions
cat > docs/conventions/improvement.yaml <<'CONFIG'
churn_window: "30 days ago"
CONFIG
