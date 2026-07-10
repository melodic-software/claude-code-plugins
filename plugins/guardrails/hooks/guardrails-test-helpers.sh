# shellcheck shell=bash
# Self-contained test helpers for the guardrails plugin hook contract tests.
# Sourced (never *.test.sh-named, so a test runner's glob ignores it) by each
# hook's *.test.sh after that file sets up its own TEST_TMPDIR + trap. No
# dependency on any host-repo assertion library — the plugin is standalone.

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

# make_sink <body> -> path to an executable single-command stub sink running
# <body> (which reads the telemetry envelope on stdin). HOOK_TELEMETRY_SINK
# must be a single executable path, so tests point it at a stub.
make_sink() {
  local s
  # shellcheck disable=SC2154  # TEST_TMPDIR is a caller contract (set by each test file)
  s="$(mktemp -p "$TEST_TMPDIR" sink.XXXXXX)"
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
