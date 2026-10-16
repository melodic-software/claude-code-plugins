#!/usr/bin/env bash
# A git repo whose feature branch is one commit ahead of main, with a bare local origin so the push
# step succeeds, and one approved PLAN.md in the gitignored memory slice whose Brief lists three
# acceptance criteria. The branch name does not match the plan's topic slug, and the prompt never
# mentions the plan.
set -euo pipefail

git init -q --bare ../eval-origin.git
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git remote add origin ../eval-origin.git
mkdir -p .claude src
printf '.work/\n' > .gitignore
printf 'export const toCsv = (rows) => rows.join("\\n");\n' > src/export.ts
printf '# demo\n' > README.md
printf '# source-control configuration\n\n## pr_body_required_sections\n\n- Summary\n- Verification\n' > .claude/source-control.md
git add .gitignore .claude src README.md
git commit -q -m "chore: seed"
git push -q -u origin main

git checkout -q -b feat/csv-download
cat > src/export.ts <<'TS'
const quote = (cell) => (/[",\n]/.test(cell) ? `"${cell.replaceAll('"', '""')}"` : cell);
export const toCsv = (header, rows) =>
  "\uFEFF" + [header, ...rows].map((row) => row.map(quote).join(",")).join("\r\n");
TS
git add src/export.ts
git commit -q -m "feat: quote CSV cells and write a byte order mark"

mkdir -p .work/export-csv
cat > .work/export-csv/PLAN.md <<'MD'
# export-csv

Approval: approved by the maintainer in the planning session

## Brief

Goal: the report export downloads as a CSV file spreadsheet tools open without repair.

Scope: `src/export.ts` only.

### Acceptance criteria

- AC1: the file starts with a UTF-8 byte order mark so spreadsheet tools detect the encoding.
- AC2: cells holding a comma, a double quote or a line break are quoted per RFC 4180.
- AC3: an export with no rows still writes the header row, matching /srv/finance-share/fixtures/empty-export.csv.

## Plan

### Phase 1: CSV writer [DONE]

- Rewrite `toCsv` in `src/export.ts`.
- **Sanity Check:** the unit tests pass.
MD
