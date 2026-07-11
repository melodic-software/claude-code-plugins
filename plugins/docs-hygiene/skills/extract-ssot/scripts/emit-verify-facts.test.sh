#!/usr/bin/env bash
# Self-contained tests for emit-verify-facts.sh (no external test lib — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$SCRIPT_DIR/emit-verify-facts.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE=0

pass() {
  CASE=$((CASE + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE=$((CASE + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n' "$1" "$2" >&2
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "NOT to contain: $3" ;;
  *) pass "$1" ;;
  esac
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1" "exit $2, got $3"
  fi
}

# --- Build a fixture consumer repo with a known duplication cluster. ---
repo="$TEST_TMPDIR/repo"
mkdir -p "$repo/docs" "$repo/.claude/rules"
git -C "$repo" init -q
git -C "$repo" config user.email t@t.t
git -C "$repo" config user.name t

phrase="the quick brown fox jumps over the lazy dog"

cat >"$repo/docs/alpha.md" <<EOF
Alpha doc restates the rule: $phrase.
EOF
cat >"$repo/docs/beta.md" <<EOF
Beta doc restates the rule: $phrase.
It also cites canonical per style-guide.md "Naming rules".
EOF
cat >"$repo/.claude/rules/gamma.md" <<EOF
Gamma rule restates: $phrase.
Primary source: https://platform.claude.com/docs/example
EOF
# Non-markdown file containing the phrase — must NOT count (scope is *.md).
cat >"$repo/script.sh" <<EOF
#!/usr/bin/env bash
echo "$phrase"
EOF
git -C "$repo" add -A
git -C "$repo" commit -qm fixture

# --- Argument handling ---
assert_exit "--help exits 0" 0 "$(
  bash "$EMIT" --help >/dev/null 2>&1
  echo $?
)"
assert_exit "no args exits 2" 2 "$(
  bash "$EMIT" 2>/dev/null
  echo $?
)"
assert_exit "unknown arg exits 2" 2 "$(
  bash "$EMIT" --unknown 2>/dev/null
  echo $?
)"
assert_exit "--phrase with empty value exits 2" 2 "$(
  bash "$EMIT" --phrase 2>/dev/null
  echo $?
)"

# --- Fact emission against the fixture repo ---
out="$(cd "$repo" && bash "$EMIT" --phrase "$phrase")"
assert_contains "phrase echoed" "$out" "Phrase: $phrase"
assert_contains "markdown instances counted" "$out" "Instance hit count: 3"
assert_not_contains "non-markdown file excluded from scope" "$out" "script.sh"
assert_contains "citation pattern counted" "$out" "Citation pattern hit count: 1"
assert_contains "citation sample surfaced" "$out" "docs/beta.md"
assert_contains "primary URL counted" "$out" "Primary URL hit count: 1"
assert_contains "primary URL sample surfaced" "$out" ".claude/rules/gamma.md"
assert_not_contains "no verdict emitted" "$out" "PROCEED"
assert_not_contains "no refusal emitted" "$out" "REFUSE"

# --- Zero-match phrase still exits 0 with zero counts ---
zero_rc=0
zero_out="$(cd "$repo" && bash "$EMIT" --phrase "phrase that matches nothing at all")" || zero_rc=$?
assert_exit "zero-match run exits 0" 0 "$zero_rc"
assert_contains "zero-match instance count" "$zero_out" "Instance hit count: 0"

if [[ $FAILED -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE" >&2
exit 1
