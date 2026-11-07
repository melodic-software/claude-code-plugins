#!/usr/bin/env bash
# A configured Python repo with an empty team arid record and one personal entry.
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
printf '*.local.md\n' >>.gitignore
git add -A
git commit -q -m "chore: mutation-testing records"
cat >.claude/mutation-testing-arid.local.md <<'MD'
# Personal arid-node suppressions

```yaml
suppressions:
  a778cd5cef81d582:
    check: mutation-testing/operator/SBR
    claim: arid(kind=log-call)
    sites:
      - surface: src/calc.py
        anchor/v1: "e:9f1c2a3b:4d5e6f70"
    reason: "Logging call; the suite asserts on no log output."
    date: 2026-10-01
```
MD
