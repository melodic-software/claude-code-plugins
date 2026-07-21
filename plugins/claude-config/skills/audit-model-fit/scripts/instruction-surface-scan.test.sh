#!/usr/bin/env bash
# Tests for instruction-surface-scan.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/instruction-surface-scan.sh"

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
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}

rc=0
bash "$SCAN" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

# Build a throwaway fixture repo with seeded surfaces and smells.
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
(
  cd "$FIX" || exit 1
  git init -q
  mkdir -p .claude/skills/demo/context .claude/agents .claude/rules
  cat >CLAUDE.md <<'MD'
Never force-push to main.
Do not skip the tests.
This line explains a rationale and is fine.
MD
  printf 'name: demo\n' >.claude/skills/demo/SKILL.md
  cat >.claude/skills/demo/context/examples.md <<'MD'
```
a
```
```
b
```
```
c
```
```
d
```
```
e
```
```
f
```
MD
  # Exactly 5 blocks — at the recommended ceiling, must NOT be flagged (C3 boundary).
  cat >.claude/skills/demo/context/at-threshold.md <<'MD'
```
a
```
```
b
```
```
c
```
```
d
```
```
e
```
MD
  printf 'agent body\n' >.claude/agents/x.md
  printf 'a rule\n' >.claude/rules/y.md
)

# Isolate HOME so the real user ~/.claude/CLAUDE.md never leaks into the fixture scan.
rc=0
out="$(cd "$FIX" && HOME="$FIX" bash "$SCAN" 2>/dev/null)" || rc=$?
assert_exit "default mode exits 0" 0 "$rc"
assert_contains "reports CLAUDE.md surface" "$out" "CLAUDE.md files: 1"
assert_contains "reports agent surface" "$out" "Agent definitions: 1"
assert_contains "reports rule surface" "$out" "Rule files (.claude/rules): 1"
assert_contains "flags bare prohibitions" "$out" "Bare-prohibition lines"
assert_contains "flags example-dense file" "$out" "Example-dense files (>5"
# Only the 6-block file counts — the 5-block file at the ceiling is NOT flagged (C3 boundary).
assert_contains "5-block file not flagged; only the 6-block one" "$out" "blocks): 1 files"

cnt="$(cd "$FIX" && HOME="$FIX" bash "$SCAN" --count 2>/dev/null)"
assert_equals "count matches seeded prohibitions" "2" "$cnt"

cand="$(cd "$FIX" && HOME="$FIX" bash "$SCAN" --candidates 2>/dev/null)"
assert_contains "candidates list the CLAUDE.md prohibition line" "$cand" "CLAUDE.md:1"
assert_contains "candidates flag the example-dense file" "$cand" "examples.md:0: EXAMPLE-DENSE"
case "$cand" in
  *at-threshold.md*EXAMPLE-DENSE*) fail "5-block at-threshold.md must not be flagged" "found in candidates" ;;
  *) pass "5-block at-threshold.md absent from candidates" ;;
esac

# Empty repo: still exits 0 with a clean inventory (no crash on no surfaces).
EMPTY="$(mktemp -d)"
(cd "$EMPTY" && git init -q)
rc=0
out="$(cd "$EMPTY" && HOME="$EMPTY" bash "$SCAN" 2>/dev/null)" || rc=$?
assert_exit "empty repo exits 0" 0 "$rc"
assert_contains "empty repo zero prohibitions" "$out" "0 across 0 files"
rm -rf "$EMPTY"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
