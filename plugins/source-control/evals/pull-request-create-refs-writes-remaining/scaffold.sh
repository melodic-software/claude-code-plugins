#!/usr/bin/env bash
# A git repo whose feature branch is one commit ahead of main and an offline forge (fixtures/gh-forge,
# --no-pr) that takes the push, opens the PR and serves the issues/812.json fixture: open, with one
# checked and two unchecked acceptance items and no sub-issues. The branch delivers the byte order
# mark. The case's gh-forge-path plugin puts the stand-in first on the run's PATH; any command it
# does not serve exits 1, so nothing reaches GitHub.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p .claude src
printf 'export const toCsv = (rows) => rows.join("\\n");\n' >src/export.ts
printf '# demo\n' >README.md
printf '# source-control configuration\n\n## pr_body_required_sections\n\n- Summary\n- Verification\n' >.claude/source-control.md
git add .claude src README.md
git commit -q -m "chore: seed"

git checkout -q -b feat/csv-export-bom
printf 'export const toCsv = (rows) => "\\uFEFF" + rows.join("\\n");\n' >src/export.ts
git add src/export.ts
git commit -q -m "feat: write a UTF-8 byte order mark in the CSV export"
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/gh-forge/install.sh" 834 feat/csv-export-bom main "feat: write a UTF-8 byte order mark in the CSV export" --no-pr

cat >"$(git rev-parse --path-format=absolute --git-common-dir)/eval-forge/issues/812.json" <<'JSON'
{
  "number": 812,
  "title": "CSV export opens without repair in spreadsheet tools",
  "state": "OPEN",
  "body": "## Acceptance criteria\n\n- [x] An export with no rows still writes the header row.\n- [ ] The file starts with a UTF-8 byte order mark.\n- [ ] Cells holding a comma, quote or line break are quoted per RFC 4180 (Closes #813 when done).\n",
  "subIssues": {"nodes": []},
  "url": "https://github.com/eval-fixture/app/issues/812"
}
JSON
