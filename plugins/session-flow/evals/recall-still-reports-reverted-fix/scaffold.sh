#!/usr/bin/env bash
# Seeds the eval workspace with a git repository that keeps a postmortem of a CSV export crash on
# quoted cells, fixes the crash with a commit that closes item #42, then reverts that fix.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src docs/postmortems
printf 'export const cell = (v) => String(v);\n' >src/csv.ts
git add src
git commit -q -m "feat(export): CSV export"

cat >docs/postmortems/2026-09-csv-export-crash.md <<'EOF'
# Postmortem: CSV export crash on quoted cells

Date: 2026-09-18

## What happened

Every CSV export holding a double quote in a cell crashed for about two hours.

## Cause

The CSV writer did not escape double quotes.

## Follow-ups

- Escape double quotes in CSV cells (#42).
EOF
git add docs
git commit -q -m "docs: postmortem for the CSV export crash"

cat >src/csv.ts <<'EOF'
export const cell = (v) => `"${String(v).replaceAll('"', '""')}"`;
EOF
git commit -q -am "fix(export): escape double quotes in CSV cells" \
  -m "Fixes #42: an export with a double quote in a cell crashed."
fix="$(git rev-parse HEAD)"

git revert --no-edit "$fix" >/dev/null
git commit -q --amend -m "Revert \"fix(export): escape double quotes in CSV cells\"" \
  -m "This reverts commit $fix." \
  -m "Quoting every cell broke spreadsheet imports, so exports with a double quote crash again."
