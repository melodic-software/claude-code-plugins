#!/usr/bin/env bash
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" configured
printf '.claude/**/*.local.*\ndocs/conventions/**/*.local.*\n' >>.gitignore
git add -A
git commit -q -m "chore: ignore personal overrides"
mkdir -p .claude
cat >.claude/mutation-testing.local.md <<'MD'
# Personal mutation-testing override

```yaml
operators: narrow
```
MD
