#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ledger-repo.sh" setup-existing

printf '%s\n' '.claude/**/*.local.*' >.gitignore
cat >.claude/codebase-health.local.md <<'MD'
# codebase-health personal override

## runbooks

**primary-sources:**

- `README.md`

**verification-sources:**

- `package.json`
MD
