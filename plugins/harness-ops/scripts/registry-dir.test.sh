#!/usr/bin/env bash
# Tests for registry-dir.mjs: the known-issues registry directory resolved through the config
# cascade (default, userConfig, team <home>/harness-ops.yaml, personal <home>/harness-ops.local.yaml),
# the containment rule on every layer, and the layer each value came from.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$SCRIPT_DIR/registry-dir.mjs"
HOOK_DIR="$SCRIPT_DIR/../hooks"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'ok %d - %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n' "$CASE_NUM" "$1"
  if [[ -n "${2:-}" ]]; then printf '  %s\n' "$2"; fi
}
# check <name> <command...>: passes when the command exits 0.
check() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name" "${DETAIL:-}"; fi
  DETAIL=""
}

for tool in git node jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "1..0 # SKIP $tool not available"
    exit 0
  fi
done

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
N=0

# new_repo: sets R to a new empty git repository with a docs/conventions directory.
new_repo() {
  N=$((N + 1))
  R="$TEST_TMPDIR/repo$N"
  mkdir -p "$R/docs/conventions"
  git -C "$R" init -q
}
team() { printf 'registry_dir: %s\n' "$1" >"$R/docs/conventions/harness-ops.yaml"; }
personal() { printf 'registry_dir: %s\n' "$1" >"$R/docs/conventions/harness-ops.local.yaml"; }
# run <project> [user value]: the reader with --project and, when given, --user-registry-dir.
run() {
  local args=(--project "$1")
  if [[ $# -ge 2 ]]; then args+=(--user-registry-dir "$2"); fi
  node "$READER" "${args[@]}" >"$TEST_TMPDIR/out" 2>"$TEST_TMPDIR/err"
  RC=$?
  OUT="$(cat "$TEST_TMPDIR/out")"
  ERR="$(cat "$TEST_TMPDIR/err")"
  DETAIL="exit $RC; out: $OUT; stderr: $ERR"
}
got() { jq -r "$1" <<<"$OUT" 2>/dev/null; }

# 1. Nothing set: the plugin data directory, reported as layer default.
new_repo
run "$R"
check "neither set: exits 0" test "$RC" -eq 0
check "neither set: layer default, no directory" test "$(got '"\(.layer) \(.registry_dir) \(.data_dir) \(.path)"')" == "default null null null"
check "neither set: no errors" test "$(got '.errors | length')" -eq 0

# 2. userConfig alone.
run "$R" 'tools/registry'
check "userConfig only: layer userConfig" test "$(got '"\(.layer) \(.registry_dir)"')" == "userConfig tools/registry"
check "userConfig only: directory joined to the project" test "$(got .data_dir)" == "$R/tools/registry"

# 3. An unrendered placeholder or an empty value is unset.
# shellcheck disable=SC2016 # the literal placeholder is the input under test
run "$R" '${user_config.registry_dir}'
check "unrendered placeholder: layer default" test "$(got .layer)" == "default"
run "$R" ''
check "empty userConfig: layer default" test "$(got .layer)" == "default"

# 4. The team file beats userConfig.
team 'docs/registry'
run "$R" 'tools/registry'
check "team over userConfig: layer team" test "$(got '"\(.layer) \(.registry_dir) \(.path)"')" == "team docs/registry docs/conventions/harness-ops.yaml"
check "team over userConfig: directory from the team value" test "$(got .data_dir)" == "$R/docs/registry"

# 5. The personal override beats the team file.
personal 'mine/registry'
run "$R" 'tools/registry'
check "personal over team: layer local" test "$(got '"\(.layer) \(.registry_dir) \(.path)"')" == "local mine/registry docs/conventions/harness-ops.local.yaml"

# 6. An invalid personal value leaves the team value standing and is named.
personal '../outside'
run "$R" 'tools/registry'
check "invalid personal: the team value stands" test "$(got '"\(.layer) \(.registry_dir)"')" == "team docs/registry"
check "invalid personal: the error names the file, key and value" grep -q 'local (.*harness-ops.local.yaml).*registry_dir.*\.\./outside' <<<"$(got '.errors[]')"

# 7. An invalid team value falls to the default, never to the valid userConfig value below it.
new_repo
team '/srv/registry'
run "$R" 'tools/registry'
check "invalid team: exits 0" test "$RC" -eq 0
check "invalid team: layer default, not userConfig" test "$(got '"\(.layer) \(.data_dir)"')" == "default null"
check "invalid team: the error names the file, key and value" grep -q 'team (.*harness-ops.yaml).*registry_dir.*/srv/registry' <<<"$(got '.errors[]')"

# 8. A team value of the wrong type is dropped the same way.
team '42'
run "$R" 'tools/registry'
check "non-string team: layer default" test "$(got .layer)" == "default"
check "non-string team: an error names the key" grep -q 'team (.*harness-ops.yaml).*registry_dir' <<<"$(got '.errors[]')"

# 9. An invalid userConfig value is named and resolves to the default.
new_repo
run "$R" '..\outside'
check "invalid userConfig: layer default" test "$(got .layer)" == "default"
check "invalid userConfig: the error names userConfig and the value" grep -q 'userConfig.*registry_dir' <<<"$(got '.errors[]')"

# 10. A symlink inside the project that leads outside it is not contained.
new_repo
mkdir -p "$TEST_TMPDIR/elsewhere"
ln -s "$TEST_TMPDIR/elsewhere" "$R/link"
team 'link/registry'
run "$R"
check "escaping symlink: layer default" test "$(got .layer)" == "default"
check "escaping symlink: the error names the value" grep -q 'registry_dir.*link/registry' <<<"$(got '.errors[]')"

# 11. Other keys in the team file do not disturb the result, and their errors are not reported.
new_repo
printf 'verification: light\nregistry_dir: reg\nunknown_key: 1\n' >"$R/docs/conventions/harness-ops.yaml"
run "$R"
check "other keys: layer team" test "$(got '"\(.layer) \(.registry_dir)"')" == "team reg"
check "other keys: no registry_dir errors" test "$(got '.errors | length')" -eq 0

# 12. The pointer line binds the convention home.
new_repo
mkdir -p "$R/conventions"
# shellcheck disable=SC2016 # the backticks are the pointer line's literal Markdown
printf '<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in `conventions`.\n<!-- END GENERATED: convention-home -->\n' >"$R/AGENTS.md"
printf 'registry_dir: bound/registry\n' >"$R/conventions/harness-ops.yaml"
team 'ignored/registry'
run "$R"
check "bound home: the team file under the bound home" test "$(got '"\(.layer) \(.registry_dir) \(.path) \(.home)"')" == "team bound/registry conventions/harness-ops.yaml conventions"

# 13. A declined home reads no repository file.
printf '<!-- BEGIN GENERATED: convention-home -->\ndeclined\n<!-- END GENERATED: convention-home -->\n' >"$R/AGENTS.md"
run "$R" 'tools/registry'
check "declined home: userConfig, the team file unread" test "$(got '"\(.layer) \(.home)"')" == "userConfig null"
check "declined home: says why" test -n "$(got '.home_skipped // empty')"

# 14. Outside a git repository the team and personal layers are not applicable.
N=$((N + 1))
R="$TEST_TMPDIR/loose$N"
mkdir -p "$R/docs/conventions"
team 'docs/registry'
run "$R"
check "not a repository: layer default" test "$(got '"\(.layer) \(.home)"')" == "default null"
check "not a repository: says why" test -n "$(got '.home_skipped // empty')"

# 15. A subdirectory of a repository anchors at the git toplevel.
new_repo
mkdir -p "$R/sub/dir"
team 'docs/registry'
run "$R/sub/dir"
check "subdirectory: anchored at the toplevel" test "$(got .data_dir)" == "$R/docs/registry"

# 16. The containment rule matches the hooks' rule (hooks/harness-ops-paths.sh) value for value.
# shellcheck source=../hooks/hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=../hooks/harness-ops-paths.sh
source "$HOOK_DIR/harness-ops-paths.sh"
new_repo
mkdir -p "$TEST_TMPDIR/far"
ln -s "$TEST_TMPDIR/far" "$R/out"
for value in 'a/b' 'a\b' './a' '/tmp/x' 'C:\x' 'C:x' '\\server\share' '../x' '..\x' 'a/../b' 'out/x' 'out'; do
  if harness_ops::resolve_project_relative_dir "$R" "$value" >/dev/null; then hooks=ok; else hooks=rejected; fi
  run "$R" "$value"
  if [[ "$(got .layer)" == "userConfig" ]]; then mine=ok; else mine=rejected; fi
  check "parity with the hooks' rule: $value ($hooks)" test "$mine" == "$hooks"
done

# 17. A bad argument is a usage error.
node "$READER" --no-such-flag >/dev/null 2>"$TEST_TMPDIR/err"
RC=$?
DETAIL="exit $RC; stderr: $(cat "$TEST_TMPDIR/err")"
check "unknown flag: exit 2" test "$RC" -eq 2

echo "1..$CASE_NUM"
if [[ "$FAILED" -gt 0 ]]; then
  echo "# $FAILED of $CASE_NUM failed"
  exit 1
fi
