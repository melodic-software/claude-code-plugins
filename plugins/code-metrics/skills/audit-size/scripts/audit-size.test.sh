#!/usr/bin/env bash
# Regression tests for the audit-size entry point (audit-size.sh): option parsing,
# JSON versus markdown output, and exit-code passthrough from dispatch.sh.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-size.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SOURCES="plugins/code-metrics/scripts/fixtures/sources"
cd "$REPO_ROOT" || exit 2

FAILED=0
CASE_NUM=0
# shellcheck source=../../../scripts/test-helpers.sh
source "$PLUGIN_ROOT/scripts/test-helpers.sh"

unset CODE_METRICS_DISABLE_BUNDLED
REPORTS="$(mktemp -d)"
trap 'rm -rf "$REPORTS"' EXIT
export CODE_METRICS_REPORT_DIR="$REPORTS"

out="$(bash "$SCRIPT" --json --all "$SOURCES")"
rc=$?
assert_eq "--json exits 0" 0 "$rc"
assert_doc "--json prints a code-metrics/v1 document for audit-size" "$out" \
  'd["schema"]=="code-metrics/v1" and d["skill"]=="audit-size" and d["run"]'

out="$(bash "$SCRIPT" --all "$SOURCES")"
rc=$?
assert_eq "markdown exits 0" 0 "$rc"
assert_contains "markdown carries the run table" "$out" "## Coverage of this run"
assert_contains "markdown carries the plugin-default reference" "$out" "| file_lines | 1000 |"
assert_contains "markdown lists the python fixture" "$out" "cm_sample.py"

out="$(CODE_METRICS_DISABLE_BUNDLED=1 bash "$SCRIPT" --all "$SOURCES" 2>/dev/null || true)"
assert_contains "all-unavailable run renders the Measured nothing headline" "$out" "Measured nothing"

bash "$SCRIPT" "$SOURCES/does-not-exist.py" >/dev/null 2>&1
assert_eq "a missing explicit path exits 2" 2 "$?"

bash "$SCRIPT" --help 2>&1 | grep -q 'audit-size.sh \[--json\]'
assert_eq "--help prints usage" 0 "$?"

# The 1000-line provenance is one sentence, owned by the bundled defaults and
# repeated verbatim where a reader meets the number without the report: the
# skill body and the principles threshold table. A rewording in one place is a
# second story about where the number came from.
provenance="$("$PY" -c '
import json, sys
doc = json.load(open(sys.argv[1]))
print(next(t["provenance"] for t in doc["thresholds"] if t["measure"] == "file_lines"))
' "$PLUGIN_ROOT/scripts/config-defaults.json")"
for surface in "$SCRIPT_DIR/../SKILL.md" "$SCRIPT_DIR/../../principles/reference/thresholds.md"; do
  # Markdown wraps the sentence across lines; compare with whitespace folded.
  folded="$(tr -s '[:space:]' ' ' <"$surface")"
  case "$folded" in
  *"$provenance"*) pass "${surface##*/} carries the file_lines provenance verbatim" ;;
  *) fail "${surface##*/} carries the file_lines provenance verbatim" "$provenance" "$(printf '%s' "$folded" | grep -o '.\{0,80\}ISO-backed.\{0,80\}' | head -1)" ;;
  esac
done

# The description names `--all` as a scope in its own right and no longer
# disowns the whole-tree run, and stays inside the field maximum.
description="$(sed -n '2p' "$SCRIPT_DIR/../SKILL.md")"
case "$description" in
*"wrong tool"*) fail "the description no longer disowns --all" "no 'wrong tool' clause" "$description" ;;
*"(\`--all\`)"*) pass "the description no longer disowns --all" ;;
*) fail "the description no longer disowns --all" "names --all" "$description" ;;
esac
length="$("$PY" -c 'import sys; print(len(sys.argv[1]))' "$description")"
if [[ "$length" -lt 1024 ]]; then pass "the description is under 1024 codepoints ($length)"; else fail "the description is under 1024 codepoints" "< 1024" "$length"; fi

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
