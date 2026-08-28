#!/usr/bin/env bash
# Self-contained tests for emit-findings.sh. Fixtures are built inline in a
# tmpdir. Per the shell-test-helpers convention, assertion helpers are local.
#
# Two load-bearing groups here. First, the relay boundary: only
# fingerprint-confirmed copies and the two deterministic stamp rules may reach
# the findings file, and a judgment verdict that leaks into it would break the
# boundary the Brief draws. Second, cell escaping: the fix action parses the
# table, so a pipe in a quoted excerpt splits a row into phantom columns.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$SCRIPT_DIR/emit-findings.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (the script reads a JSON sidecar)" >&2
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed (branch and relativization need it)" >&2
  exit 0
fi

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $3" "exit $2"; fi
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}
assert_match() {
  if [[ "$2" =~ $3 ]]; then pass "$1"; else fail "$1" "matches: $3" "$2"; fi
}
assert_file() {
  if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "exists: $2" "absent"; fi
}
# assert_fails <label> <command...>: the command must exit non-zero.
assert_fails() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$label" "non-zero exit" "exit 0"
  else
    pass "$label"
  fi
}

# --- Fixture repository ----------------------------------------------------------

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO/docs"
printf '%s\n' '# Doc' >"$REPO/docs/page.md"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "fixture"
git -C "$REPO" checkout -qb feature/provenance-relay

REPORTS="$TEST_TMPDIR/reports"
OUTDIR="$TEST_TMPDIR/out"
mkdir -p "$REPORTS" "$OUTDIR"

write_report() {
  printf '%s\n' "$2" >"$REPORTS/$1"
}

write_report full.json '{
  "counts": {"files": 1347},
  "findings": [
    {
      "id": "f-0001",
      "rule": "provenance/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 44, "end_line": 51},
      "class": "verbatim",
      "tier": "fingerprint-confirmed",
      "source": {"url": "https://code.claude.com/docs/skills.md", "fetched": "2026-08-27",
                 "identity": {"checked": true}},
      "fingerprint": {"containment": 0.42, "longest_span_words": 27}
    },
    {
      "rule": "provenance/audit/rule-stamp-expired",
      "file": "docs/page.md",
      "line": 12,
      "stamp_date": "2025-01-01",
      "window_days": 180,
      "days_over": 424
    },
    {
      "rule": "provenance/audit/rule-trigger-less-stamp",
      "file": "docs/page.md",
      "line": 20,
      "stamp_date": "2026-05-05"
    },
    {
      "rule": "provenance/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 70, "end_line": 72},
      "class": "paraphrase",
      "tier": "llm-suspected"
    },
    {
      "rule": "provenance/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 80, "end_line": 82},
      "tier": "source-fetched-similar"
    }
  ]
}'

write_report empty.json '{"counts": {"files": 10}, "findings": []}'
write_report notdetector.json '{"summary": "nothing to do here"}'
write_report garbage.json 'this is not json at all'
write_report unparsed.json '{"findings": [{"file": "docs/page.md", "line": 3, "note": "no rule id"}]}'

run() { (cd "$REPO" && bash "$EMIT" "$@"); }

# --- Usage -----------------------------------------------------------------------

OUT="$(bash "$EMIT" --help 2>&1)"
assert_exit "--help exits 0" "$?" "0"
assert_contains "--help names the script" "$OUT" "emit-findings.sh"

run --report "$REPORTS/full.json" >/dev/null 2>&1
assert_exit "a missing --out exits 2" "$?" "2"

run --out "$OUTDIR/x.md" >/dev/null 2>&1
assert_exit "a missing --report exits 2" "$?" "2"

run --report "$REPORTS/absent.json" --out "$OUTDIR/x.md" >/dev/null 2>&1
assert_exit "a nonexistent report exits 2" "$?" "2"

run --report "$REPORTS/notdetector.json" --out "$OUTDIR/x.md" >/dev/null 2>&1
assert_exit "a report with no findings key exits 3" "$?" "3"

run --report "$REPORTS/garbage.json" --out "$OUTDIR/x.md" >/dev/null 2>&1
assert_exit "an unparsable report exits 3" "$?" "3"

run --nope --report "$REPORTS/full.json" --out "$OUTDIR/x.md" >/dev/null 2>&1
assert_exit "an unknown argument exits 2" "$?" "2"

# --- The composed file -----------------------------------------------------------

TARGET="$OUTDIR/20260828T120000Z-provenance.md"
run --report "$REPORTS/full.json" --out "$TARGET" >/dev/null 2>&1
assert_exit "a clean run exits 0" "$?" "0"

assert_file "the file is written" "$TARGET"
BODY="$(cat "$TARGET")"

assert_contains "frontmatter declares the consumed type" "$BODY" "type: review-findings"
assert_contains "frontmatter carries the branch" "$BODY" "branch: feature/provenance-relay"
assert_match "date is a full ISO-8601 instant with an explicit Z" \
  "$BODY" 'date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
assert_contains "the Findings section is present" "$BODY" "## Findings"
assert_contains "the table header is the contract's columns" "$BODY" \
  "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |"

# --- Relay eligibility -----------------------------------------------------------

ROWS="$(grep -c '^| [0-9]' "$TARGET")"
assert_eq "only the three relay-eligible findings become rows" "$ROWS" "3"
assert_contains "the fingerprint-confirmed copy is a row" "$BODY" "rule-verbatim-copy"
assert_contains "the expired stamp is a row" "$BODY" "rule-stamp-expired"
assert_contains "the trigger-less stamp is a row" "$BODY" "rule-trigger-less-stamp"
assert_not_contains "an llm-suspected verdict never reaches the relay" "$BODY" "llm-suspected"
assert_not_contains "a source-fetched-similar verdict never reaches the relay" "$BODY" "source-fetched-similar"
assert_contains "withheld judgment findings are counted, not dropped" "$BODY" "2 judgment"

# --- Producer-owned fields -------------------------------------------------------

COPY_ROW="$(grep 'rule-verbatim-copy' "$TARGET" | head -1)"
assert_contains "Tier is looked up from the crosswalk" "$COPY_ROW" "| IMPORTANT |"
assert_contains "Confidence is high for a deterministic rule that fired" "$COPY_ROW" "| high |"
assert_contains "Location is repo-relative file:line" "$COPY_ROW" "docs/page.md:44"
assert_contains "the Finding cell leads with the qualified rule id" "$COPY_ROW" \
  "| provenance/audit/rule-verbatim-copy:"
assert_contains "the Finding cell carries the fired values" "$COPY_ROW" "27"
assert_contains "the copy row names its source" "$COPY_ROW" "https://code.claude.com/docs/skills.md"
assert_contains "the Action names the producer-owned remediation" "$COPY_ROW" "provenance:audit fix"

STAMP_ROW="$(grep 'rule-stamp-expired' "$TARGET" | head -1)"
assert_contains "the stamp row carries its fired values" "$STAMP_ROW" "424"
assert_contains "the stamp row names its window" "$STAMP_ROW" "180"
assert_contains "the stamp row is not auto-applicable" "$STAMP_ROW" "re-deriv"

assert_eq "ranks run 1..N in order" \
  "$(grep -o '^| [0-9]* |' "$TARGET" | tr -dc '0-9' | tr -d '\n')" "123"

# --- Cell escaping ---------------------------------------------------------------

write_report pipes.json '{
  "findings": [
    {
      "rule": "provenance/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 5, "end_line": 6},
      "tier": "fingerprint-confirmed",
      "source": {"url": "https://example.com/a"},
      "fingerprint": {"containment": 0.5, "longest_span_words": 20},
      "excerpt": "a | b and an already \\| escaped pipe\nplus a newline"
    }
  ]
}'
PIPE_OUT="$OUTDIR/pipes.md"
run --report "$REPORTS/pipes.json" --out "$PIPE_OUT" >/dev/null 2>&1
PIPE_ROW="$(grep 'rule-verbatim-copy' "$PIPE_OUT" | head -1)"
assert_eq "the escaped row still has exactly the contract's columns" \
  "$(printf '%s' "$PIPE_ROW" | sed 's/\\|//g' | tr -cd '|' | wc -c | tr -d ' ')" "8"
assert_contains "a bare pipe is escaped" "$PIPE_ROW" '\|'
assert_not_contains "an already-escaped pipe is not double-escaped" "$PIPE_ROW" '\\\|'
assert_not_contains "a newline inside a cell is replaced" "$PIPE_ROW" $'\n'

# --- Unparsed and coverage -------------------------------------------------------

UNP="$OUTDIR/unparsed.md"
run --report "$REPORTS/unparsed.json" --out "$UNP" >/dev/null 2>&1
assert_exit "a finding with no rule id still exits 0" "$?" "0"
assert_contains "an unrecognized finding lands in Unparsed" "$(cat "$UNP")" "## Unparsed"
assert_contains "the unparsed finding keeps its raw text" "$(cat "$UNP")" "no rule id"

EMPTY="$OUTDIR/empty.md"
run --report "$REPORTS/empty.json" --out "$EMPTY" >/dev/null 2>&1
assert_exit "a zero-finding run still exits 0" "$?" "0"
assert_file "a zero-finding run still writes the file" "$EMPTY"
assert_contains "coverage is reported even with no findings" "$(cat "$EMPTY")" "## Surfaces"
assert_contains "the surfaces line names the corpus size" "$(cat "$EMPTY")" "10"

# --- Non-overwrite naming --------------------------------------------------------

DUP="$OUTDIR/dup.md"
run --report "$REPORTS/full.json" --out "$DUP" >/dev/null 2>&1
run --report "$REPORTS/full.json" --out "$DUP" >/dev/null 2>&1
assert_file "a second write takes the -2 suffix" "$OUTDIR/dup-2.md"
run --report "$REPORTS/full.json" --out "$DUP" >/dev/null 2>&1
assert_file "a third write takes the -3 suffix" "$OUTDIR/dup-3.md"

# --- Branch handling -------------------------------------------------------------

BR="$OUTDIR/branch.md"
run --report "$REPORTS/full.json" --out "$BR" --branch 'no' >/dev/null 2>&1
assert_contains "a YAML-implicit-typed branch name is quoted" "$(cat "$BR")" 'branch: "no"'

BR2="$OUTDIR/branch2.md"
run --report "$REPORTS/full.json" --out "$BR2" --branch '#hash' >/dev/null 2>&1
assert_contains "a branch starting with a YAML indicator is quoted" "$(cat "$BR2")" 'branch: "#hash"'

# --- Absolute paths --------------------------------------------------------------

write_report abs.json "{
  \"findings\": [
    {
      \"rule\": \"provenance/audit/rule-stamp-expired\",
      \"file\": \"$REPO/docs/page.md\",
      \"line\": 7,
      \"stamp_date\": \"2025-01-01\",
      \"window_days\": 180,
      \"days_over\": 100
    }
  ]
}"
ABS="$OUTDIR/abs.md"
run --report "$REPORTS/abs.json" --out "$ABS" >/dev/null 2>&1
assert_contains "an absolute path is relativized" "$(cat "$ABS")" "| docs/page.md:7 |"
assert_not_contains "the repo root does not survive into Location" "$(cat "$ABS")" "$REPO/docs"

# --- Write failures --------------------------------------------------------------
#
# The worst outcome for a persistence step is reporting success having written
# nothing: the audit says the findings are relayed, and the consumer never scans
# a file that does not exist. `set -e` is deliberately not on in this script, so
# the two writing commands are checked explicitly.

assert_fails "an uncreatable destination directory exits non-zero" \
  bash "$EMIT" --report "$REPORTS/full.json" --out /proc/nope/deeper/x.md

OUT="$(run --report "$REPORTS/full.json" --out /proc/nope/deeper/x.md 2>&1)"
assert_not_contains "a failed write never claims it wrote" "$OUT" "wrote"

UNWRITABLE="$TEST_TMPDIR/unwritable"
mkdir -p "$UNWRITABLE"
chmod a-w "$UNWRITABLE"
if [[ ! -w "$UNWRITABLE" ]]; then
  assert_fails "an unwritable destination exits non-zero" \
    bash "$EMIT" --report "$REPORTS/full.json" --out "$UNWRITABLE/x.md"
else
  pass "an unwritable destination exits non-zero (SKIP: this user ignores mode bits)"
fi
chmod u+w "$UNWRITABLE"

# --- Determinism -----------------------------------------------------------------

D1="$OUTDIR/det1.md"
D2="$OUTDIR/det2.md"
run --report "$REPORTS/full.json" --out "$D1" >/dev/null 2>&1
run --report "$REPORTS/full.json" --out "$D2" >/dev/null 2>&1
assert_eq "repeat runs differ only in their date line" \
  "$(diff <(grep -v '^date:' "$D1") <(grep -v '^date:' "$D2") >/dev/null && echo same)" "same"

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
