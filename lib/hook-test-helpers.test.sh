#!/usr/bin/env bash
# shellcheck disable=SC2016  # each case's code runs in a child bash that sources the helper first
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook-test-helpers.sh"

T_PASS=0
T_FAIL=0
check() {
  if [[ "$3" == "$2" ]]; then
    echo "ok: $1"
    T_PASS=$((T_PASS + 1))
  else
    echo "FAIL: $1: expected '$2', got '$3'" >&2
    T_FAIL=$((T_FAIL + 1))
  fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

in_helper() {
  bash -c 'source "$1"; shift; eval "$*"' _ "$LIB" "$@"
}

out="$(env -u GIT_CONFIG_GLOBAL GIT_DIR=/nonexistent GIT_CONFIG=/nonexistent \
  bash -c 'source "$1"; printf "%s|%s|%s|%s" "${GIT_DIR-unset}" "${GIT_CONFIG-unset}" "$GIT_CONFIG_GLOBAL" "$GIT_CONFIG_NOSYSTEM"' _ "$LIB")"
check "sourcing clears GIT_DIR and GIT_CONFIG and isolates global and system config" \
  "unset|unset|/dev/null|1" "$out"

out="$(env GIT_CONFIG_GLOBAL="$WORK/chosen" bash -c 'source "$1"; printf "%s" "$GIT_CONFIG_GLOBAL"' _ "$LIB")"
check "a caller-set GIT_CONFIG_GLOBAL is kept" "$WORK/chosen" "$out"

mkdir -p "$WORK/home"
printf '[user]\n\tname = machine-global-name\n' >"$WORK/home/.gitconfig"
out="$(env -u GIT_CONFIG_GLOBAL HOME="$WORK/home" bash -c 'source "$1"; git config --get user.name; echo "rc=$?"' _ "$LIB")"
check "the machine's global git config is not read" "rc=1" "$out"

out="$(in_helper 'ok a >/dev/null; ok b >/dev/null; bad c 2>/dev/null; report >/dev/null; echo "$PASS/$FAIL/$?"')"
check "two ok and one bad count 2/1 and report fails" "2/1/1" "$out"

out="$(in_helper 'ok a >/dev/null; report >/dev/null; echo "$PASS/$FAIL/$?"')"
check "an all-ok run reports success" "1/0/0" "$out"

out="$(in_helper 'assert_eq same x x >/dev/null; assert_eq differ x y 2>/dev/null; echo "$PASS/$FAIL"')"
check "assert_eq passes on equal and fails on unequal" "1/1" "$out"

out="$(in_helper 'assert_contains has "abc" b >/dev/null; assert_absent lacks "abc" b 2>/dev/null; echo "$PASS/$FAIL"')"
check "assert_contains and assert_absent agree on a present needle" "1/1" "$out"

: >"$WORK/empty"
out="$(in_helper "wait_for_sink '$WORK/empty' 1; echo \$?")"
check "wait_for_sink fails when nothing arrives" "1" "$out"

out="$(in_helper "TEST_TMPDIR='$WORK'; s=\$(make_sink '$WORK/cap'); printf envelope | \"\$s\"; wait_for_sink '$WORK/cap' 50; echo \"\$?:\$(cat '$WORK/cap')\"")"
check "make_sink's stub writes its stdin to the capture file" "0:envelope" "$out"

echo
echo "PASS=$T_PASS FAIL=$T_FAIL"
[[ $T_FAIL -eq 0 ]]
