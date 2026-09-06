#!/usr/bin/env bash
# Regression tests for the audit-type-debt entry point (audit-type-debt.sh):
# the per-lane rows both collectors produce, the lanes that are
# not-applicable, the null reference, and what an absent tool looks like.
#
# Both tools are stubbed at runtime (design T13): a temporary bin/ prepended to
# a PATH filtered of every collector name carries a fake `type-coverage`
# replaying fixtures/tool-output/type-coverage.json and a fake `mypy` writing
# fixtures/tool-output/mypy-any-exprs.txt into the report directory it is
# given. Every case runs from a scratch working directory, because the
# type-coverage probe reads ./node_modules/typescript from the current
# directory; the fixture sources are passed as an absolute path.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-type-debt.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SOURCES="$PLUGIN_ROOT/scripts/fixtures/sources"
TC_CAPTURE="$PLUGIN_ROOT/scripts/fixtures/tool-output/type-coverage.json"
MYPY_CAPTURE="$PLUGIN_ROOT/scripts/fixtures/tool-output/mypy-any-exprs.txt"
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
# jq-free JSON assertions: a Python expression over the parsed document `d`.
assert_doc() {
  # assert_doc <name> <json> <python-expression>
  if printf '%s' "$2" | "$PY" -c "import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if ($3) else 1)" 2>/dev/null; then
    pass "$1"
  else
    fail "$1" "$3" "$(printf '%s' "$2" | head -c 800)"
  fi
}

WORK="$(mktemp -d)"
STUBS="$WORK/bin"
EMPTY_PATH="$WORK/empty"
HOME_DIR="$WORK/home"
mkdir -p "$STUBS" "$EMPTY_PATH" "$HOME_DIR"
trap 'rm -rf "$WORK"' EXIT

# EMPTY_PATH is the caller's PATH with every collector removed: a directory of
# symlinks to each executable on PATH except the tools the ladder names, so
# git, the coreutils, and the interpreter stay reachable while `mypy` and
# `type-coverage` do not (this machine may have either installed).
COLLECTOR_NAMES=" scc lizard radon multimetric jscpd gocyclo gocognit dupl shellmetrics type-coverage mypy pmd "
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

cat >"$STUBS/type-coverage" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf 'Version: 2.30.1\n'; exit 0; fi
cat "$TC_CAPTURE"
EOF
cat >"$STUBS/mypy" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf 'mypy 1.19.1 (compiled: yes)\n'; exit 0; fi
dir=""
prev=""
for arg in "\$@"; do
  [[ "\$prev" == "--any-exprs-report" ]] && dir="\$arg"
  prev="\$arg"
done
[[ -n "\$dir" ]] && mkdir -p "\$dir"
cp "$MYPY_CAPTURE" "\$dir/any-exprs.txt"
EOF
chmod +x "$STUBS/type-coverage" "$STUBS/mypy"

# A scratch working directory whose node_modules/typescript makes the
# type-coverage probe pass, and a bare one that makes it fail.
PROJECT="$WORK/project"
BARE="$WORK/bare"
mkdir -p "$PROJECT/node_modules/typescript" "$BARE"
printf '{"name": "typescript", "version": "5.9.3"}\n' >"$PROJECT/node_modules/typescript/package.json"

# The five lane fixtures this suite measures, named so the affected-tests
# runner maps them here: cm-sample.ts, cm_sample.py, cm-sample.sh,
# cm-sample.go, CmSample.cs.
for fixture in cm-sample.ts cm_sample.py cm-sample.sh cm-sample.go CmSample.cs; do
  [[ -f "$SOURCES/$fixture" ]] ||
    fail "the lane fixture $fixture exists" "a file at $SOURCES/$fixture" "missing"
done
pass "the five lane fixtures are present"

# 1. Both tools present: a percentage per typed lane, not-applicable elsewhere.
out="$(cd "$PROJECT" && PATH="$STUBS:$EMPTY_PATH" CODE_METRICS_HOME="$HOME_DIR" bash "$SCRIPT" --json --all "$SOURCES")"
rc=$?
assert_eq "--json exits 0 with both collectors stubbed" 0 "$rc"
assert_doc "the document is code-metrics/v1 for audit-type-debt" "$out" \
  'd["schema"]=="code-metrics/v1" and d["skill"]=="audit-type-debt"'
assert_doc "the typescript row carries type_coverage_pct from type-coverage.json" "$out" \
  'next(r for r in d["measures"] if r["lane"]=="typescript")["values"]["type_coverage_pct"]==55.55'
assert_doc "the typescript row is per lane, not per file" "$out" \
  'all(r["file"] is None and r["function"] is None for r in d["measures"])'
assert_doc "the python row carries any_expressions from mypy-any-exprs.txt" "$out" \
  'next(r for r in d["measures"] if r["lane"]=="python")["values"]["any_expressions"]==0'
assert_doc "the python row also carries mypy's own coverage percentage" "$out" \
  'next(r for r in d["measures"] if r["lane"]=="python")["values"]["type_coverage_pct"]==100.0'
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

# 2. The markdown rendering carries the coverage table.
out="$(cd "$PROJECT" && PATH="$STUBS:$EMPTY_PATH" CODE_METRICS_HOME="$HOME_DIR" bash "$SCRIPT" --all "$SOURCES")"
rc=$?
assert_eq "markdown exits 0" 0 "$rc"
assert_contains "markdown carries the run table" "$out" "## Coverage of this run"
assert_contains "markdown names the type-coverage collector" "$out" "type-coverage 2.30.1"
assert_contains "markdown prints the null reference" "$out" "| type_coverage | null |"

# 3. type-coverage resolves but typescript does not: the probe's requirement
# reaches the run row's reason (the dispatcher relays the adapter's install
# hint, which names both halves of the requirement).
out="$(cd "$BARE" && PATH="$STUBS:$EMPTY_PATH" CODE_METRICS_HOME="$HOME_DIR" bash "$SCRIPT" --json --all "$SOURCES")"
rc=$?
assert_eq "exit 0 when the typescript probe fails" 0 "$rc"
assert_doc "the typescript row is unavailable, not ok" "$out" \
  'next(r for r in d["run"] if r["lane"]=="typescript")["status"]=="unavailable"'
assert_doc "its reason states that type-coverage needs a resolvable typescript" "$out" \
  '"needs a resolvable typescript" in next(r for r in d["run"] if r["lane"]=="typescript")["reason"]'
assert_doc "the python lane still reports while typescript cannot" "$out" \
  'any(r["lane"]=="python" and r["status"]=="ok" for r in d["run"]) and d["status"]=="partial"'

# 4. Neither tool present: exit 0, nothing measured, the install hint is named.
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

# 5. Usage.
(cd "$BARE" && PATH="$EMPTY_PATH" bash "$SCRIPT" "$SOURCES/does-not-exist.ts" >/dev/null 2>&1)
assert_eq "a missing explicit path exits 2" 2 "$?"
bash "$SCRIPT" --help 2>&1 | grep -q 'audit-type-debt.sh \[--json\]'
assert_eq "--help prints usage" 0 "$?"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
