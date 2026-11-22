#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-ledger-cli.sh"

mkdir -p .claude
cat > .claude/improvement.md <<'CONFIG'
# improvement config

```yaml
churn_window: "30 days ago"
```
CONFIG
cat > .claude/improvement.local.md <<'CONFIG'
# improvement personal config

```yaml
find_size_band: small
```
CONFIG
