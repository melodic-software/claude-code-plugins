#!/usr/bin/env bash
# The same repository as eb-recorded-rule-proven: an import check under scripts/check.sh and a
# recorded billing-must-not-import-reporting rule that no check enforces yet.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs src scripts .github
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/import-check-repo.sh"
git add -A
git commit -q -m "Billing, reporting and shared modules with an import check"
