#!/usr/bin/env bash
# Regression tests for the audit-complexity entry point (audit-complexity.sh):
# option parsing, the references it prints with their provenance, the lanes it
# reports as unavailable, and exit-code passthrough from dispatch.sh.
# Collectors are stubbed at runtime: a temporary bin/ prepended to a filtered
# PATH carries fake `lizard`, `radon`, `multimetric`, `gocognit` and
# `shellmetrics` replaying the committed captures under
# fixtures/tool-output/ (design T13; nothing executable is committed).
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-complexity.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SOURCES="plugins/code-metrics/scripts/fixtures/sources"
CAPTURES="$PLUGIN_ROOT/scripts/fixtures/tool-output"
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
    fail "$1" "$3" "$(printf '%s' "$2" | head -c 600)"
  fi
}

STUBS="$(mktemp -d)"
EMPTY_PATH="$(mktemp -d)"
trap 'rm -rf "$STUBS" "$EMPTY_PATH"' EXIT

cat >"$STUBS/lizard" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '1.24.0\n'; exit 0; fi
cat "$CAPTURES/lizard.csv"
EOF
cat >"$STUBS/radon" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '6.0.1\n'; exit 0; fi
if [[ "\${1:-}" == "cc" ]]; then cat "$CAPTURES/radon-cc.json"; exit 0; fi
if [[ "\${1:-}" == "hal" ]]; then cat "$CAPTURES/radon-hal.json"; exit 0; fi
exit 0
EOF
cat >"$STUBS/multimetric" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '2.4.4\n'; exit 0; fi
cat "$CAPTURES/multimetric.json"
EOF
cat >"$STUBS/gocognit" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in -version | --version) printf 'v1.2.1\n'; exit 0 ;; esac
cat "$CAPTURES/gocognit.json"
EOF
cat >"$STUBS/shellmetrics" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then printf '0.5.0\n'; exit 0; fi
cat "$CAPTURES/shellmetrics.csv"
EOF
chmod +x "$STUBS"/*

# EMPTY_PATH is the caller's PATH with every collector removed: a directory of
# symlinks to each executable on PATH except the tools the ladder names, so the
# coreutils, git and the interpreter stay reachable while a real lizard, radon,
# eslint or gocyclo on this machine cannot shadow the stubs or the assertions.
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

# 1. Every stub resolves: the document, its references, and its run table.
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --json --all "$SOURCES")"
rc=$?
assert_eq "--json exits 0" 0 "$rc"
assert_doc "--json prints a code-metrics/v1 document for audit-complexity" "$out" \
  'd["schema"]=="code-metrics/v1" and d["skill"]=="audit-complexity" and d["run"]'
assert_doc "cyclomatic cites ISO/IEC 5055 8.2.117 at a reference of 20" "$out" \
  'any(t["measure"]=="cyclomatic" and t["reference"]==20 and "8.2.117" in t["provenance"] for t in d["thresholds"])'
assert_doc "cognitive and halstead_difficulty have no reference" "$out" \
  'all(t["reference"] is None for t in d["thresholds"] if t["measure"] in ("cognitive","halstead_difficulty")) and len([t for t in d["thresholds"] if t["measure"] in ("cognitive","halstead_difficulty")])==2'
assert_doc "python cognitive is unavailable, not silent" "$out" \
  'any(r["lane"]=="python" and r["measure"]=="cognitive" and r["status"]=="unavailable" and r["reason"] for r in d["run"])'
assert_doc "bash cognitive is unavailable, not silent" "$out" \
  'any(r["lane"]=="bash" and r["measure"]=="cognitive" and r["status"]=="unavailable" and r["reason"] for r in d["run"])'
assert_doc "the python fixture carries function ranges for the CRAP join" "$out" \
  'any(r["file"].endswith("cm_sample.py") and r["start_line"]==9 and r["end_line"]==20 for r in d["measures"])'
assert_doc "the go lane reports cognitive complexity from gocognit" "$out" \
  'any(r["lane"]=="go" and r["values"].get("cognitive")==2 for r in d["measures"])'
assert_doc "the bash lane reports cyclomatic complexity from shellmetrics" "$out" \
  'any(r["lane"]=="bash" and r["values"].get("cyclomatic")==3 for r in d["measures"])'
assert_doc "halstead difficulty is reported and never fabricated as zero" "$out" \
  'all(r["values"]["halstead_difficulty"] for r in d["measures"] if "halstead_difficulty" in r["values"])'
# The five lane fixtures by name (cm-sample.ts, cm_sample.py, cm-sample.sh,
# cm-sample.go, CmSample.cs): the assertion is also what maps them to this suite.
assert_doc "the four measurable fixtures are measured and CmSample.cs is deferred" "$out" \
  'sorted({r["file"].rsplit("/",1)[1] for r in d["measures"]})==["cm-sample.go","cm-sample.sh","cm-sample.ts","cm_sample.py"] and any(r["lane"]=="dotnet" and r["status"]=="deferred" for r in d["run"])'

# 2. The markdown rendering opens with the coverage table.
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES")"
rc=$?
assert_eq "markdown exits 0" 0 "$rc"
assert_contains "markdown carries the run table" "$out" "Coverage of this run"
assert_contains "markdown carries the cited cyclomatic reference" "$out" "8.2.117"
assert_contains "markdown states that a reference is not a bar" "$out" "never a bar"

# 3. Every collector absent: exit 0, status empty, nothing measured silently.
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" --json --all "$SOURCES")"
rc=$?
assert_eq "exit 0 when no collector resolved" 0 "$rc"
assert_doc "status empty and every run row non-ok with a reason" "$out" \
  'd["status"]=="empty" and d["run"] and all(r["status"]!="ok" and r["reason"] for r in d["run"]) and d["measures"]==[]'
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" --all "$SOURCES")"
assert_contains "the all-unavailable run renders the Measured nothing headline" "$out" "Measured nothing"

# 4. Usage.
PATH="$EMPTY_PATH" bash "$SCRIPT" "$SOURCES/does-not-exist.py" >/dev/null 2>&1
assert_eq "a missing explicit path exits 2" 2 "$?"
PATH="$EMPTY_PATH" bash "$SCRIPT" --help 2>&1 | grep -q 'audit-complexity.sh \[--json\]'
assert_eq "--help prints usage" 0 "$?"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
