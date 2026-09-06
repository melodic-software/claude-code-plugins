#!/usr/bin/env bash
# Regression tests for the audit-coverage entry point (audit-coverage.sh):
# artifact discovery and the usage error for a named path that does not exist,
# the join it prints for each committed artifact format
# (fixtures/coverage/lcov-1x.info, lcov-2.2.info, lcov-absolute-sf.info,
# cobertura.xml, coverage-py.json, go-cover.out), the run rows that explain a
# reduced result, and the markdown rendering.
#
# Complexity comes from the sibling audit-complexity script, so its collectors
# are stubbed at runtime the same way its own suite does it: a temporary bin/
# prepended to a filtered PATH carries a fake `lizard` replaying
# fixtures/tool-output/lizard.csv (function start AND end lines) and a fake
# `shellmetrics` replaying fixtures/tool-output/shellmetrics.csv (a start line
# only, which is what makes Bash CRAP not-applicable). Nothing executable is
# committed (design T13). No test command is ever run: this skill reads
# artifacts.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-coverage.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SOURCES="plugins/code-metrics/scripts/fixtures/sources"
CAPTURES="$PLUGIN_ROOT/scripts/fixtures/tool-output"
COVERAGE="$PLUGIN_ROOT/scripts/fixtures/coverage"
cd "$REPO_ROOT" || exit 2

PY=python3
command -v python3 >/dev/null 2>&1 || PY=python

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
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$(printf '%s' "$2" | head -c 400)" ;;
  esac
}
assert_matches() {
  # assert_matches <name> <text> <extended regex>
  if printf '%s' "$2" | grep -Eq "$3"; then
    pass "$1"
  else
    fail "$1" "matches: $3" "$(printf '%s' "$2" | head -c 400)"
  fi
}
# jq-free JSON assertions: a Python expression over the parsed document `d`.
assert_doc() {
  if printf '%s' "$2" | "$PY" -c "import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if ($3) else 1)" 2>/dev/null; then
    pass "$1"
  else
    fail "$1" "$3" "$(printf '%s' "$2" | head -c 600)"
  fi
}

STUBS="$(mktemp -d)"
EMPTY_PATH="$(mktemp -d)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$STUBS" "$EMPTY_PATH" "$SCRATCH"' EXIT

cat >"$STUBS/lizard" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '1.24.0\n'; exit 0; fi
cat "$CAPTURES/lizard.csv"
EOF
cat >"$STUBS/shellmetrics" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '0.5.0\n'; exit 0; fi
cat "$CAPTURES/shellmetrics.csv"
EOF
chmod +x "$STUBS"/*

# EMPTY_PATH is the caller's PATH with every collector removed, so a real
# lizard, radon or multimetric on this machine cannot change the rows the
# assertions read.
COLLECTOR_NAMES=" scc lizard radon multimetric jscpd gocyclo gocognit dupl shellmetrics eslint type-coverage mypy pmd "
IFS=':' read -r -a path_dirs <<<"$PATH"
for dir in "${path_dirs[@]}"; do
  [[ -d "$dir" ]] || continue
  for exe in "$dir"/*; do
    [[ -f "$exe" && -x "$exe" ]] || continue
    name="${exe##*/}"
    [[ "$COLLECTOR_NAMES" == *" $name "* ]] && continue
    [[ -e "$EMPTY_PATH/$name" ]] || ln -s "$exe" "$EMPTY_PATH/$name"
  done
done
unset CODE_METRICS_DISABLE_BUNDLED

run_json() {
  # run_json <artifact fixture basename>...
  local args=()
  local name
  for name in "$@"; do args+=(--artifacts "$COVERAGE/$name"); done
  PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --json --all "$SOURCES" "${args[@]}" 2>/dev/null
}

# 1. A named artifact that does not exist is a usage error, not a silent skip.
PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES" --artifacts /nonexistent.info >/dev/null 2>&1
assert_eq "a named artifact that does not exist exits 2" 2 "$?"

# 2. No artifact named and none discoverable: a reduced result, never silence.
out="$(cd "$SCRATCH" && PATH="$STUBS:$EMPTY_PATH" HOME="$SCRATCH" CODE_METRICS_HOME="$SCRATCH" \
  bash "$SCRIPT" --json --all "$REPO_ROOT/$SOURCES" 2>/dev/null)"
rc=$?
assert_eq "no artifact anywhere still exits 0" 0 "$rc"
assert_doc "every run row is unavailable and names the paths searched" "$out" \
  'd["run"] and all(r["status"]=="unavailable" and "searched" in (r["reason"] or "") for r in d["run"])'
assert_doc "the document reports that it measured nothing" "$out" 'd["status"]=="empty"'
assert_contains "the reason lists a well-known artifact name" "$out" "coverage/lcov.info"

# 3. lcov-absolute-sf.info: absolute SF: paths normalize, and a join that
#    covers some of the scope says so rather than reading as zero coverage.
out="$(run_json lcov-absolute-sf.info)"
assert_matches "a partial join names its scope-file count" "$out" \
  'partial, [0-9]+ of [0-9]+ scope files'
assert_doc "the absolute SF: path joined to the repository-relative scope file" "$out" \
  'any(r["file"].endswith("cm-sample.ts") for r in d["measures"])'
assert_doc "every coverage row carries cov_source" "$out" \
  'd["measures"] and all(r["cov_source"] in ("artifact-region","line-range") for r in d["measures"])'

# 4. lcov-1x.info: the classic FN/FNDA pairing. The function is never entered,
#    so its coverage is 0 rather than the 1/6 its declaration line would give,
#    and its CRAP is comp squared plus comp.
out="$(run_json lcov-1x.info)"
assert_doc "a function with a hit flag of 0 reports 0 percent" "$out" \
  'any(r["function"]=="classify" and r["values"]["coverage_pct"]==0 and r["hit"]==0 for r in d["measures"])'
assert_doc "its CRAP is comp squared plus comp" "$out" \
  'any(r["function"]=="classify" and r["values"]["crap"]==r["values"]["cyclomatic"]**2+r["values"]["cyclomatic"] for r in d["measures"])'
assert_doc "the file row still reports the lines the artifact hit" "$out" \
  'any(r["function"] is None and r["values"]["lines_executable"]==6 and r["values"]["lines_hit"]==1 for r in d["measures"])'
assert_doc "a line-range join is labelled as one" "$out" \
  'any(r["function"]=="classify" and r["cov_source"]=="line-range" for r in d["measures"])'
# The Bash lane's collector (shellmetrics.csv) reports no function end lines.
assert_doc "bash CRAP is a visible not-applicable row, not a null" "$out" \
  'any(r["lane"]=="bash" and r["measure"]=="crap" and r["status"]=="not-applicable" for r in d["run"])'
assert_matches "the bash CRAP row says why" "$out" 'no function end lines'

# 5. coverage-py.json: the artifact's own per-function regions win.
out="$(run_json coverage-py.json)"
assert_doc "python function rows come from the artifact regions" "$out" \
  'len([r for r in d["measures"] if r["function"] and r["lane"]=="python"])==2 and all(r["cov_source"]=="artifact-region" for r in d["measures"] if r["function"] and r["lane"]=="python")'
assert_doc "the nested function is reported on its own" "$out" \
  'any(r["function"]=="classify.inner" and r["values"]["coverage_pct"]==100 for r in d["measures"])'
assert_doc "the outer function reports the CRAP of its own coverage" "$out" \
  'any(r["function"]=="classify" and r["values"]["coverage_pct"]==50.0 and r["values"]["crap"]==4.125 for r in d["measures"])'

# 5b. No complexity collector at all: file-level coverage still comes from the
#     dispatcher's own scope, and CRAP is unavailable with the collector's reason
#     rather than the scope reading as empty.
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" --json --all "$SOURCES" --artifacts "$COVERAGE/coverage-py.json" 2>/dev/null)"
rc=$?
assert_eq "no complexity collector still exits 0" 0 "$rc"
assert_doc "the python file row survives without any complexity row" "$out" \
  'any(r["function"] is None and r["lane"]=="python" and r["values"]["coverage_pct"] is not None for r in d["measures"])'
assert_doc "CRAP is unavailable and names the missing collector" "$out" \
  'any(r["lane"]=="python" and r["measure"]=="crap" and r["status"]=="unavailable" and "cyclomatic collector" in r["reason"] for r in d["run"])'

# 6. lcov-2.2.info: FNL/FNA with no FN record at all, so the end line and the
#    hit count come from the 2.2 records or not at all.
out="$(run_json lcov-2.2.info)"
assert_doc "the go function joins from the artifact region" "$out" \
  'any(r["function"]=="Classify" and r["cov_source"]=="artifact-region" and r["values"]["coverage_pct"]==100 for r in d["measures"])'
assert_doc "a fully covered function has CRAP equal to its complexity" "$out" \
  'any(r["function"]=="Classify" and r["values"]["crap"]==r["values"]["cyclomatic"] for r in d["measures"])'

# 7. cobertura.xml (the format kcov emits for Bash) and go-cover.out (a module
#    path rather than a repository path).
out="$(run_json cobertura.xml go-cover.out)"
assert_doc "the bash file row comes from the Cobertura report" "$out" \
  'any(r["file"].endswith("cm-sample.sh") and r["values"]["coverage_pct"]==80 for r in d["measures"])'
# A Go profile weighs statements, not lines: its four hit statements out of
# five are the 80% `go tool cover -func` prints, and it never says which lines
# carry them, so the line counts are null rather than a count of nothing.
assert_doc "the go profile joins by its unique basename" "$out" \
  'any(r["file"].endswith("cm-sample.go") and r["function"] is None and r["values"]["coverage_pct"]==80.0 and r["values"]["lines_executable"] is None for r in d["measures"])'
assert_doc "the go file row names the statement ratio as its basis" "$out" \
  'any(r["file"].endswith("cm-sample.go") and r["function"] is None and r["cov_source"]=="statement-ratio" for r in d["measures"])'
# The profile measures no lines at all, so the Go function's line counts are
# null. A 0 there would say the artifact looked at the range and found nothing
# executable in it, which is not what a statement profile reports.
assert_doc "a go function measured only by a profile reports null, not 0, lines" "$out" \
  'any(r["function"]=="Classify" and r["values"]["lines_executable"] is None and r["values"]["lines_hit"] is None and r["values"]["coverage_pct"] is None and r["values"]["crap"] is None for r in d["measures"])'
# Both lanes name the format they read. Go's single file is fully matched, so
# it is `ok`; the Cobertura report covers one of Bash's three, which is neither
# ok nor unavailable and must not let the document settle as complete.
assert_doc "both lanes name the format they read" "$out" \
  'sorted(r["collector"] for r in d["run"] if r["measure"]=="coverage" and r["lane"] in ("bash","go"))==["cobertura","go_cover"]'
assert_doc "the fully matched lane is ok and the half-matched one is partial" "$out" \
  'next(r["status"] for r in d["run"] if r["measure"]=="coverage" and r["lane"]=="go")=="ok" and next(r["status"] for r in d["run"] if r["measure"]=="coverage" and r["lane"]=="bash")=="partial"'
assert_doc "a lane measured in part keeps the document off complete" "$out" \
  'd["status"]=="partial"'

# 8. Every format at once, then the markdown the skill presents.
out="$(run_json lcov-1x.info lcov-2.2.info cobertura.xml coverage-py.json go-cover.out)"
assert_doc "--json is one code-metrics/v1 document for audit-coverage" "$out" \
  'd["schema"]=="code-metrics/v1" and d["skill"]=="audit-coverage"'
# All four measurable lanes read an artifact. Three match every scope file and
# are ok; Bash matches one of its three and says so rather than claiming both.
assert_doc "the four measurable lanes are all covered" "$out" \
  'sorted({r["lane"] for r in d["run"] if r["measure"]=="coverage" and r["status"] in ("ok","partial")})==["bash","go","python","typescript"]'
assert_doc "only the lane matched in part is partial" "$out" \
  '{r["lane"] for r in d["run"] if r["measure"]=="coverage" and r["status"]=="partial"}=={"bash"}'
assert_doc "no threshold produced a finding or a severity" "$out" \
  'all(t["reference"] is None for t in d["thresholds"]) and all(not r["over_reference"] for r in d["measures"])'
# Two artifacts measure cm-sample.go here: the profile weighs 4 of 5
# statements (80%) and lcov-2.2.info lists 6 lines all hit (100%). The
# profile's ratio is the file's exact native measure and wins, the row says
# so, and the line counts do not ride along as the counts behind a number
# they do not produce. The function row is line-based and keeps the region.
assert_doc "a go profile outranks a line artifact for the same file" "$out" \
  'any(r["file"].endswith("cm-sample.go") and r["function"] is None and r["values"]["coverage_pct"]==80.0 and r["cov_source"]=="statement-ratio" and r["values"]["lines_executable"] is None and r["values"]["lines_hit"] is None for r in d["measures"])'
assert_doc "both formats are still named as read for the go lane" "$out" \
  'all(f in next(r["collector"] for r in d["run"] if r["measure"]=="coverage" and r["lane"]=="go") for f in ("go_cover","lcov"))'
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES" --artifacts "$COVERAGE/coverage-py.json" 2>/dev/null)"
rc=$?
assert_eq "markdown exits 0" 0 "$rc"
assert_contains "markdown carries the run table" "$out" "Coverage of this run"
assert_contains "markdown states that a reference is not a bar" "$out" "never a bar"

# 9. Usage.
PATH="$EMPTY_PATH" bash "$SCRIPT" "$SOURCES/does-not-exist.py" >/dev/null 2>&1
assert_eq "a missing explicit scope path exits 2" 2 "$?"
PATH="$EMPTY_PATH" bash "$SCRIPT" --help 2>&1 | grep -q 'audit-coverage.sh \[--json\]'
assert_eq "--help prints usage" 0 "$?"
PATH="$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES" --artifacts >/dev/null 2>&1
assert_eq "--artifacts without a path exits 2" 2 "$?"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
