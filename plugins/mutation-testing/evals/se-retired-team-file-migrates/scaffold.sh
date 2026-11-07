#!/usr/bin/env bash
# A Python repo configured only by the retired .claude/mutation-testing.md.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" unconfigured
mkdir -p .claude
cat >.claude/mutation-testing.md <<'MD'
# Mutation testing

```yaml
tool: manual
diff-target: main
mutate: ["src/**/*.py"]
operators: narrow
max-mutants: 12
```
MD
git add -A
git commit -q -m "chore: mutation-testing records"
