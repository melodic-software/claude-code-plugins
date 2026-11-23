#!/usr/bin/env bash
# test-scope: plugins/code-metrics/scripts/collectors/*.py plugins/code-metrics/scripts/fixtures/* plugins/code-metrics/scripts/yaml_subset.py
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-type-debt.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SOURCES="$PLUGIN_ROOT/scripts/fixtures/sources"
TC_CAPTURE="$PLUGIN_ROOT/scripts/fixtures/tool-output/type-coverage.json"
MYPY_CAPTURE="$PLUGIN_ROOT/scripts/fixtures/tool-output/mypy-any-exprs.txt"
MYPY_ABORTED="$PLUGIN_ROOT/scripts/fixtures/tool-output/mypy-any-exprs-aborted.txt"
cd "$REPO_ROOT" || exit 2

FAILED=0
CASE_NUM=0
DOC_EXCERPT_BYTES=800
# shellcheck source=../../../scripts/test-helpers.sh
source "$PLUGIN_ROOT/scripts/test-helpers.sh"

WORK="$(mktemp -d)"
STUBS="$WORK/bin"
EMPTY_PATH="$WORK/empty"
HOME_DIR="$WORK/home"
mkdir -p "$STUBS" "$EMPTY_PATH" "$HOME_DIR"
trap 'rm -rf "$WORK"' EXIT
export CODE_METRICS_REPORT_DIR="$WORK/reports"

# shellcheck source=../../../scripts/tool-free-path.sh
source "$PLUGIN_ROOT/scripts/tool-free-path.sh"
cm_assert_tool_free_path "$EMPTY_PATH"

cat >"$STUBS/type-coverage" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf 'Version: 2.30.1\n'; exit 0; fi
cat "$TC_CAPTURE"
EOF
mypy_stub() {
  cat <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf 'mypy 1.19.1 (compiled: yes)\n'; exit 0; fi
dir=""
prev=""
for arg in "\$@"; do
  [[ "\$prev" == "--any-exprs-report" ]] && dir="\$arg"
  prev="\$arg"
done
[[ -n "\$dir" ]] && mkdir -p "\$dir"
cp "$1" "\$dir/any-exprs.txt"
EOF
}
mypy_stub "$MYPY_CAPTURE" >"$STUBS/mypy"
cat >"$STUBS/node" <<'EOF'
#!/usr/bin/env bash
if [[ ! -f node_modules/typescript/package.json ]]; then
  printf '%s\n' "Error: Cannot find module 'typescript'" >&2
  exit 1
fi
printf '%s\n' '["plugins/code-metrics/scripts/fixtures/sources/cm-sample.ts"]'
EOF
chmod +x "$STUBS/type-coverage" "$STUBS/mypy" "$STUBS/node"

PROJECT="$WORK/project"
BARE="$WORK/bare"
mkdir -p "$PROJECT/node_modules/typescript" "$BARE"
printf '{"name": "typescript", "version": "5.9.3"}\n' >"$PROJECT/node_modules/typescript/package.json"
SCOPE="plugins/code-metrics/scripts/fixtures/sources"
mkdir -p "$PROJECT/${SCOPE%/*}"
cp -R "$SOURCES" "$PROJECT/$SCOPE"

for fixture in cm-sample.ts cm_sample.py cm-sample.sh cm-sample.go CmSample.cs; do
  [[ -f "$SOURCES/$fixture" ]] ||
    fail "the lane fixture $fixture exists" "a file at $SOURCES/$fixture" "missing"
done
pass "the five lane fixtures are present"

out="$(cd "$PROJECT" && PATH="$STUBS:$EMPTY_PATH" CODE_METRICS_HOME="$HOME_DIR" bash "$SCRIPT" --json --all "$SCOPE")"
rc=$?
assert_eq "--json exits 0 with both collectors stubbed" 0 "$rc"
assert_doc "the document is code-metrics/v2 for audit-type-debt" "$out" \
  'd["schema"]=="code-metrics/v2" and d["skill"]=="audit-type-debt"'
assert_doc "the typescript lane row carries type_coverage_pct from type-coverage.json" "$out" \
  'next(r for r in d["measures"] if r["lane"]=="typescript" and r["file"] is None)["values"]["type_coverage_pct"]==55.55'
assert_doc "each lane has one file row per scope file plus one lane-total row" "$out" \
  'sorted(r["file"].rsplit("/",1)[-1] for r in d["measures"] if r["file"])==["cm-sample.ts","cm_sample.py"] and sorted(r["lane"] for r in d["measures"] if r["file"] is None and "lane-total" in r["labels"])==["python","typescript"] and all(r["function"] is None for r in d["measures"])'
assert_doc "the typescript file row carries the occurrences listed for that file and nothing else" "$out" \
  'next(r for r in d["measures"] if r["lane"]=="typescript" and r["file"])["values"]=={"type_coverage_pct":None,"typed_identifiers":None,"total_identifiers":None,"any_count":4}'
assert_doc "the summary counts the file rows" "$out" 'd["summary"]["files"]==2'
assert_doc "the python file row carries any_expressions from mypy-any-exprs.txt" "$out" \
  'next(r for r in d["measures"] if r["lane"]=="python" and r["file"])["values"]["any_expressions"]==0'
assert_doc "the python lane row also carries mypy's own coverage percentage" "$out" \
  'next(r for r in d["measures"] if r["lane"]=="python" and r["file"] is None)["values"]["type_coverage_pct"]==100.0'
assert_doc "a silent success leaves the ok row's reason null" "$out" \
  'all(r["reason"] is None for r in d["run"] if r["status"]=="ok")'
assert_doc "the dotnet row is not-applicable with the C# sentence" "$out" \
  'next(r for r in d["run"] if r["lane"]=="dotnet" and r["measure"]=="type_coverage")["status"]=="not-applicable"'
assert_doc "the dotnet reason says a count is not comparable to a ratio" "$out" \
  '"not comparable to a ratio" in next(r for r in d["run"] if r["lane"]=="dotnet")["reason"]'
assert_doc "bash and go are not-applicable with a reason" "$out" \
  'all(next(r for r in d["run"] if r["lane"]==l)["status"]=="not-applicable" and next(r for r in d["run"] if r["lane"]==l)["reason"] for l in ("bash","go"))'
assert_doc "the type_coverage reference is null by design" "$out" \
  'next(t for t in d["thresholds"] if t["measure"]=="type_coverage")["reference"] is None'
assert_doc "no row is counted over a reference" "$out" \
  'all(r["over_reference"]==[] for r in d["measures"])'

out="$(cd "$PROJECT" && PATH="$STUBS:$EMPTY_PATH" CODE_METRICS_HOME="$HOME_DIR" bash "$SCRIPT" --all "$SCOPE")"
rc=$?
assert_eq "markdown exits 0" 0 "$rc"
assert_contains "markdown carries the run table" "$out" "## Coverage of this run"
assert_contains "markdown names the type-coverage collector" "$out" "type-coverage 2.30.1"
assert_contains "markdown prints the null reference" "$out" "| type_coverage | null |"
assert_contains "markdown lists the python file row" "$out" "cm_sample.py |"
assert_contains "markdown marks the lane row" "$out" "| lane-total |"
assert_contains "markdown counts the files measured" "$out" "Files: 2."

out="$(cd "$BARE" && PATH="$STUBS:$EMPTY_PATH" CODE_METRICS_HOME="$HOME_DIR" bash "$SCRIPT" --json --all "$SOURCES")"
rc=$?
assert_eq "exit 0 when the typescript probe fails" 0 "$rc"
assert_doc "the typescript row is unavailable, not ok" "$out" \
  'next(r for r in d["run"] if r["lane"]=="typescript")["status"]=="unavailable"'
assert_doc "its reason states that type-coverage needs a resolvable typescript" "$out" \
  '"needs a resolvable typescript" in next(r for r in d["run"] if r["lane"]=="typescript")["reason"]'
assert_doc "the python lane still reports while typescript cannot" "$out" \
  'any(r["lane"]=="python" and r["status"]=="ok" for r in d["run"]) and d["status"]=="partial"'

ABORT_STUBS="$WORK/abort-stubs"
mkdir -p "$ABORT_STUBS"
cp "$STUBS/type-coverage" "$STUBS/node" "$ABORT_STUBS/"
{
  mypy_stub "$MYPY_ABORTED"
  cat <<'EOF'
printf '%s\n' 'b/lib/x.py: error: Duplicate module named "lib.x" (also at "a/lib/x.py")' >&2
exit 2
EOF
} >"$ABORT_STUBS/mypy"
chmod +x "$ABORT_STUBS/mypy"
out="$(cd "$PROJECT" && PATH="$ABORT_STUBS:$EMPTY_PATH" CODE_METRICS_HOME="$HOME_DIR" bash "$SCRIPT" --json --all "$SCOPE")"
rc=$?
assert_eq "exit 0 when mypy aborts before analysis" 0 "$rc"
assert_doc "the python row is unavailable and no python measure is emitted" "$out" \
  'next(r for r in d["run"] if r["lane"]=="python")["status"]=="unavailable" and not any(r["lane"]=="python" for r in d["measures"])'
assert_doc "its reason carries mypy's own duplicate-module message" "$out" \
  '"Duplicate module named" in next(r for r in d["run"] if r["lane"]=="python")["reason"]'
assert_doc "the typescript lane still reports while mypy cannot" "$out" \
  'any(r["lane"]=="typescript" and r["status"]=="ok" for r in d["run"]) and d["status"]=="partial"'

ERROR_STUBS="$WORK/error-stubs"
mkdir -p "$ERROR_STUBS"
cp "$STUBS/type-coverage" "$STUBS/node" "$ERROR_STUBS/"
{
  mypy_stub "$MYPY_CAPTURE"
  cat <<'EOF'
printf '%s\n' 'cm_sample.py:1: error: Library stubs not installed for "yaml"  [import-untyped]' 'cm_sample.py:9: error: Incompatible return value type  [return-value]'
exit 1
EOF
} >"$ERROR_STUBS/mypy"
chmod +x "$ERROR_STUBS/mypy"
out="$(cd "$PROJECT" && PATH="$ERROR_STUBS:$EMPTY_PATH" CODE_METRICS_HOME="$HOME_DIR" bash "$SCRIPT" --json --all "$SCOPE")"
rc=$?
assert_eq "exit 0 when mypy reports type errors" 0 "$rc"
assert_doc "the python run row is ok and its reason counts the errors and missing stubs" "$out" \
  'next(r for r in d["run"] if r["lane"]=="python")["status"]=="ok" and next(r for r in d["run"] if r["lane"]=="python")["reason"]=="mypy reported 2 errors (1 missing stub)"'
assert_doc "the python lane row is labeled and the file row is not" "$out" \
  'next(r for r in d["measures"] if r["lane"]=="python" and r["file"] is None)["labels"]==["lane-total","mypy-reported-errors"] and next(r for r in d["measures"] if r["lane"]=="python" and r["file"])["labels"]==[]'

out="$(cd "$BARE" && PATH="$EMPTY_PATH" CODE_METRICS_HOME="$HOME_DIR" bash "$SCRIPT" --json --all "$SOURCES")"
rc=$?
assert_eq "exit 0 when no collector resolves" 0 "$rc"
assert_doc "status empty and no measures" "$out" 'd["status"]=="empty" and d["measures"]==[]'
assert_doc "the typescript reason names the install hint" "$out" \
  '"npm install --save-dev type-coverage" in next(r for r in d["run"] if r["lane"]=="typescript")["reason"]'
assert_doc "the python reason names the mypy install hint" "$out" \
  '"pip install mypy" in next(r for r in d["run"] if r["lane"]=="python")["reason"]'
assert_doc "unavailable lists both typed lanes" "$out" \
  'sorted(d["unavailable"])==["python/type_coverage","typescript/type_coverage"]'

(cd "$BARE" && PATH="$EMPTY_PATH" bash "$SCRIPT" "$SOURCES/does-not-exist.ts" >/dev/null 2>&1)
assert_eq "a missing explicit path exits 2" 2 "$?"
grep -q 'audit-type-debt.sh \[--json\]' < <(bash "$SCRIPT" --help 2>&1)
assert_eq "--help prints usage" 0 "$?"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
