#!/usr/bin/env bash
# The harness runs on this host and refuses a Windows figure that was not measured there.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/measure-hook-log-budget.sh"
DOC="$SCRIPT_DIR/../reference/hook-log-budget.md"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

if ! command -v node >/dev/null 2>&1; then
  printf 'SKIP: node is not on PATH; the harness times the node launcher\n'
  exit 0
fi

chmod +x "$SUT"
OUT="$(bash "$SUT" --samples 3 --record "$TEST_TMPDIR/capture.txt")"
assert_exit "harness exits 0" 0 "$?"
assert_contains "capture names a host" "$OUT" "host: "
assert_contains "node floor" "$OUT" "node_spawn_floor_median_ms: "
assert_contains "kill switch row" "$OUT" "kill_switch_off_median_ms: "
assert_contains "parallel wall off" "$OUT" "parallel_wall_off_ms: "
assert_contains "parallel wall on" "$OUT" "parallel_wall_on_ms: "
assert_contains "4 KB append" "$OUT" "append_4kb_corrupt: "
assert_contains "16 KB append" "$OUT" "append_16kb_corrupt: "
assert_contains "64 KB append lines" "$OUT" "append_64kb_lines: "
assert_contains "64 KB append" "$OUT" "append_64kb_corrupt: "
assert_contains "ls -t order" "$OUT" "ls_t_order: "
assert_contains "late-EOF" "$OUT" "late_eof_ms: "
assert_contains "record file matches stdout" "$(cat "$TEST_TMPDIR/capture.txt")" "bash_spawn_floor_median_ms: "
assert_contains "launcher bash path" "$OUT" "launcher_bash_path: "
assert_contains "invoking bash path" "$OUT" "invoking_bash_path: "
launcher_bash="$(sed -n 's/^launcher_bash_path: //p' <<<"$OUT")"
if [[ -n "$launcher_bash" && "$launcher_bash" != unresolved ]]; then
  pass "launcher resolved a bash ($launcher_bash)"
else
  fail "launcher resolved no bash" "launcher_bash_path=$launcher_bash"
fi

case "${OSTYPE:-}" in
msys* | cygwin*)
  assert_contains "git bash host stamp" "$OUT" "host: windows-git-bash"
  ;;
*)
  if printf '%s' "$OUT" | grep -q 'host: windows-git-bash'; then
    fail "non-windows host stamped a windows capture" "$OUT"
  else
    pass "non-windows host did not stamp a windows capture"
  fi
  ;;
esac

late="$(sed -n 's/^late_eof_ms: //p' <<<"$OUT")"
if [[ "$late" =~ ^[0-9]+$ ]] && [[ "$late" -lt 2000 ]]; then
  pass "late-EOF returned before the writer finished ($late ms)"
else
  fail "late-EOF was not an early return" "late_eof_ms=$late"
fi

corrupt="$(sed -n 's/^append_4kb_corrupt: //p' <<<"$OUT")"
if [[ "$corrupt" =~ ^[0-9]+$ ]]; then
  pass "4 KB corrupt count is an integer ($corrupt)"
else
  fail "4 KB corrupt count is not an integer" "$corrupt"
fi

# A trailing option with no value is a usage error, not an endless loop.
for flag in --samples --record --check-doc; do
  timeout 10 bash "$SUT" "$flag" >/dev/null 2>&1
  assert_exit "$flag without a value exits 2" 2 "$?"
done

OUT="$(bash "$SUT" --check-doc "$DOC")"
assert_exit "recorded doc passes" 0 "$?"
assert_contains "recorded doc is stamped" "$OUT" "doc: windows capture stamped"

FAKE="$TEST_TMPDIR/fake.md"
printf '%s\n' '**Claim:** x' '**Basis:** y' '**As of:** z' '**Recheck:** q' \
  'kill-switch' 'append' 'ls -t' 'late-EOF' 'windows-git-bash: 2.42' >"$FAKE"
OUT="$(bash "$SUT" --check-doc "$FAKE" 2>&1)"
assert_exit "a number without a windows stamp fails" 1 "$?"
assert_contains "the failure names the missing stamp" "$OUT" "windows-git-bash stamp"

if [[ "$FAILED" -eq 0 ]]; then
  echo "all measure-hook-log-budget contract tests passed"
  exit 0
fi
echo "$FAILED measure-hook-log-budget contract test(s) failed" >&2
exit 1
