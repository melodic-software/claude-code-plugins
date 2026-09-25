#!/usr/bin/env bash
# Self-contained tests for user-scope.sh: every fixture root lives under a
# mktemp directory, with HOME and CLAUDE_CONFIG_DIR pointed there, so the real
# ~/.claude is never read.
set -uo pipefail

export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
US="$SCRIPT_DIR/user-scope.sh"
DETECT="$SCRIPT_DIR/detect.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
TEST_TMPDIR="$(cd -P "$TEST_TMPDIR" && pwd)"
export HOME="$TEST_TMPDIR/home"
export CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig"
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME/.claude" "$CLAUDE_PROJECT_DIR"

FAILED=0
CASE_NUM=0
SKIPPED=0
# PASS + FAIL + SKIP when every case runs; see detect.test.sh for the contract.
EXPECTED_CASES=47

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}
# assert_line <name> <text> <line>: the text holds that exact line.
assert_line() {
  if grep -qxF -- "$3" <<<"$2"; then pass "$1"; else fail "$1" "line: $3" "$2"; fi
}
assert_no_line() {
  if grep -qxF -- "$3" <<<"$2"; then fail "$1" "no line: $3" "present"; else pass "$1"; fi
}

mkfile() {
  mkdir -p "$(dirname "$1")"
  printf 'text\n' >"$1"
}

# --- fixture root ----------------------------------------------------------------

F="$TEST_TMPDIR/cfg"
listed=(
  CLAUDE.md
  rules/a.md
  rules/sub/b.md
  skills/s1/SKILL.md
  skills/s1/ref/guide.md
  commands/c.md
  commands/ns/d.md
  agents/ag.md
  agents/team/ag2.md
  output-styles/o.md
)
decoys=(
  plugins/x.md
  backups/x.md
  references/x.md
  notes.md
  skills/nodir/x.md
  output-styles/sub/x.md
  skills/s1/notes.txt
  rules/r.txt
)
memory=(
  projects/p1/memory/MEMORY.md
  projects/p1/memory/topic.md
  agent-memory/ag/MEMORY.md
)
for f in "${listed[@]}" "${decoys[@]}" "${memory[@]}"; do mkfile "$F/$f"; done
mkdir -p "$F/rules/y.md"
mkfile "$HOME/.claude/CLAUDE.md"

expected="$(for f in "${listed[@]}"; do printf '%s\n' "$F/$f"; done | sort)"

# --- default listing -------------------------------------------------------------

out="$(CLAUDE_CONFIG_DIR="$F" bash "$US" 2>"$TEST_TMPDIR/err")"
rc=$?
assert_exit "default: exit 0" 0 "$rc"
assert_eq "default: exactly the surface files, sorted" "$out" "$expected"
for f in "${listed[@]}"; do
  assert_line "default: lists $f" "$out" "$F/$f"
done
for f in "${decoys[@]}"; do
  assert_no_line "default: leaves out $f" "$out" "$F/$f"
done
assert_no_line "default: leaves out a directory named y.md" "$out" "$F/rules/y.md"
assert_no_line "default: leaves out auto memory" "$out" "$F/${memory[0]}"
assert_no_line "default: leaves out agent memory" "$out" "$F/${memory[2]}"
assert_no_line "default: CLAUDE_CONFIG_DIR wins over HOME" "$out" "$HOME/.claude/CLAUDE.md"

# --- --memory --------------------------------------------------------------------

out="$(CLAUDE_CONFIG_DIR="$F" bash "$US" --memory 2>/dev/null)"
rc=$?
assert_exit "memory: exit 0" 0 "$rc"
for f in "${memory[@]}"; do
  assert_line "memory: lists $f" "$out" "$F/$f"
done
assert_line "memory: still lists CLAUDE.md" "$out" "$F/CLAUDE.md"

# --- root resolution -------------------------------------------------------------

out="$(CLAUDE_CONFIG_DIR="" bash "$US" 2>/dev/null)"
assert_eq "root: an empty CLAUDE_CONFIG_DIR falls back to HOME" "$out" "$HOME/.claude/CLAUDE.md"
out="$(bash "$US" 2>/dev/null)"
assert_eq "root: no CLAUDE_CONFIG_DIR reads HOME/.claude" "$out" "$HOME/.claude/CLAUDE.md"
out="$(cd "$TEST_TMPDIR" && CLAUDE_CONFIG_DIR=cfg bash "$US" 2>/dev/null)"
assert_line "root: a relative CLAUDE_CONFIG_DIR prints absolute paths" "$out" "$F/CLAUDE.md"

err="$(CLAUDE_CONFIG_DIR="$TEST_TMPDIR/absent" bash "$US" 2>&1 >/dev/null)"
rc=$?
assert_exit "root: a missing root exits 2" 2 "$rc"
assert_contains "root: the message names the missing root" "$err" "$TEST_TMPDIR/absent"

mkdir -p "$TEST_TMPDIR/empty"
out="$(CLAUDE_CONFIG_DIR="$TEST_TMPDIR/empty" bash "$US" 2>"$TEST_TMPDIR/err")"
rc=$?
assert_exit "root: an empty root exits 0" 0 "$rc"
assert_eq "root: an empty root prints nothing" "$out" ""
assert_contains "root: an empty root notes the root on stderr" "$(cat "$TEST_TMPDIR/err")" "$TEST_TMPDIR/empty"

# --- usage -----------------------------------------------------------------------

CLAUDE_CONFIG_DIR="$F" bash "$US" --bogus >/dev/null 2>&1
assert_exit "usage: an unknown argument exits 2" 2 "$?"
out="$(bash "$US" --help 2>&1)"
rc=$?
assert_exit "usage: --help exits 0" 0 "$rc"
assert_contains "usage: --help prints usage" "$out" "user-scope.sh [--memory] [--help]"

# --- non-regular and odd paths ---------------------------------------------------

FF="$TEST_TMPDIR/fifo"
mkfile "$FF/rules/ok.md"
if command -v mkfifo >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1 && mkfifo "$FF/rules/x.md"; then
  CLAUDE_CONFIG_DIR="$FF" timeout 10 bash "$US" >"$TEST_TMPDIR/fifo-out" 2>/dev/null
  rc=$?
  : <>"$FF/rules/x.md"
  assert_exit "fifo: returns within the timeout" 0 "$rc"
  assert_eq "fifo: a FIFO named x.md is not listed" "$(cat "$TEST_TMPDIR/fifo-out")" "$FF/rules/ok.md"
else
  skip "fifo: returns within the timeout" "no mkfifo or timeout"
  skip "fifo: a FIFO named x.md is not listed" "no mkfifo or timeout"
fi

NL="$TEST_TMPDIR/newline"
mkfile "$NL/rules/ok.md"
if printf 'text\n' >"$NL/rules/bad"$'\n'"name.md" 2>/dev/null && [[ -f "$NL/rules/bad"$'\n'"name.md" ]]; then
  out="$(CLAUDE_CONFIG_DIR="$NL" bash "$US" 2>"$TEST_TMPDIR/err")"
  assert_eq "newline: the path is skipped, never split into rows" "$out" "$NL/rules/ok.md"
  assert_contains "newline: a warning names the skip" "$(cat "$TEST_TMPDIR/err")" "skipped a path holding a newline"
else
  skip "newline: the path is skipped, never split into rows" "file system refuses a newline in a name"
  skip "newline: a warning names the skip" "file system refuses a newline in a name"
fi

TB="$TEST_TMPDIR/tab"
mkfile "$TB/rules/ok.md"
if printf 'text\n' >"$TB/rules/a"$'\t'"b.md" 2>/dev/null && [[ -f "$TB/rules/a"$'\t'"b.md" ]]; then
  out="$(CLAUDE_CONFIG_DIR="$TB" bash "$US" 2>/dev/null)"
  assert_eq "tab: a path holding a tab is skipped" "$out" "$TB/rules/ok.md"
else
  skip "tab: a path holding a tab is skipped" "file system refuses a tab in a name"
fi

# --- detect.sh consumes the list -------------------------------------------------

CLAUDE_CONFIG_DIR="$F" bash "$US" >"$TEST_TMPDIR/list.txt" 2>/dev/null
bash "$DETECT" --list-targets --paths-file "$TEST_TMPDIR/list.txt" >"$TEST_TMPDIR/targets.tsv" 2>"$TEST_TMPDIR/err"
rc=$?
assert_exit "detect: --list-targets --paths-file accepts the list" 0 "$rc"
assert_eq "detect: one target row per listed file" \
  "$(awk 'NF' "$TEST_TMPDIR/targets.tsv" | wc -l | tr -d ' ')" "${#listed[@]}"

# --- Result ---------------------------------------------------------------------

echo
TOTAL=$((CASE_NUM + SKIPPED))
RC=0
if [[ "$TOTAL" -ne "$EXPECTED_CASES" ]]; then
  RC=1
  printf 'CASE COUNT MISMATCH: ran %d cases (%d pass/fail + %d host skip), expected %d.\n' \
    "$TOTAL" "$CASE_NUM" "$SKIPPED" "$EXPECTED_CASES" >&2
fi
if [[ "$FAILED" -ne 0 ]]; then
  RC=1
  echo "$FAILED of $CASE_NUM cases FAILED, $SKIPPED host skip(s)"
elif [[ "$RC" -eq 0 ]]; then
  echo "All $CASE_NUM cases passed, $SKIPPED host skip(s)"
fi
exit "$RC"
