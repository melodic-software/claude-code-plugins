#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"

mkdir -p .claude
cat > .claude/improvement.md <<'CONFIG'
# improvement config

```yaml
find_run_item_cap: 1
```
CONFIG
