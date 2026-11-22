#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"

# An old-location team file, read through the dual-read window. It sets only the default
# churn window, so the open cap stays at its default of 5.
mkdir -p .claude
cat > .claude/improvement.md <<'CONFIG'
# improvement config

```yaml
churn_window: "90 days ago"
```
CONFIG
