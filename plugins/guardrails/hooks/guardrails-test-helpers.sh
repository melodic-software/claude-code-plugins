# shellcheck shell=bash
# Self-contained test helpers for the guardrails plugin hook contract tests.
# Sourced (never *.test.sh-named, so a test runner's glob ignores it) by each
# hook's *.test.sh after that file sets up its own TEST_TMPDIR + trap. No
# dependency on any host-repo assertion library — the plugin is standalone.
#
# Duplicated across plugins by design, not drift — see
# docs/conventions/shell-test-helpers/README.md at the repo root.

# Strip the inherited git environment so a fixture `git init` in these tests
# resolves to the mktemp fixture, never the real repo (#2840). `-C` only changes
# directory, while an exported ABSOLUTE GIT_DIR overrides repository DISCOVERY,
# and `git config`'s default --local scope follows whatever gitdir that resolves
# to. Any process may export it — the real incident came from an ad-hoc tool
# invocation, not from a git hook — so the rule is to clear unconditionally.
# GIT_CONFIG is a DISTINCT leak path: it replaces the file the `git config`
# subcommand reads and writes, independently of -C and of GIT_DIR.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

: "${PASS:=0}"
: "${FAIL:=0}"

ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
bad() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

# assert_eq <label> <expected> <actual>. Prefer this over assert_contains for a
# value with a known exact form: containment passes on any string that merely
# embeds the expected one, which is how a leaked `\\srv\share\secrets.env` once
# satisfied a "data.file is the basename" check.
assert_eq() {
  if [[ "$3" == "$2" ]]; then ok "$1 ($3)"; else bad "$1: expected '$2', got '$3'"; fi
}
# assert_exit <label> <expected> <actual>
assert_exit() {
  if [[ "$3" == "$2" ]]; then ok "$1 (exit $3)"; else bad "$1: expected exit $2, got $3"; fi
}
# assert_contains <label> <haystack> <needle>
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1: '$3' not in output: $2"; fi
}
# assert_absent <label> <haystack> <needle>
assert_absent() {
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1: unexpected '$3' in output"; fi
}
# assert_silent <label> <output>
assert_silent() {
  if [[ -z "$2" ]]; then ok "$1"; else bad "$1: expected empty output, got: $2"; fi
}
# assert_file_absent <label> <path>
assert_file_absent() {
  if [[ ! -e "$2" ]]; then ok "$1"; else bad "$1: file exists: $2"; fi
}

# assert_file_dir_seam <hook-path>. The hook anchors its repo-root lookup on the
# FILE's directory through a parameter expansion rather than a `dirname` fork,
# and that expansion must answer as `dirname` did for every shape. For a
# root-level `/bar.md` the shortest `/*` suffix is the whole string, so the bare
# expansion is EMPTY and hook::repo_root's `${1:-.}` would anchor on the process
# CWD, not `/`. That shape cannot reach a hook end to end (hook::read_file_path
# needs the file to exist and `/` is not writable), so the seam is lifted from
# the hook source and evaluated against each shape on its own.
# shellcheck disable=SC2016  # the sed script and the needle are literal hook source text
assert_file_dir_seam() {
  local seam fp FILE FILE_DIR
  seam=$(sed -n '/^FILE_DIR="\${FILE%\/\*}"$/,/^REPO_ROOT=/{/^REPO_ROOT=/d;p}' "$1")
  assert_contains "file-dir seam: lifted from the hook" "$seam" 'FILE_DIR="${FILE%/*}"'
  for fp in /bar.md bar.md /a/b/bar.md; do
    # shellcheck disable=SC2034  # read by the eval below
    FILE="$fp"
    FILE_DIR=""
    eval "$seam"
    assert_eq "file-dir seam: $fp anchors where dirname does" "$(dirname "$fp")" "$FILE_DIR"
  done
}

# PreToolUse JSON builders. jq -n --arg escapes quotes/backslashes/newlines.
# MSYS_NO_PATHCONV=1 stops Git Bash translating POSIX file paths for jq's exe.
write_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg fp "$1" --arg c "$2" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}'
}
edit_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg fp "$1" --arg s "$2" \
    '{tool_name:"Edit",tool_input:{file_path:$fp,new_string:$s}}'
}
notebook_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg fp "$1" --arg s "$2" \
    '{tool_name:"NotebookEdit",tool_input:{file_path:$fp,new_source:$s}}'
}
other_tool_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg t "$1" --arg fp "$2" \
    '{tool_name:$t,tool_input:{file_path:$fp}}'
}
command_json() {
  jq -n --arg cmd "$1" '{tool_name:"Bash",tool_input:{command:$cmd}}'
}
# PreToolUse payload for the opt-in PowerShell tool: same tool_input.command
# field as Bash, distinguished by tool_name so dispatch keys on the tool.
pwsh_command_json() {
  jq -n --arg cmd "$1" '{tool_name:"PowerShell",tool_input:{command:$cmd}}'
}

# --- One command-to-verdict driver -------------------------------------------
# Every guard suite needs the same unit of work: one payload on stdin, one hook
# process, one verdict (the exit code, plus whatever the guard said on stdout
# and stderr). A guard reaches that verdict two ways in production — alone, and
# under hooks/run-guards.sh — and the dispatcher's own seams (stdin read once
# and re-served with the guard's own rc, the primed jq cache, the merge of
# several stdout documents into one) only carry a REAL verdict when a suite
# drives the second one. `--via` selects the path, so one case can assert both
# and a disagreement between them is a failure rather than a blind spot.
#
# Caller contract, set by each suite before its first call:
#   GUARD_UNDER_TEST  path to the guard under test
#   TEST_TMPDIR       scratch directory (already required by make_sink)
#
# guard_invoke [option ...] [-- <env word> ...]
#   --tool <name>       tool_name of the built payload (default Bash)
#   --command <string>  tool_input.command of the built payload
#   --cwd <dir>         payload `.cwd`; omitted from the document when not given
#   --payload <json>    exact stdin document; wins over the three above
#   --hook <path>       guard for this call only
#   --also <path>       an ADDITIONAL guard for the dispatcher, repeatable
#   --lib <path>        a `--lib` argument for the dispatcher, repeatable
#   --via direct|dispatched
#   --chdir <dir>       working directory of the hook process
#   --merge-stderr      fold stderr into GUARD_OUT (GUARD_ERR stays empty)
#   -- <word> ...       every remaining word is passed to `env` ahead of the
#                       command, in order: NAME=VALUE, or a flag such as -u NAME
#
# Sets GUARD_OUT, GUARD_ERR, GUARD_RC and returns GUARD_RC.
GUARDRAILS_HOOK_DIR="${BASH_SOURCE[0]%/*}"
: "${GUARD_DISPATCH:=$GUARDRAILS_HOOK_DIR/run-guards.sh}"
: "${GUARD_VIA:=direct}"
GUARD_OUT=""
GUARD_ERR=""
GUARD_RC=0

# shellcheck disable=SC2034  # GUARD_OUT/GUARD_ERR are read by the sourcing suite
# Every local here carries a `_gi_` prefix. `shellcheck -x` follows this file
# into each suite that sources it and carries a name's declared TYPE with it, so
# an unprefixed `local -a cmd` here reports the suites' own string `cmd` as an
# array misuse.
guard_invoke() {
  local _gi_via="$GUARD_VIA" _gi_hook="${GUARD_UNDER_TEST:-}" _gi_tool=Bash
  local _gi_command="" _gi_cwd="" _gi_payload="" _gi_have_payload=0
  local _gi_chdir="" _gi_merge=0
  local -a _gi_envs=() _gi_also=() _gi_libs=()
  while (($#)); do
    case "$1" in
    --tool)
      _gi_tool="$2"
      shift 2
      ;;
    --command)
      _gi_command="$2"
      shift 2
      ;;
    --cwd)
      _gi_cwd="$2"
      shift 2
      ;;
    --payload)
      _gi_payload="$2"
      _gi_have_payload=1
      shift 2
      ;;
    --hook)
      _gi_hook="$2"
      shift 2
      ;;
    --also)
      _gi_also+=("$2")
      shift 2
      ;;
    --lib)
      _gi_libs+=(--lib "$2")
      shift 2
      ;;
    --via)
      _gi_via="$2"
      shift 2
      ;;
    --chdir)
      _gi_chdir="$2"
      shift 2
      ;;
    --merge-stderr)
      _gi_merge=1
      shift
      ;;
    --)
      shift
      _gi_envs=("$@")
      break
      ;;
    *)
      bad "guard_invoke: unknown option '$1'"
      GUARD_RC=64
      return 64
      ;;
    esac
  done
  if ((_gi_have_payload == 0)); then
    _gi_payload=$(MSYS_NO_PATHCONV=1 jq -n \
      --arg t "$_gi_tool" --arg c "$_gi_command" --arg d "$_gi_cwd" \
      '{tool_name:$t,tool_input:{command:$c}} + (if $d == "" then {} else {cwd:$d} end)')
  fi
  local -a _gi_argv=()
  if ((${#_gi_envs[@]})); then _gi_argv=(env "${_gi_envs[@]}"); fi
  case "$_gi_via" in
  direct) _gi_argv+=(bash "$_gi_hook") ;;
  dispatched)
    _gi_argv+=(bash "$GUARD_DISPATCH" ${_gi_libs[@]+"${_gi_libs[@]}"} "$_gi_hook"
      ${_gi_also[@]+"${_gi_also[@]}"})
    ;;
  *)
    bad "guard_invoke: unknown --via '$_gi_via'"
    GUARD_RC=64
    return 64
    ;;
  esac
  # One fixed stderr file rather than a per-call mktemp: these suites are
  # sequential and a mktemp would be one more process on every case.
  local _gi_errf="${TEST_TMPDIR:?guard_invoke needs TEST_TMPDIR}/guard-invoke.err"
  GUARD_RC=0
  GUARD_ERR=""
  if ((_gi_merge)); then
    if [[ -n "$_gi_chdir" ]]; then
      GUARD_OUT=$(cd "$_gi_chdir" && "${_gi_argv[@]}" <<<"$_gi_payload" 2>&1) || GUARD_RC=$?
    else
      GUARD_OUT=$("${_gi_argv[@]}" <<<"$_gi_payload" 2>&1) || GUARD_RC=$?
    fi
  else
    if [[ -n "$_gi_chdir" ]]; then
      GUARD_OUT=$(cd "$_gi_chdir" && "${_gi_argv[@]}" <<<"$_gi_payload" 2>"$_gi_errf") || GUARD_RC=$?
    else
      GUARD_OUT=$("${_gi_argv[@]}" <<<"$_gi_payload" 2>"$_gi_errf") || GUARD_RC=$?
    fi
    GUARD_ERR=$(<"$_gi_errf")
  fi
  return "$GUARD_RC"
}

# expect <label> <expected-exit> [guard_invoke option ...]
expect() {
  local label="$1" expected="$2"
  shift 2
  guard_invoke "$@"
  assert_exit "$label" "$expected" "$GUARD_RC"
}

# expect_both <label> <expected-exit> [guard_invoke option ...]
# The same case run alone and under the dispatcher, asserting the SAME verdict
# both ways. Two arms cannot agree by construction and stay single-mode: a
# guard's empty-stdin (rc 1) and cut-short (rc 3) skips, which the dispatcher
# answers once for the whole event before any guard is sourced.
expect_both() {
  local label="$1" expected="$2"
  shift 2
  expect "$label (direct)" "$expected" --via direct "$@"
  expect "$label (dispatched)" "$expected" --via dispatched "$@"
}

# --- Write/Edit driver for the advisory PostToolUse guards --------------------
# Those suites all drive one shape: a Write or Edit payload naming the fixture's
# TARGET file, with CLAUDE_PROJECT_DIR pinned to the fixture REPO.
#
# run <content>: hook stdout+stderr lands in the global OUT; the hook's exit
# code is RETURNED, so `run ...` then `assert_exit ... "$?"` is the call shape.
#
# Never `OUT=$(run ...)`: a command substitution runs the helper in a subshell,
# so an `RC=$?` assigned inside it never reaches the parent and every
# `assert_exit` after the call silently compares a stale outer value; the suite
# would stay green through a hook that regressed to a nonzero exit.
# HOOK_OVERRIDE lets a case point the helpers at a stub hook; unset elsewhere.
#
# run_payload <json> is the shared driver call every shape reduces to: one
# payload, one hook process, stdout and stderr together in OUT, the hook's own
# exit code returned.
#
# Caller contract, set by each suite before its first call:
#   HOOK    guard under test
#   REPO    fixture working tree, handed to the hook as CLAUDE_PROJECT_DIR
#   TARGET  file path the Write/Edit payload names
run_payload() {
  # shellcheck disable=SC2154  # HOOK/REPO are a caller contract (set by each test file)
  guard_invoke --hook "${HOOK_OVERRIDE:-$HOOK}" --merge-stderr --payload "$1" \
    -- "CLAUDE_PROJECT_DIR=$REPO"
  # shellcheck disable=SC2034  # OUT is read by the sourcing suite
  OUT="$GUARD_OUT"
  return "$GUARD_RC"
}
# shellcheck disable=SC2154  # TARGET is a caller contract (set by each test file)
run() { run_payload "$(write_json "$TARGET" "$1")"; }
# run_edit <new_string> -> same, as an Edit payload.
# shellcheck disable=SC2154  # TARGET is a caller contract (set by each test file)
run_edit() { run_payload "$(edit_json "$TARGET" "$1")"; }

# assert_run_helpers_propagate_exit. Guards the assertion machinery itself:
# point `run` and `run_edit` at a stub that exits nonzero and the code they
# return must be that code. An `OUT=$(run ...)` shape with an inner `RC=$?`
# reads 0 instead, which makes every run-based `assert_exit` in a suite vacuous.
assert_run_helpers_propagate_exit() {
  local stub="${TEST_TMPDIR:?assert_run_helpers_propagate_exit needs TEST_TMPDIR}/rc-stub-hook.sh"
  # shellcheck disable=SC2034  # read by run_payload through dynamic scope
  local HOOK_OVERRIDE="$stub"
  printf '#!/usr/bin/env bash\nexit 3\n' >"$stub"
  run 'anything'
  assert_exit "run propagates a nonzero hook exit" 3 "$?"
  run_edit 'anything'
  assert_exit "run_edit propagates a nonzero hook exit" 3 "$?"
}

# parity <label> <content> <expected-exit> <needle, or "" for silence>
# One Write payload driven both ways, alone and under run-guards.sh, asserting
# the same exit code and the same finding (or the same silence) on both. An
# advisory guard exits 0 whether or not it found anything, so the exit code
# alone is not its verdict: the additionalContext document is.
parity() {
  local label="$1" content="$2" expected="$3" needle="$4" payload via
  payload="$(write_json "$TARGET" "$content")"
  for via in direct dispatched; do
    guard_invoke --via "$via" --merge-stderr --payload "$payload" \
      -- "CLAUDE_PROJECT_DIR=$REPO"
    assert_exit "$label ($via)" "$expected" "$GUARD_RC"
    if [[ -n "$needle" ]]; then
      assert_contains "$label ($via): finding survives" "$GUARD_OUT" "$needle"
    else
      assert_silent "$label ($via): stays quiet" "$GUARD_OUT"
    fi
  done
}

# make_sink <body> -> path to an executable single-command stub sink running
# <body> (which reads the telemetry envelope on stdin). HOOK_TELEMETRY_SINK
# must be a single executable path, so tests point it at a stub.
make_sink() {
  local s
  # shellcheck disable=SC2154  # TEST_TMPDIR is a caller contract (set by each test file)
  s="$(mktemp "$TEST_TMPDIR/sink.XXXXXX")"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$1"
  } >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}

# wait_for_sink <file> [tries] -> block until <file> is non-empty (the
# fire-and-forget sink flushed) or the bound elapses, polling in 20ms steps.
wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

report() {
  echo
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
}
