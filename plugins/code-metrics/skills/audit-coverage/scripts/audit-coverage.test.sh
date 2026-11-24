#!/usr/bin/env bash
# test-scope: plugins/code-metrics/scripts/collectors/*.py plugins/code-metrics/scripts/parsers/*.py plugins/code-metrics/scripts/fixtures/* plugins/code-metrics/scripts/yaml_subset.py
# test-scope: docs/conventions/ecosystems/*.yaml # runs from the repo root, so the config resolver reads its lanes
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

FAILED=0
CASE_NUM=0
# shellcheck source=../../../scripts/test-helpers.sh
source "$PLUGIN_ROOT/scripts/test-helpers.sh"

assert_matches() {
  if grep -Eq "$3" <<<"$2"; then
    pass "$1"
  else
    fail "$1" "matches: $3" "$(printf '%s' "$2" | head -c 400)"
  fi
}

STUBS="$(mktemp -d)"
EMPTY_PATH="$(mktemp -d)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$STUBS" "$EMPTY_PATH" "$SCRATCH"' EXIT
export CODE_METRICS_REPORT_DIR="$STUBS/reports"

cat >"$STUBS/lizard" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '1.24.0\n'; exit 0; fi
sed "s#\${CM_TEST_SUBDIR:-@unset@}##g" "$CAPTURES/lizard.csv"
EOF
cat >"$STUBS/shellmetrics" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '0.5.0\n'; exit 0; fi
sed "s#\${CM_TEST_SUBDIR:-@unset@}##g" "$CAPTURES/shellmetrics.csv"
EOF
chmod +x "$STUBS"/*

# shellcheck source=../../../scripts/tool-free-path.sh
source "$PLUGIN_ROOT/scripts/tool-free-path.sh"
cm_assert_tool_free_path "$EMPTY_PATH"
unset CODE_METRICS_DISABLE_BUNDLED

run_json() {
  local args=()
  local name
  for name in "$@"; do args+=(--artifacts "$COVERAGE/$name"); done
  PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --json --all "$SOURCES" "${args[@]}" 2>/dev/null
}

PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES" --artifacts /nonexistent.info >/dev/null 2>&1
assert_eq "a named artifact that does not exist exits 2" 2 "$?"

out="$(cd "$SCRATCH" && PATH="$STUBS:$EMPTY_PATH" HOME="$SCRATCH" CODE_METRICS_HOME="$SCRATCH" \
  bash "$SCRIPT" --json --all "$REPO_ROOT/$SOURCES" 2>/dev/null)"
rc=$?
assert_eq "no artifact anywhere still exits 0" 0 "$rc"
assert_doc "every language-lane run row is unavailable and names the paths searched" "$out" \
  'd["run"] and all(r["status"]=="unavailable" and "searched" in (r["reason"] or "") for r in d["run"] if r["lane"]!="other") and all(r["status"]=="not-applicable" for r in d["run"] if r["lane"]=="other")'
assert_doc "the document reports that it measured nothing" "$out" 'd["status"]=="empty"'
assert_contains "the reason lists a well-known artifact name" "$out" "coverage/lcov.info"

out="$(run_json lcov-absolute-sf.info)"
assert_matches "a partial join names its scope-file count" "$out" \
  'partial, [0-9]+ of [0-9]+ scope files'
assert_doc "the absolute SF: path joined to the repository-relative scope file" "$out" \
  'any(r["file"].endswith("cm-sample.ts") for r in d["measures"])'
assert_doc "every coverage row carries cov_source" "$out" \
  'd["measures"] and all(r["cov_source"] in ("artifact-region","line-range") for r in d["measures"])'

out="$(run_json lcov-1x.info)"
assert_doc "a function with a hit flag of 0 reports 0 percent" "$out" \
  'any(r["function"]=="classify" and r["values"]["coverage_pct"]==0 and r["hit"]==0 for r in d["measures"])'
assert_doc "its CRAP is comp squared plus comp" "$out" \
  'any(r["function"]=="classify" and r["values"]["crap"]==r["values"]["cyclomatic"]**2+r["values"]["cyclomatic"] for r in d["measures"])'
assert_doc "the file row still reports the lines the artifact hit" "$out" \
  'any(r["function"] is None and r["values"]["lines_executable"]==6 and r["values"]["lines_hit"]==1 for r in d["measures"])'
assert_doc "a line-range join is labeled as one" "$out" \
  'any(r["function"]=="classify" and r["cov_source"]=="line-range" for r in d["measures"])'
assert_doc "bash CRAP is a visible not-applicable row, not a null" "$out" \
  'any(r["lane"]=="bash" and r["measure"]=="crap" and r["status"]=="not-applicable" for r in d["run"])'
assert_matches "the bash CRAP row says why" "$out" 'no function end lines'

out="$(run_json coverage-py.json)"
assert_doc "python function rows come from the artifact regions" "$out" \
  'len([r for r in d["measures"] if r["function"] and r["lane"]=="python"])==2 and all(r["cov_source"]=="artifact-region" for r in d["measures"] if r["function"] and r["lane"]=="python")'
assert_doc "the nested function is reported on its own" "$out" \
  'any(r["function"]=="classify.inner" and r["values"]["coverage_pct"]==100 for r in d["measures"])'
assert_doc "the outer function reports the CRAP of its own coverage" "$out" \
  'any(r["function"]=="classify" and r["values"]["coverage_pct"]==50.0 and r["values"]["crap"]==4.125 for r in d["measures"])'

out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" --json --all "$SOURCES" --artifacts "$COVERAGE/coverage-py.json" 2>/dev/null)"
rc=$?
assert_eq "no complexity collector still exits 0" 0 "$rc"
assert_doc "the python file row survives without any complexity row" "$out" \
  'any(r["function"] is None and r["lane"]=="python" and r["values"]["coverage_pct"] is not None for r in d["measures"])'
assert_doc "CRAP is unavailable and names the missing collector" "$out" \
  'any(r["lane"]=="python" and r["measure"]=="crap" and r["status"]=="unavailable" and "cyclomatic collector" in r["reason"] for r in d["run"])'

out="$(run_json lcov-2.2.info)"
assert_doc "the go function joins from the artifact region" "$out" \
  'any(r["function"]=="Classify" and r["cov_source"]=="artifact-region" and r["values"]["coverage_pct"]==100 for r in d["measures"])'
assert_doc "a fully covered function has CRAP equal to its complexity" "$out" \
  'any(r["function"]=="Classify" and r["values"]["crap"]==r["values"]["cyclomatic"] for r in d["measures"])'

out="$(run_json cobertura.xml go-cover.out)"
assert_doc "the bash file row comes from the Cobertura report" "$out" \
  'any(r["file"].endswith("cm-sample.sh") and r["values"]["coverage_pct"]==80 for r in d["measures"])'
assert_doc "the go profile joins by its unique basename" "$out" \
  'any(r["file"].endswith("cm-sample.go") and r["function"] is None and r["values"]["coverage_pct"]==80.0 and r["values"]["lines_executable"] is None for r in d["measures"])'
assert_doc "the go file row names the statement ratio as its basis" "$out" \
  'any(r["file"].endswith("cm-sample.go") and r["function"] is None and r["cov_source"]=="statement-ratio" for r in d["measures"])'
assert_doc "a go function measured only by a profile reports null, not 0, lines" "$out" \
  'any(r["function"]=="Classify" and r["values"]["lines_executable"] is None and r["values"]["lines_hit"] is None and r["values"]["coverage_pct"] is None and r["values"]["crap"] is None for r in d["measures"])'
assert_doc "both lanes name the format they read" "$out" \
  'sorted(r["collector"] for r in d["run"] if r["measure"]=="coverage" and r["lane"] in ("bash","go"))==["cobertura","go_cover"]'
assert_doc "the fully matched lane is ok and the half-matched one is partial" "$out" \
  'next(r["status"] for r in d["run"] if r["measure"]=="coverage" and r["lane"]=="go")=="ok" and next(r["status"] for r in d["run"] if r["measure"]=="coverage" and r["lane"]=="bash")=="partial"'
assert_doc "a lane measured in part keeps the document off complete" "$out" \
  'd["status"]=="partial"'

out="$(run_json lcov-1x.info lcov-2.2.info cobertura.xml coverage-py.json go-cover.out)"
assert_doc "--json is one code-metrics/v2 document for audit-coverage" "$out" \
  'd["schema"]=="code-metrics/v2" and d["skill"]=="audit-coverage"'
assert_doc "the four measurable lanes are all covered" "$out" \
  'sorted({r["lane"] for r in d["run"] if r["measure"]=="coverage" and r["status"] in ("ok","partial")})==["bash","go","python","typescript"]'
assert_doc "only the lane matched in part is partial" "$out" \
  '{r["lane"] for r in d["run"] if r["measure"]=="coverage" and r["status"]=="partial"}=={"bash"}'
assert_doc "no threshold produced a finding or a severity" "$out" \
  'all(t["reference"] is None for t in d["thresholds"]) and all(not r["over_reference"] for r in d["measures"])'
assert_doc "a go profile outranks a line artifact for the same file" "$out" \
  'any(r["file"].endswith("cm-sample.go") and r["function"] is None and r["values"]["coverage_pct"]==80.0 and r["cov_source"]=="statement-ratio" and r["values"]["lines_executable"] is None and r["values"]["lines_hit"] is None for r in d["measures"])'
assert_doc "both formats are still named as read for the go lane" "$out" \
  'all(f in next(r["collector"] for r in d["run"] if r["measure"]=="coverage" and r["lane"]=="go") for f in ("go_cover","lcov"))'
sub_out="$(cd "$COVERAGE/.." && CM_TEST_SUBDIR="plugins/code-metrics/scripts/fixtures/" PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --json --all sources \
  --artifacts "$COVERAGE/lcov-1x.info" --artifacts "$COVERAGE/lcov-2.2.info" --artifacts "$COVERAGE/cobertura.xml" \
  --artifacts "$COVERAGE/coverage-py.json" --artifacts "$COVERAGE/go-cover.out" 2>/dev/null)"
assert_eq "the run from a subdirectory exits 0" 0 "$?"
same="$(printf '%s\n\x1e%s' "$out" "$sub_out" | "$PY" -c '
import json, sys
a, b = (json.loads(part) for part in sys.stdin.read().split("\x1e"))
files = lambda d: sorted(r["file"] for r in d["measures"] if r["file"])
missing = lambda d: sorted((r["lane"], r["measure"], tuple(r.get("missing", []))) for r in d["run"])
reasons = lambda d: sorted((r["lane"], r["measure"], r["reason"] or "") for r in d["run"])
ok = (files(a) == files(b) and files(a) and missing(a) == missing(b) and reasons(a) == reasons(b)
      and a["root"] == b["root"] and a["scan_root"] == "." and b["scan_root"] == "plugins/code-metrics/scripts/fixtures"
      and a["summary"] == b["summary"])
raise SystemExit(0 if ok else 1)
' && echo same)"
assert_eq "coverage from a subdirectory: same files, missing lists, reasons and root as from the root" "same" "$same"
assert_doc "the coverage document's paths and missing lists are repository-root-relative" "$sub_out" \
  'all(r["file"].startswith("plugins/") for r in d["measures"] if r["file"]) and all(p.startswith("plugins/") for r in d["run"] for p in r.get("missing", []))'
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES" --artifacts "$COVERAGE/coverage-py.json" 2>/dev/null)"
rc=$?
assert_eq "markdown exits 0" 0 "$rc"
assert_contains "markdown carries the run table" "$out" "Coverage of this run"
assert_contains "markdown states that a reference is not a bar" "$out" "never a bar"

team="$(mktemp -d)"
printf 'scope:\n  registries: [plugins/code-metrics/scripts/fixtures/registry/cluster.txt]\n' >"$team/team.yaml"
"$PY" "$PLUGIN_ROOT/scripts/resolve-config.py" "$team/team.yaml" --ladder "$PLUGIN_ROOT/scripts/collector-ladder.tsv" >"$team/resolved.json"
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --json --config "$team/resolved.json" --all "$SOURCES" --artifacts "$COVERAGE/lcov-cluster.info" 2>/dev/null)"
rc=$?
assert_eq "a registry run exits 0" 0 "$rc"
assert_doc "the two shared-utils copies collapse to one row standing for both files" "$out" \
  'len([r for r in d["measures"] if r["file"].endswith("shared-utils.sh")])==1 and next(r for r in d["measures"] if r["file"].endswith("shared-utils.sh"))["replicas"]["count"]==2 and "replicated" in next(r for r in d["measures"] if r["file"].endswith("shared-utils.sh"))["labels"]'
assert_doc "the summary counts the collapsed file once per row it stands for" "$out" \
  'd["summary"]["files"]==len({f for r in d["measures"] for f in [r["file"], *(r.get("replicas") or {}).get("files", [])]})'
rm -rf "$team"

PATH="$EMPTY_PATH" bash "$SCRIPT" "$SOURCES/does-not-exist.py" >/dev/null 2>&1
assert_eq "a missing explicit scope path exits 2" 2 "$?"
grep -q 'audit-coverage.sh \[--json\]' < <(PATH="$EMPTY_PATH" bash "$SCRIPT" --help 2>&1)
assert_eq "--help prints usage" 0 "$?"
PATH="$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES" --artifacts >/dev/null 2>&1
assert_eq "--artifacts without a path exits 2" 2 "$?"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
