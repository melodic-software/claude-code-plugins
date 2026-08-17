# shellcheck shell=bash
# Self-contained test helpers for the claude-ops plugin hook contract tests.
# Sourced (never *.test.sh-named, so the test runner's glob ignores it) by each
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

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [[ "$3" == "$2" ]]; then ok "$1 ($3)"; else bad "$1: expected '$2', got '$3'"; fi
}
# assert_exit <label> <expected> <actual>
assert_exit() {
  if [[ "$3" == "$2" ]]; then ok "$1 (exit $3)"; else bad "$1: expected exit $2, got $3"; fi
}
# assert_contains <label> <haystack> <needle>
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1: '$3' not in: $2"; fi
}
# assert_absent <label> <haystack> <needle>
assert_absent() {
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1: unexpected '$3' in: $2"; fi
}
# assert_silent <label> <output>
assert_silent() {
  if [[ -z "$2" ]]; then ok "$1"; else bad "$1: expected empty output, got: $2"; fi
}
# assert_file_absent <label> <path>
assert_file_absent() {
  if [[ ! -e "$2" ]]; then ok "$1"; else bad "$1: file exists: $2"; fi
}

# make_sink <envelope-capture-file> -> path to a single-command stub sink that
# writes the telemetry envelope it reads on stdin to the capture file. The
# producer runs the sink fire-and-forget, so tests point HOOK_TELEMETRY_SINK at
# this stub and poll the capture file with wait_for_sink.
make_sink() {
  local s
  # shellcheck disable=SC2154  # TEST_TMPDIR is a caller contract
  s="$(mktemp "$TEST_TMPDIR/sink.XXXXXX")"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cat >%q\n' "$1"
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
