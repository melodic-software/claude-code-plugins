#!/usr/bin/env bash
# Seeds the ledger-cli repository with only the new team file, docs/conventions/improvement.yaml,
# and no old .claude/improvement.md or .claude/improvement.local.md.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-ledger-cli.sh"

mkdir -p docs/conventions
cat > docs/conventions/improvement.yaml <<'CONFIG'
churn_window: "30 days ago"
CONFIG
