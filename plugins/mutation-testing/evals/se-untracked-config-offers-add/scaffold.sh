#!/usr/bin/env bash
# A Python repo whose config and arid record exist on disk, untracked and not ignored.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" unconfigured
mkdir -p docs/conventions
cat >docs/conventions/mutation-testing.yaml <<'YAML'
tool: manual
diff-target: main
mutate:
  - 'src/**/*.py'
test-command: 'python3 -m unittest {tests}'
YAML
mkdir -p .claude
cat >.claude/mutation-testing-arid.md <<'MD'
# Arid-node suppressions

```yaml
suppressions: {}
```
MD
