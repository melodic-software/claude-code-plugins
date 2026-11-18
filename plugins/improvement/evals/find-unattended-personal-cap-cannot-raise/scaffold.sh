#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"

mkdir -p .claude
cat > .claude/improvement.local.md <<'CONFIG'
# personal improvement config

```yaml
find_open_item_cap: 9
```
CONFIG
