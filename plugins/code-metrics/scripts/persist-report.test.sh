#!/usr/bin/env bash
# Regression tests for persist-report.sh: per-project report directory and retention.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CODE_METRICS_REPORT_DIR CM_REPORTS_KEPT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# state-key.sh derives the directory's key; naming it here keeps this suite in
# its affected-tests selection.
: "$SCRIPT_DIR/../lib/state-key.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"
# shellcheck source=persist-report.sh
source "$SCRIPT_DIR/persist-report.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_DATA="$TMP/data"
ROOT="$CLAUDE_PLUGIN_DATA/reports"
DOC="$TMP/doc.json"
printf '{}\n' >"$DOC"

for name in a b; do
  git init -q "$TMP/repo-$name"
  git -C "$TMP/repo-$name" remote add origin "https://example.com/owner/repo-$name.git"
done

persist_from() {
  (cd "$1" && cm_persist_report "$2" "$DOC")
}

# (a) two projects, two directories
pa="$(persist_from "$TMP/repo-a" audit-size)"
pb="$(persist_from "$TMP/repo-b" audit-size)"
assert_contains "repo A's report lands under the keyed root" "$pa" "$ROOT/example.com/owner/repo-a/"
assert_contains "repo B's report lands under the keyed root" "$pb" "$ROOT/example.com/owner/repo-b/"
assert_eq "the two projects keep their reports in different directories" 1 "$([[ "$(dirname "$pa")" != "$(dirname "$pb")" ]] && echo 1 || echo 0)"
assert_eq "the persisted file exists" 1 "$([[ -f "$pa" ]] && echo 1 || echo 0)"

# (b) retention is per project
count_reports() { find "$1" -maxdepth 1 -name 'audit-size-*.json' | wc -l | tr -d ' '; }
export CM_REPORTS_KEPT=2
for _ in 1 2 3; do persist_from "$TMP/repo-a" audit-size >/dev/null; done
assert_eq "repo A keeps only CM_REPORTS_KEPT reports" 2 "$(count_reports "$(dirname "$pa")")"
assert_eq "repo B's report is untouched by repo A's pruning" 1 "$(count_reports "$(dirname "$pb")")"
assert_eq "repo B's original file still exists" 1 "$([[ -f "$pb" ]] && echo 1 || echo 0)"

# (c) a leftover unkeyed file is named once and left alone
leftover="$ROOT/audit-size-20200101T000000Z.json"
printf '{}\n' >"$leftover"
err="$(persist_from "$TMP/repo-b" audit-size 2>&1 >/dev/null)"
assert_contains "the directory holding leftovers is named on stderr" "$err" "$ROOT holds"
assert_eq "the leftover file still exists" 1 "$([[ -f "$leftover" ]] && echo 1 || echo 0)"
unset CM_LEFTOVERS_NOTED
err="$(persist_from "$TMP/repo-b" other-skill 2>&1 >/dev/null)"
assert_eq "a leftover of another skill is not reported" "" "$err"

# fail closed when the key cannot be derived
saved="$CM_PERSIST_SCRIPT_DIR"
CM_PERSIST_SCRIPT_DIR="$TMP/nowhere"
out="$(persist_from "$TMP/repo-a" audit-size 2>"$TMP/err")"
rc=$?
CM_PERSIST_SCRIPT_DIR="$saved"
assert_eq "an underivable key fails the persist" 1 "$rc"
assert_eq "an underivable key prints no path" "" "$out"
assert_contains "an underivable key is named on stderr" "$(cat "$TMP/err")" "cannot derive the per-project state key"
assert_eq "an underivable key never writes to the unkeyed root" 1 "$([[ "$(find "$ROOT" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')" == 1 ]] && echo 1 || echo 0)"

# (d) the override carries no key
export CODE_METRICS_REPORT_DIR="$TMP/override"
out="$(persist_from "$TMP/repo-a" audit-size)"
assert_eq "CODE_METRICS_REPORT_DIR overrides with no key" "$TMP/override" "$(dirname "$out")"
assert_eq "cm_report_dir prints the override unchanged" "$TMP/override" "$(cm_report_dir)"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
