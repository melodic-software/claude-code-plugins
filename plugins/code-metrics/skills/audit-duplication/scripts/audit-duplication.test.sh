#!/usr/bin/env bash
# Regression tests for the audit-duplication entry point
# (audit-duplication.sh): the sanctioned-replication exclusion, the tunables it
# exports for the collector adapters, option parsing, and exit codes.
#
# jscpd is stubbed at runtime: a temporary directory prepended to PATH holds a
# fake `jscpd` that writes the committed capture
# scripts/fixtures/tool-output/jscpd.json into the --output directory the
# adapter passes and exits 1, the reporting exit code the contract says is not
# a failure (design T13; no executable is committed). The fixture cluster is
# scripts/fixtures/sources/cluster/{alpha,beta}/shared/shared-utils.sh and the
# registry that sanctions it is scripts/fixtures/registry/cluster.txt.
#
# The last case is the Brief's own: this repository's real
# plugins/*/hooks/hook-utils.sh cluster against
# scripts/cross-plugin-source-registry.txt. It runs only when a real `jscpd`
# already resolves on PATH, which this plugin never installs, and otherwise
# prints a visible SKIP line.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-duplication.sh"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
FIXTURES="plugins/code-metrics/scripts/fixtures"
CLUSTER="$FIXTURES/sources/cluster"
CLUSTER_REGISTRY="$FIXTURES/registry/cluster.txt"
CAPTURE="$REPO_ROOT/$FIXTURES/tool-output/jscpd.json"
REAL_REGISTRY="scripts/cross-plugin-source-registry.txt"
cd "$REPO_ROOT" || exit 2
PY=python3
command -v python3 >/dev/null 2>&1 || PY=python
JSCPD_ON_PATH=0
command -v jscpd >/dev/null 2>&1 && JSCPD_ON_PATH=1

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

STUBS="$(mktemp -d)"
EMPTY_PATH="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "$STUBS" "$EMPTY_PATH" "$WORK"' EXIT
cat >"$STUBS/jscpd" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf 'jscpd 5.1.2\n'
  exit 0
fi
[[ -z "${CM_TEST_ARGV_LOG:-}" ]] || printf '%s\n' "$*" >>"$CM_TEST_ARGV_LOG"
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--output" ]]; then
    out="$2"
    shift 2
    continue
  fi
  shift
done
mkdir -p "$out"
cp "$CM_TEST_CAPTURE" "$out/jscpd-report.json"
exit 1
STUB
chmod +x "$STUBS/jscpd"
export CM_TEST_CAPTURE="$CAPTURE"
# EMPTY_PATH is the caller's PATH with every duplication collector removed: a
# directory of symlinks to each executable on PATH except those tools, so the
# coreutils, git, and the interpreter stay reachable while the collectors do
# not.
COLLECTOR_NAMES=" jscpd pmd dupl "
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

# 1. The declared cluster is excluded, not counted as debt.
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --json --all "$CLUSTER" --registry "$CLUSTER_REGISTRY")"
assert_eq "the registry run exits 0" 0 "$?"
if printf '%s' "$out" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); assert d["summary"]["duplicated_lines"] == 0 and len(d["excluded"]) >= 1' 2>/dev/null; then
  pass "a registry-sanctioned cluster reports zero duplicated lines"
else
  fail "a registry-sanctioned cluster reports zero duplicated lines" "duplicated_lines 0 with an excluded entry" "$(printf '%s' "$out" | head -c 400)"
fi
excluded_path="$(printf '%s' "$out" | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["excluded"][0]["path"])' 2>/dev/null)"
assert_eq "the excluded entry names the registry line" "shared/shared-utils.sh" "$excluded_path"
excluded_registry="$(printf '%s' "$out" | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["excluded"][0]["registry"])' 2>/dev/null)"
assert_contains "the excluded entry names the registry file" "$excluded_registry" "cluster.txt"

# 2. Without the registry the same clones are duplication debt.
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --json --all "$CLUSTER")"
assert_eq "the run without a registry exits 0" 0 "$?"
if printf '%s' "$out" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); assert d["summary"]["duplicated_lines"] > 0 and d["summary"]["clone_groups"] == 1 and d["excluded"] == []' 2>/dev/null; then
  pass "without a registry the same cluster reports duplicated lines"
else
  fail "without a registry the same cluster reports duplicated lines" "duplicated_lines > 0, no exclusions" "$(printf '%s' "$out" | head -c 400)"
fi
if printf '%s' "$out" | "$PY" -c 'import json,sys; row = json.load(sys.stdin)["measures"][0]; assert row["file"] is None and row["function"] is None and len(row["instances"]) == 2 and row["values"]["tokens"] == 110' 2>/dev/null; then
  pass "a clone group replaces file and function with instances"
else
  fail "a clone group replaces file and function with instances" "instances[] with two copies" "$(printf '%s' "$out" | head -c 400)"
fi

# 3. The markdown rendering states both the debt and the exclusion.
out="$(PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --all "$CLUSTER" --registry "$CLUSTER_REGISTRY")"
assert_eq "the markdown run exits 0" 0 "$?"
assert_contains "markdown carries the run table" "$out" "## Coverage of this run"
assert_contains "markdown states the duplicated-line count" "$out" "Duplicated lines"
assert_contains "markdown states the exclusion" "$out" "Excluded by a sanctioned-replication registry"

# 4. Every collector absent: a report is still produced and says so.
out="$(PATH="$EMPTY_PATH" bash "$SCRIPT" --json --all "$CLUSTER")"
assert_eq "an all-collectors-absent run exits 0" 0 "$?"
if printf '%s' "$out" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); assert d["status"] == "empty" and d["unavailable"] == ["bash/duplication"]' 2>/dev/null; then
  pass "an all-collectors-absent run is status empty with the lane unavailable"
else
  fail "an all-collectors-absent run is status empty with the lane unavailable" "status empty" "$(printf '%s' "$out" | head -c 400)"
fi
assert_contains "the unavailable row carries the install hint" "$out" "npm install -g jscpd"

# 5. An explicitly named registry that does not exist is a usage error.
PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --json --all "$CLUSTER" --registry /nonexistent-registry.txt >/dev/null 2>&1
assert_eq "a missing --registry exits 2" 2 "$?"

# 6. The configured tunables reach the collector's command line.
"$PY" "$PLUGIN_ROOT/scripts/resolve-config.py" --ladder "$PLUGIN_ROOT/scripts/collector-ladder.tsv" --home "$WORK" >"$WORK/base.json" 2>/dev/null
"$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); d["duplication"]["min_tokens"] = 77; d["duplication"]["min_lines"] = 9; d["duplication"]["ignore"] = ["**/vendor/**"]; print(json.dumps(d))' "$WORK/base.json" >"$WORK/tuned.json"
CM_TEST_ARGV_LOG="$WORK/argv.log" PATH="$STUBS:$EMPTY_PATH" bash "$SCRIPT" --json --all "$CLUSTER" --config "$WORK/tuned.json" >/dev/null 2>&1
assert_eq "the tuned run exits 0" 0 "$?"
argv="$(cat "$WORK/argv.log" 2>/dev/null)"
assert_contains "min_tokens reaches the collector" "$argv" "--min-tokens 77"
assert_contains "min_lines reaches the collector" "$argv" "--min-lines 9"
assert_contains "the ignore globs reach the collector" "$argv" "--ignore **/vendor/**"

# 7. --help prints the usage without running anything.
bash "$SCRIPT" --help 2>&1 | grep -q 'audit-duplication.sh \[--json\]'
assert_eq "--help prints usage" 0 "$?"

# 8. The Brief's case: this repository's own vendored hook-utils cluster.
# The jscpd on PATH has to be a working detector, not another suite's stub or
# a replaying fake: the probe copies one fixture into two directories under a
# name nothing else uses and requires the report to name it back.
detects_clones() {
  local probe="$WORK/probe"
  mkdir -p "$probe/one" "$probe/two" "$probe/out" || return 1
  cp "$CLUSTER/alpha/shared/shared-utils.sh" "$probe/one/probe-utils.sh" || return 1
  cp "$CLUSTER/alpha/shared/shared-utils.sh" "$probe/two/probe-utils.sh" || return 1
  jscpd --reporters json --output "$probe/out" --absolute --silent \
    "$probe/one/probe-utils.sh" "$probe/two/probe-utils.sh" >/dev/null 2>&1
  grep -q 'probe-utils.sh' "$probe/out/jscpd-report.json" 2>/dev/null
}
if [[ $JSCPD_ON_PATH -eq 1 ]] && ! detects_clones; then
  printf 'SKIP jscpd (on PATH but not a working detector): real hook-utils cluster case\n'
  JSCPD_ON_PATH=0
fi
if [[ $JSCPD_ON_PATH -eq 1 ]]; then
  mapfile -t hook_copies < <(printf '%s\n' plugins/*/hooks/hook-utils.sh)
  out="$(bash "$SCRIPT" --json --registry "$REAL_REGISTRY" "${hook_copies[@]}")"
  assert_eq "the real hook-utils cluster run exits 0" 0 "$?"
  if printf '%s' "$out" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); assert d["summary"]["duplicated_lines"] == 0, d["summary"]; assert any(e["path"] == "hooks/hook-utils.sh" for e in d["excluded"]), d["excluded"]' 2>/dev/null; then
    pass "the real hook-utils cluster reports zero debt through the registry"
  else
    fail "the real hook-utils cluster reports zero debt through the registry" "duplicated_lines 0 with an excluded hooks/hook-utils.sh entry" "$(printf '%s' "$out" | head -c 600)"
  fi
else
  printf 'SKIP jscpd (not on PATH): real hook-utils cluster case\n'
fi

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
