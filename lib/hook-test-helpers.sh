# shellcheck shell=bash
# Fixture repos must never resolve to the caller's repository or git config: https://github.com/melodic-software/claude-code-plugins/issues/2840
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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

assert_eq() {
  if [[ "$3" == "$2" ]]; then ok "$1 ($3)"; else bad "$1: expected '$2', got '$3'"; fi
}
assert_exit() {
  if [[ "$3" == "$2" ]]; then ok "$1 (exit $3)"; else bad "$1: expected exit $2, got $3"; fi
}
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1: '$3' not in: $2"; fi
}
assert_absent() {
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1: unexpected '$3' in: $2"; fi
}
assert_silent() {
  if [[ -z "$2" ]]; then ok "$1"; else bad "$1: expected empty output, got: $2"; fi
}
assert_file_absent() {
  if [[ ! -e "$2" ]]; then ok "$1"; else bad "$1: file exists: $2"; fi
}

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

drive_with_sink() {
  local __hook="$1" __payload="$2" __cap="$3" __sink
  shift 3
  : >"$__cap"
  __sink="$(make_sink "$__cap")"
  env HOOK_TELEMETRY_SINK="$__sink" "$@" bash "$__hook" <<<"$__payload" >/dev/null 2>&1
}

emit_envelope() {
  drive_with_sink "$@"
  wait_for_sink "$3"
}

expect_no_envelope() {
  local __label="$1"
  shift
  drive_with_sink "$@"
  if wait_for_sink "$3" 25; then
    bad "$__label: unexpected envelope: $(cat "$3")"
  else
    ok "$__label"
  fi
}

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
