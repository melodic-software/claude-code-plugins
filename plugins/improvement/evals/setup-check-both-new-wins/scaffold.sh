#!/usr/bin/env bash
# Seeds the ledger-cli repository with both team files: the new docs/conventions/improvement.yaml
# (churn_window 30 days ago) and the old .claude/improvement.md (churn_window 180 days ago plus
# find_size_band small, a key the new file does not set).
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-ledger-cli.sh"

mkdir -p docs/conventions .claude
cat > docs/conventions/improvement.yaml <<'CONFIG'
churn_window: "30 days ago"
CONFIG
cat > .claude/improvement.md <<'CONFIG'
# improvement config

```yaml
churn_window: "180 days ago"
find_size_band: small
```
CONFIG
