#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$SCRIPT_DIR/permission-state.sh"
MERGE="$SCRIPT_DIR/permission-merge.sh"
ENTRY_DIFF="$SCRIPT_DIR/automode-entry-diff.sh"
PLANE_LINT="$SCRIPT_DIR/permission-plane-lint.sh"
BLOCK_LINT="$SCRIPT_DIR/automode-block-lint.sh"
CONFORMANCE="$SCRIPT_DIR/managed-conformance.sh"
DRAFTER="$SCRIPT_DIR/../../draft-auto-mode-rules/scripts/draft-automode-block.sh"
FIXTURES="$SCRIPT_DIR/../evals/fixtures"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

FX="$TEST_TMPDIR/fx"
mkdir -p "$FX/proj/.claude" "$FX/home/.claude" "$FX/policy/managed-settings.d" "$FX/startdir/.claude"
jq -n '{permissions:{allow:["Bash(git status)","Bash(python*)"],deny:["WebFetch"]}}' >"$FX/proj/.claude/settings.json"
jq -n '{permissions:{allow:["Bash(npm test)"]}}' >"$FX/proj/.claude/settings.local.json"
jq -n '{autoMode:{classifyAllShell:true},permissions:{allow:["Bash(*)"],disableAutoMode:true}}' >"$FX/home/.claude/settings.json"
jq -n '{permissions:{deny:["Read(./.env)"]}}' >"$FX/policy/managed-settings.json"
jq -n '{permissions:{ask:["Bash(rm *)"]}}' >"$FX/policy/managed-settings.d/10-first.json"
jq -n '{permissions:{allow:["Bash(ls)"]}}' >"$FX/startdir/.claude/settings.local.json"

STUB="$TEST_TMPDIR/stub-bin"
mkdir -p "$STUB"
printf '#!%s\n' "$real_bash" >"$STUB/claude"
cat >>"$STUB/claude" <<'STUB_CLAUDE'
debug=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --debug-file)
    debug="$2"
    shift 2
    ;;
  *) shift ;;
  esac
done
if [[ -n "$debug" ]]; then
  printf '%s\n' "[DEBUG] Applying permission update: Adding 1 allow rule(s) to destination 'userSettings'" >"$debug"
fi
printf 'OK\n'
STUB_CLAUDE
chmod +x "$STUB/claude"

snapshot() {
  local root
  for root in "$@"; do
    find "$root" -type f -exec wc -c {} + 2>/dev/null | LC_ALL=C sort
    find "$root" -type f -exec cat {} + 2>/dev/null
  done
}

fixture_env() {
  env -u CLAUDE_CONFIG_DIR \
    HOME="$FX/home" \
    PERMISSION_STATE_FIXTURE_DIR="$FX/proj" \
    PERMISSION_STATE_STARTDIR="$FX/startdir" \
    PERMISSION_STATE_MANAGED_PATH="$FX/policy/managed-settings.json" \
    PERMISSION_STATE_REGISTRY_KEYS="" \
    PERMISSION_STATE_PLIST_DOMAIN="" \
    AUTOMODE_CONFIG_FIXTURE="$FIXTURES/automode-config-rawctl.json" \
    AUTOMODE_DEFAULTS_FIXTURE="$FIXTURES/automode-defaults.json" \
    AUTOMODE_CRITIQUE_FIXTURE="$TEST_TMPDIR/critique.txt" \
    PATH="$STUB:$PATH" \
    "$@"
}

printf 'Your rules look consistent.\n' >"$TEST_TMPDIR/critique.txt"

ANSWERS=$(
  cat <<'EOF'
section allow
label Test Execution
covered running the test suite
not installing dependencies
why the runner is named in the command
EOF
)

before="$(snapshot "$FX")"

CASE_NUM_ACTIONS=0
run_action() {
  local label="$1"
  shift
  CASE_NUM_ACTIONS=$((CASE_NUM_ACTIONS + 1))
  "$@" >/dev/null 2>&1
  local rc=$?
  local after
  after="$(snapshot "$FX")"
  if [[ "$before" == "$after" ]]; then
    pass "no writes: $label"
  else
    fail "no writes: $label" "the fixture tree or fixture HOME changed (exit was $rc)"
    before="$after"
  fi
}

STAGE="$TEST_TMPDIR/stage"
mkdir -p "$STAGE"

PIPE_OUT=""
pipe_into() {
  local label="$1" input="$2"
  shift 2
  CASE_NUM_ACTIONS=$((CASE_NUM_ACTIONS + 1))
  PIPE_OUT="$STAGE/out.$((++stage_seq))"
  fixture_env "$real_bash" "$@" <"$input" >"$PIPE_OUT" 2>/dev/null
  local rc=$?
  local after
  after="$(snapshot "$FX")"
  if [[ "$before" == "$after" ]]; then
    pass "no writes: $label"
  else
    fail "no writes: $label" "the fixture tree or fixture HOME changed (exit was $rc)"
    before="$after"
  fi
  [[ -s "$PIPE_OUT" ]] || fail "stage produced output: $label" "empty result file (exit was $rc)"
}
stage_seq=0

run_action "permission-state.sh" fixture_env "$real_bash" "$STATE"
run_action "permission-state.sh --scopes" fixture_env "$real_bash" "$STATE" --scopes

fixture_env "$real_bash" "$STATE" >"$STAGE/state.txt" 2>/dev/null
pipe_into "permission-merge.sh" "$STAGE/state.txt" "$MERGE"
merged="$PIPE_OUT"
pipe_into "permission-plane-lint.sh" "$STAGE/state.txt" "$PLANE_LINT"
pipe_into "managed-conformance.sh" "$STAGE/state.txt" "$CONFORMANCE"
pipe_into "automode-entry-diff.sh" "$merged" "$ENTRY_DIFF"

run_action "automode-block-lint.sh" fixture_env "$real_bash" "$BLOCK_LINT"
run_action "automode-block-lint.sh --critique" fixture_env "$real_bash" "$BLOCK_LINT" --critique

printf '%s\n' "$ANSWERS" >"$STAGE/answers.txt"
pipe_into "draft-automode-block.sh" "$STAGE/answers.txt" "$DRAFTER"

pipe_into "automode-entry-diff.sh --oracle (SPAWNS)" "$merged" "$ENTRY_DIFF" --oracle

assert_eq "every one of the ten actions ran" 10 "$CASE_NUM_ACTIONS"

assert_eq "the oracle wrote no debug file under the fixture HOME" 0 \
  "$(find "$FX/home" -name '*.log' -o -name 'debug*' 2>/dev/null | wc -l | tr -d ' ')"

report_and_exit
