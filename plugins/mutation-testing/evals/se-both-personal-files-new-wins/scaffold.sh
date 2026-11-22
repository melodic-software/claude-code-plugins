#!/usr/bin/env bash
# A configured Python repo with a personal override at both the old and the new location.
# The new file sets operators; the old one sets operators and max-mutants.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" configured
printf '.claude/**/*.local.*\ndocs/conventions/**/*.local.*\n' >>.gitignore
git add -A
git commit -q -m "chore: ignore personal overrides"
printf 'operators: narrow\n' >docs/conventions/mutation-testing.local.yaml
mkdir -p .claude
cat >.claude/mutation-testing.local.md <<'MD'
# Personal mutation-testing override

```yaml
operators: default
max-mutants: 3
```
MD
