#!/usr/bin/env bash
# A configured Python repo whose arid record has one entry with no check or claim.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" configured
mkdir -p .claude
cat >.claude/mutation-testing-arid.md <<'MD'
# Arid-node suppressions

```yaml
suppressions:
  846675cd2cbd91bd:
    sites:
      - surface: src/calc.py
        anchor/v1: "e:9f1c2a3b:4d5e6f70"
    reason: "Logging call; the suite asserts on no log output."
    date: 2026-10-01
```
MD
git add -A
git commit -q -m "chore: mutation-testing records"
