#!/usr/bin/env bash
# A configured Python repo with an empty arid record.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" configured
mkdir -p .claude
cat >.claude/mutation-testing-arid.md <<'MD'
# Arid-node suppressions

```yaml
suppressions: {}
```
MD
git add -A
git commit -q -m "chore: mutation-testing records"
