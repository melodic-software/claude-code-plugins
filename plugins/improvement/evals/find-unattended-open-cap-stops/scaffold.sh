#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"

mkdir -p .claude
cat > .claude/improvement.md <<'CONFIG'
# improvement config

```yaml
churn_window: "90 days ago"
```
CONFIG

git init -q -b main
git add -A
git -c user.name=Checkout -c user.email=checkout@example.invalid -c commit.gpgsign=false \
  commit -q -m "Add checkout service"
