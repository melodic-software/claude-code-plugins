#!/usr/bin/env bash
# no-writes.test.sh — criterion 9, asserted mechanically rather than by reading
# the code.
#
# Both skills claim to write nothing, in any scope, under any flag. That claim is
# the reason they are safe to point at a consumer's real configuration, so it is
# checked by RUNNING every action of both and diffing the filesystem either side
# — a fixture tree AND a fixture HOME, since the settings files these skills are
# about live in the second one.
#
# The oracle path is exercised deliberately. Running only the defaults would
# prove nothing about the one code path that spawns a process capable of writing
# outside the tree; a stub `claude` on PATH stands in for the real CLI so the
# spawn happens without a session, a token, or a network call.
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

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# --- The tree every action runs against --------------------------------------
FX="$TEST_TMPDIR/fx"
mkdir -p "$FX/proj/.claude" "$FX/home/.claude" "$FX/policy/managed-settings.d" "$FX/startdir/.claude"
jq -n '{permissions:{allow:["Bash(git status)","Bash(python*)"],deny:["WebFetch"]}}' >"$FX/proj/.claude/settings.json"
jq -n '{permissions:{allow:["Bash(npm test)"]}}' >"$FX/proj/.claude/settings.local.json"
jq -n '{autoMode:{classifyAllShell:true},permissions:{allow:["Bash(*)"],disableAutoMode:true}}' >"$FX/home/.claude/settings.json"
jq -n '{permissions:{deny:["Read(./.env)"]}}' >"$FX/policy/managed-settings.json"
jq -n '{permissions:{ask:["Bash(rm *)"]}}' >"$FX/policy/managed-settings.d/10-first.json"
jq -n '{permissions:{allow:["Bash(ls)"]}}' >"$FX/startdir/.claude/settings.local.json"

# A stub `claude` so the oracle's spawn path executes without a real session.
# It writes into the debug file it is handed, which is the scratch path the
# oracle chose — proving the capture lands there and nowhere else.
STUB="$TEST_TMPDIR/stub-bin"
mkdir -p "$STUB"
real_bash="$(command -v bash)"
printf '#!%s\n' "$real_bash" >"$STUB/claude"
# A quoted heredoc: the body is the STUB's source, so its parameters must reach
# the file verbatim rather than expanding against this harness's values.
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
# Only `claude` is stubbed. An earlier revision wrapped every tool the scripts
# use, which deadlocked: a wrapper for `env` re-entered itself through the very
# PATH it was setting up, and the harness hung before its first assertion. The
# real tools are reached through the inherited PATH appended below.

snapshot() {
  # Path, size and full content of every file under the given roots. Mtime is
  # deliberately excluded: a read can update atime on some filesystems, and this
  # is a test about writes.
  #
  # `find -exec` rather than a `while read` loop: on Git Bash the loop's subshell
  # deadlocked against the pipeline feeding it, and the harness hung before its
  # first assertion. `-exec … +` needs no subshell at all.
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

# --- Every action of both skills, oracle ON -----------------------------------
before="$(snapshot "$FX")"

CASE_NUM_ACTIONS=0
run_action() {
  # run_action <label> <command...> — output discarded; only the effect matters
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

# Stages are chained through files rather than a pipeline in a `bash -c` string:
# the shell quoting a nested pipeline needs is its own source of defects, and
# what is under test is whether these programs write, not how they are composed.
STAGE="$TEST_TMPDIR/stage"
mkdir -p "$STAGE"

# The produced file is returned in a NAMED VARIABLE, never on stdout. An earlier
# revision printed the path and captured it with $(...), which swallowed every
# PASS line printed alongside it -- the run reported "All 10 checks passed" while
# four stages had silently never executed. A harness that can miscount its own
# cases is worse than no harness.
PIPE_OUT=""
pipe_into() {
  # pipe_into <label> <input-file> <script> [args...] — result path in $PIPE_OUT
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
  # A stage that produced nothing means the pipeline broke, and every downstream
  # assertion would then pass vacuously against an empty input.
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

# The oracle explicitly ON. This is the only path that spawns a process, so a
# run without it proves nothing about criterion 9 — the flag exists precisely
# because this code path is different in kind from the others.
pipe_into "automode-entry-diff.sh --oracle (SPAWNS)" "$merged" "$ENTRY_DIFF" --oracle

# Every action above must actually have been attempted. Without this, a harness
# that skipped stages would still print a confident "all checks passed" -- which
# is exactly what an earlier revision did.
#
# Ten: the reader twice (default and --scopes), merge, plane lint, conformance,
# entry diff, block lint twice (default and --critique), the drafter, and the
# entry diff again with the oracle ON.
assert_eq "every one of the ten actions ran" 10 "$CASE_NUM_ACTIONS"

# --- The oracle's capture lands in scratch, not in the config directory -------
# Its cost notice promises the debug capture goes to a scratch path and never to
# ~/.claude/debug/. The stub writes wherever it is pointed, so if the oracle
# pointed it at the config directory this would catch it.
assert_eq "the oracle wrote no debug file under the fixture HOME" 0 \
  "$(find "$FX/home" -name '*.log' -o -name 'debug*' 2>/dev/null | wc -l | tr -d ' ')"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
