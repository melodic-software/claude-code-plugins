#!/usr/bin/env bash
# A git repo whose feature branch is one commit ahead of main, with a bare local origin so the push
# step succeeds, and an offline gh that serves only `issue view 812`: an open issue with one checked
# and two unchecked acceptance items and no sub-issues. The branch delivers the byte order mark.
# The stand-in sits in <git dir>/eval-forge/bin, which the case's gh-forge-path plugin puts first on
# the run's PATH; every other gh command exits 1, so nothing reaches GitHub.
set -euo pipefail

git init -q --bare ../eval-origin.git
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git remote add origin ../eval-origin.git
mkdir -p .claude src
printf 'export const toCsv = (rows) => rows.join("\\n");\n' >src/export.ts
printf '# demo\n' >README.md
printf '# source-control configuration\n\n## pr_body_required_sections\n\n- Summary\n- Verification\n' >.claude/source-control.md
git add .claude src README.md
git commit -q -m "chore: seed"
git push -q -u origin main

git checkout -q -b feat/csv-export-bom
printf 'export const toCsv = (rows) => "\\uFEFF" + rows.join("\\n");\n' >src/export.ts
git add src/export.ts
git commit -q -m "feat: write a UTF-8 byte order mark in the CSV export"

bin="$(git rev-parse --path-format=absolute --git-common-dir)/eval-forge/bin"
mkdir -p "$bin"
cat >"$bin/issue-812.json" <<'JSON'
{
  "number": 812,
  "title": "CSV export opens without repair in spreadsheet tools",
  "state": "OPEN",
  "body": "## Acceptance criteria\n\n- [x] An export with no rows still writes the header row.\n- [ ] The file starts with a UTF-8 byte order mark.\n- [ ] Cells holding a comma, quote or line break are quoted per RFC 4180 (Closes #813 when done).\n",
  "subIssues": {"nodes": []},
  "url": "https://github.com/eval-fixture/app/issues/812"
}
JSON
cat >"$bin/gh" <<'GH'
#!/usr/bin/env bash
# Offline gh for one eval case: serves `issue view <n>` from issue-<n>.json and refuses the rest.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ "${1:-} ${2:-}" == "issue view" ]] || { echo "gh (eval fixture): '$*' is not served offline" >&2; exit 1; }
shift 2
n="" json="" jq_expr=""
while (($#)); do
  case "$1" in
    --json) json="$2"; shift ;;
    --json=*) json="${1#--json=}" ;;
    -q | --jq) jq_expr="$2"; shift ;;
    --jq=*) jq_expr="${1#--jq=}" ;;
    -R | --repo) shift ;;
    -*) ;;
    *) n="${1#\#}"; n="${n##*/issues/}" ;;
  esac
  shift
done
f="$here/issue-$n.json"
[[ -f "$f" ]] || { echo "GraphQL: Could not resolve to an issue or pull request with the number of $n." >&2; exit 1; }
doc=$(cat "$f")
[[ -n "$json" ]] && doc=$(jq -c --arg f "$json" '. as $d | reduce ($f | split(",")[]) as $k ({}; .[$k] = $d[$k])' <<<"$doc")
if [[ -n "$jq_expr" ]]; then jq -r "$jq_expr" <<<"$doc"; else jq . <<<"$doc"; fi
GH
chmod +x "$bin/gh"
