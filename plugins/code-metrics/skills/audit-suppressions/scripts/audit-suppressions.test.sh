#!/usr/bin/env bash
# Tests for the audit-suppressions entry point: scope (the change, --all,
# paths, scope.exclude), the correctness list from the team layer, the JSON
# document, the markdown report and the kept copy. Expected values are read
# off the fixture repository this file builds.
# test-scope: lib/suppression-scan.py plugins/code-metrics/scripts/dispatch.sh plugins/code-metrics/scripts/resolve-config.py
# shellcheck disable=SC2016 # `$(...)` and backticks here are fixture text, never expanded
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-suppressions.sh"
PY="${PYTHON:-python3}"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: [$3], actual: [$2]" ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
export CODE_METRICS_HOME="$TMP/home"
export CODE_METRICS_REPORT_DIR="$TMP/reports"
mkdir -p "$REPO/docs/conventions" "$REPO/vendor" "$CODE_METRICS_HOME"
g() { git -C "$REPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
g init -q -b main
printf '%s\n' 'a = 1  # noqa: E501' >"$REPO/old.py"
printf '%s\n' 'suppressions:' '  correctness_rules: [no-console]' >"$REPO/docs/conventions/code-metrics.yaml"
g add -A
g commit -q -m base
g switch -q -c topic
printf '%s\n' 'foo(); // eslint-disable-line no-console' >"$REPO/new.js"
printf '%s\n' 'x = 1  # noqa: E501 the URL is kept whole' >"$REPO/new.py"
printf '%s\n' '# shellcheck disable=SC2086' >"$REPO/\$(touch pwned).sh"
printf '%s\n' 'alert(1); // eslint-disable-line no-alert' >"$REPO/vendor/lib.js"
g add -A
g commit -q -m topic

doc_field() {
  "$PY" -c '
import json, sys
d = json.load(sys.stdin)
print(eval(sys.argv[1], {"d": d}))
' "$1"
}

out="$(cd "$REPO" && BASH_COMPAT=51 bash "$SCRIPT" --json)"
assert_eq "the change run exits 0" 0 "$?"
assert_eq "the change reports only added lines, outside scope.exclude" \
  '$(touch pwned).sh:1 new.js:1 new.py:1' \
  "$(printf '%s' "$out" | doc_field '" ".join("%s:%d" % (r["file"], r["line"]) for r in d["suppressions"])')"
assert_eq "the counts are one justified, two without a reason, one correctness rule" \
  '3 2 1' "$(printf '%s' "$out" | doc_field '"%d %d %d" % (d["counts"]["suppressions"], d["counts"]["unjustified"], d["counts"]["correctness"])')"
assert_eq "the correctness list and its layer come from the team file" \
  "['no-console'] team" "$(printf '%s' "$out" | doc_field '"%s %s" % (d["correctness_rules"]["rules"], d["correctness_rules"]["layer"])')"
assert_eq "the document names its skill and scope mode" \
  'audit-suppressions change' "$(printf '%s' "$out" | doc_field '"%s %s" % (d["skill"], d["scope"]["mode"])')"
if [[ -e "$REPO/pwned" ]]; then fail "a file name is never evaluated" "pwned exists"; else pass "a file name is never evaluated"; fi

out="$(cd "$REPO" && bash "$SCRIPT" --json --all)"
assert_eq "--all lists every suppression in the tree but the excluded one" \
  '$(touch pwned).sh:1 new.js:1 new.py:1 old.py:1' \
  "$(printf '%s' "$out" | doc_field '" ".join("%s:%d" % (r["file"], r["line"]) for r in d["suppressions"])')"

out="$(cd "$REPO" && bash "$SCRIPT" --json old.py)"
assert_eq "an explicit path is scanned whole" 'old.py:1' \
  "$(printf '%s' "$out" | doc_field '" ".join("%s:%d" % (r["file"], r["line"]) for r in d["suppressions"])')"

out="$(cd "$REPO" && bash "$SCRIPT")"
assert_eq "the markdown run exits 0" 0 "$?"
assert_contains "the markdown states the counts" "$out" "3 suppressions, 2 without a reason"
assert_contains "the markdown names the correctness rule" "$out" '`no-console`'
assert_contains "the markdown lists the unjustified line" "$out" "| new.js | 1 | eslint | no-console | no |"
kept=("$CODE_METRICS_REPORT_DIR"/audit-suppressions-*.json)
if [[ -f "${kept[0]}" ]]; then pass "the markdown run keeps the document"; else fail "the markdown run keeps the document" "none in $CODE_METRICS_REPORT_DIR"; fi
assert_contains "the markdown names the kept document" "$out" "${kept[0]}"

printf '%s\n' 'suppressions:' '  correctness_rules: no-console' >"$REPO/docs/conventions/code-metrics.yaml"
out="$(cd "$REPO" && bash "$SCRIPT" --json 2>"$TMP/err")"
assert_eq "an invalid correctness list never stops the run" 0 "$?"
assert_eq "an invalid team value falls back to the bundled empty list" '[] bundled default' \
  "$(printf '%s' "$out" | doc_field '"%s %s" % (d["correctness_rules"]["rules"], d["correctness_rules"]["layer"])')"
assert_contains "the warning names the key" "$(cat "$TMP/err")" "suppressions.correctness_rules"

(cd "$REPO" && bash "$SCRIPT" does-not-exist.py >/dev/null 2>&1)
assert_eq "a missing explicit path exits 2" 2 "$?"
(cd "$REPO" && bash "$SCRIPT" --bogus >/dev/null 2>&1)
assert_eq "an unknown flag exits 2" 2 "$?"
bash "$SCRIPT" --help 2>&1 | grep -q 'audit-suppressions.sh \[--json | --findings'
assert_eq "--help prints usage" 0 "$?"
assert_contains "--help states both exit codes and their meaning" "$(bash "$SCRIPT" --help 2>&1)" \
  'Exit 0 report produced, 2 usage error or a scan that failed.'

# ---- --findings: the review-findings file ------------------------------------
# Expected rows come from the fixture lines below and the two crosswalk rows in
# docs/conventions/detector-findings/README.md (rule-no-reason fires on a line
# with no reason; rule-no-rule-id on a reason with no rule id where the tool can
# name one; both IMPORTANT, Confidence high).
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "expected NOT to contain: [$3], actual: [$2]" ;;
  *) pass "$1" ;;
  esac
}
F="$TMP/frepo"
mkdir -p "$F/sub"
gf() { git -C "$F" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
gf init -q -b main
printf '%s\n' 'old = 1  # noqa' >"$F/old.py"
gf add -A
gf commit -q -m base
gf switch -q -c feat/Audit
printf '%s\n' 'foo(); // eslint-disable-line no-console' >"$F/a.js"
printf '%s\n' 'bar(); // eslint-disable-line' >"$F/b.js"
printf '%s\n' '// @ts-ignore' 'const n: number = "x";' >"$F/c.ts"
printf '%s\n' "[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]" 'param()' >"$F/d.ps1"
printf '%s\n' 'x = 1  # noqa  # kept as is | the shell example pipes it' >"$F/e.py"
printf '%s\n' 'y = 2  # noqa: E501 the URL is kept whole' >"$F/f.py"
printf '%s\n' '// @ts-expect-error the fixture type is wrong on purpose' 'const m: number = "y";' >"$F/g.ts"
printf '%s\n' 'z = 3  # type: ignore' >"$F/h.py"
printf '%s\n' 'w = 4  # type: ignore' >"$F/we|ird.py"
printf '%s\n' 'v = 5  # noqa' >"$F/sub/i.py"
gf add -A
gf commit -q -m topic

# field <file> <location> <column 1-7>: one cell of the row at <location>,
# split on unescaped pipes.
field() {
  "$PY" -c '
import re, sys
path, where, col = sys.argv[1], sys.argv[2], int(sys.argv[3])
for line in open(path, encoding="utf-8"):
    if not line.startswith("| ") or line.startswith("| Rank"):
        continue
    cells = [c.strip() for c in re.split(r"(?<!\\)\|", line.strip())[1:-1]]
    if cells[3] == where:
        print(cells[col - 1])
' "$1" "$2" "$3"
}

FDIR="$F/.work/reviews/feat-audit"
out="$(cd "$F" && bash "$SCRIPT" --findings </dev/null)"
assert_eq "--findings exits 0 with no input on stdin" 0 "$?"
files=("$FDIR"/*-suppressions.md)
assert_eq "--findings writes one file into the branch slug directory" 1 "${#files[@]}"
FILE="${files[0]}"
assert_contains "--findings prints the file it wrote" "$out" "Findings file: $FILE"
assert_contains "--findings still prints the markdown report" "$out" "# Suppressions: lines added since"
assert_eq "the memory root gets a .gitignore holding *" '*' "$(cat "$F/.work/.gitignore" 2>/dev/null)"
assert_eq "the frontmatter names the type and the exact branch" \
  'type: review-findings|branch: feat/Audit' "$(sed -n '2p;4p' "$FILE" | paste -sd'|' -)"
if sed -n 3p "$FILE" | grep -Eq '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  pass "date is an ISO-8601 UTC instant"
else fail "date is an ISO-8601 UTC instant" "$(sed -n 3p "$FILE")"; fi
assert_contains "the table header is the findings-file shape" "$(cat "$FILE")" \
  '| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |'
assert_eq "every unjustified added suppression is a row, justified ones are not, in file order" \
  'a.js:1 b.js:1 c.ts:1 d.ps1:1 e.py:1 h.py:1 sub/i.py:1 we\|ird.py:1' \
  "$("$PY" -c '
import re, sys
rows = [re.split(r"(?<!\\)\|", l.strip())[1:-1] for l in open(sys.argv[1], encoding="utf-8") if l.startswith("| ") and not l.startswith("| Rank")]
print(" ".join(c[3].strip() for c in rows))
' "$FILE")"
assert_eq "every row splits into exactly seven cells" '7' \
  "$("$PY" -c '
import re, sys
rows = [re.split(r"(?<!\\)\|", l.strip())[1:-1] for l in open(sys.argv[1], encoding="utf-8") if l.startswith("| ") and not l.startswith("| Rank")]
print(" ".join(sorted({str(len(c)) for c in rows})))
' "$FILE")"
assert_eq "tier and confidence are looked up, IMPORTANT and high on every row" 'IMPORTANT high code-metrics:audit-suppressions' \
  "$(for loc in a.js:1 e.py:1 'we\|ird.py:1'; do printf '%s %s %s\n' "$(field "$FILE" "$loc" 2)" "$(field "$FILE" "$loc" 3)" "$(field "$FILE" "$loc" 5)"; done | sort -u)"
assert_eq "a line with no reason leads with rule-no-reason and the fired values" \
  'code-metrics/audit-suppressions/rule-no-reason: eslint suppression of no-console, no reason on the line' \
  "$(field "$FILE" a.js:1 6)"
assert_eq "a reason with no rule id leads with rule-no-rule-id, its pipe escaped" \
  'code-metrics/audit-suppressions/rule-no-rule-id: noqa suppression naming no rule id, reason "kept as is \| the shell example pipes it"' \
  "$(field "$FILE" e.py:1 6)"

# The remedy, pinned per scope: where the reason goes depends on the tool, and a
# rule id is asked for only where the tool can name one and the line names none.
act="$(field "$FILE" a.js:1 7)"
assert_contains "eslint: the reason goes after --" "$act" 'write the reason after ` -- ` at the end of the directive'
assert_not_contains "eslint: no Justification argument offered" "$act" 'Justification'
assert_not_contains "eslint with a rule id: no rule id asked for" "$act" 'name the rule id'
act="$(field "$FILE" b.js:1 7)"
assert_contains "eslint with no rule id: the rule id is asked for" "$act" 'name the rule id it silences in the directive and write the reason after ` -- `'
act="$(field "$FILE" c.ts:1 7)"
assert_contains "typescript: the reason is text after the directive" "$act" 'write the reason as text after the directive on the same line'
assert_not_contains "typescript: no rule id asked for" "$act" 'rule id'
assert_not_contains "typescript: no -- slot offered" "$act" ' -- '
act="$(field "$FILE" d.ps1:1 7)"
assert_contains "powershell: the reason goes in Justification" "$act" 'in a `Justification` argument on the attribute'
assert_not_contains "powershell: no -- slot offered" "$act" ' -- '
act="$(field "$FILE" h.py:1 7)"
assert_contains "mypy: the reason is a comment after the directive" "$act" 'name the rule id it silences in the directive and write the reason in a comment after the directive on the same line'
assert_not_contains "mypy: no Justification argument offered" "$act" 'Justification'
assert_not_contains "mypy: no -- slot offered" "$act" ' -- '
act="$(field "$FILE" e.py:1 7)"
assert_contains "rule-no-rule-id: the rule id is asked for" "$act" 'Name the rule id the stated reason is about in the directive'
assert_not_contains "rule-no-rule-id: no reason asked for, the line has one" "$act" 'write the reason'
change_actions="$(for loc in a.js:1 b.js:1 c.ts:1 d.ps1:1 e.py:1 h.py:1; do field "$FILE" "$loc" 7; done)"

surfaces="$(sed -n '/^## Surfaces/,$p' "$FILE")"
assert_contains "Surfaces names the run and its coverage" "$surfaces" \
  'Ran: [code-metrics:audit-suppressions (lines added since'
assert_contains "Surfaces counts the suppressions examined" "$surfaces" '10 files in scope, 10 suppressions examined)].'
assert_contains "a reason on the line declines rule-no-reason, counted" "$surfaces" \
  'Declined candidates: code-metrics/audit-suppressions/rule-no-reason count=3 reason=reason-on-line'
assert_contains "a rule id on the line declines rule-no-rule-id, counted" "$surfaces" \
  'Declined candidates: code-metrics/audit-suppressions/rule-no-rule-id count=1 reason=rule-id-on-line'
assert_contains "a TypeScript directive with a reason declines rule-no-rule-id, counted" "$surfaces" \
  'Declined candidates: code-metrics/audit-suppressions/rule-no-rule-id count=1 reason=tool-names-no-rule'

out="$(cd "$F" && bash "$SCRIPT" --findings --all </dev/null)"
assert_eq "--findings --all exits 0" 0 "$?"
files=("$FDIR"/*-suppressions*.md)
assert_eq "a second run writes a second file, never overwriting the first" 2 "${#files[@]}"
FILE2="${out##*Findings file: }"
assert_contains "--all also reports the old file's line" "$(field "$FILE2" old.py:1 6)" 'rule-no-reason: noqa suppression naming no rule id'
assert_eq "--all offers each remedy as the change scope does" "$change_actions" \
  "$(for loc in a.js:1 b.js:1 c.ts:1 d.ps1:1 e.py:1 h.py:1; do field "$FILE2" "$loc" 7; done)"

out="$(cd "$F/sub" && bash "$SCRIPT" --findings --memory-dir mem i.py </dev/null)"
FILE3="${out##*Findings file: }"
assert_contains "--memory-dir names the memory root under the repository" "$FILE3" "$F/mem/reviews/feat-audit/"
assert_eq "a run from a subdirectory still writes repo-relative locations" 'sub/i.py:1' \
  "$(field "$FILE3" sub/i.py:1 4)"

before="$(find "$F/.work" -name '*.md' | wc -l)"
(cd "$F" && bash "$SCRIPT" >/dev/null)
assert_eq "bare invocation writes no findings file" "$before" "$(find "$F/.work" -name '*.md' | wc -l)"
(cd "$F" && bash "$SCRIPT" --findings --json >/dev/null 2>&1)
assert_eq "--findings with --json is a usage error" 2 "$?"

# The reason slot per tool, for the tools the fixture above does not reach.
# Each expected slot is the place the scanner reads a reason from for that
# tool (lib/suppression-scan.py: the text after the rule ids, a further comment
# on the line, or the attribute's Justification argument).
S="$TMP/srepo"
mkdir -p "$S"
gs() { git -C "$S" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
gs init -q -b main
printf '%s\n' 'x = 1 # rubocop:disable Style/Foo' >"$S/k.rb"
printf '%s\n' '#pragma warning disable CS0168' 'class K {}' >"$S/l.cs"
printf '%s\n' '[SuppressMessage("Usage", "CA2200")]' 'class M {}' >"$S/m.cs"
printf '%s\n' 'A long line. <!-- markdownlint-disable-line MD013 -->' >"$S/n.md"
printf '%s\n' 'package o' 'func f() { g() //nolint' '}' >"$S/o.go"
gs add -A
gs commit -q -m slots
out="$(cd "$S" && bash "$SCRIPT" --findings --all </dev/null)"
SFILE="${out##*Findings file: }"
act="$(field "$SFILE" k.rb:1 7)"
assert_contains "rubocop: the reason goes after --" "$act" 'write the reason after ` -- ` at the end of the directive'
assert_not_contains "rubocop with a rule id: no rule id asked for" "$act" 'name the rule id'
act="$(field "$SFILE" l.cs:1 7)"
assert_contains "csharp pragma: the reason is a // comment after it" "$act" 'write the reason in a `//` comment after the pragma on the same line'
assert_not_contains "csharp pragma: no Justification argument offered" "$act" 'Justification'
act="$(field "$SFILE" m.cs:1 7)"
assert_contains "csharp attribute: the reason goes in Justification" "$act" 'write the reason in the `Justification` argument of the attribute'
assert_not_contains "csharp attribute: no pragma comment offered" "$act" 'pragma'
act="$(field "$SFILE" n.md:1 7)"
assert_contains "markdownlint: the reason is a second comment" "$act" 'write the reason in a second `<!-- -->` comment on the same line'
assert_not_contains "markdownlint: no -- slot offered" "$act" ' -- '
act="$(field "$SFILE" o.go:2 7)"
assert_contains "nolint with no rule id: rule id and a trailing comment asked for" "$act" \
  'name the rule id it silences in the directive and write the reason in a comment after the directive on the same line'
assert_not_contains "nolint: no Justification argument offered" "$act" 'Justification'

gf checkout -q --detach
err="$(cd "$F" && bash "$SCRIPT" --findings 2>&1 >/dev/null)"
assert_eq "with no current branch --findings exits 2" 2 "$?"
assert_contains "with no current branch it says no file was written" "$err" "no findings file written"
assert_eq "with no current branch no file is written" "$before" "$(find "$F/.work" -name '*.md' | wc -l)"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
