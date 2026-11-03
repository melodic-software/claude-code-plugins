#!/usr/bin/env bash
# Self-contained contract tests for open-pr-count.sh (network-free: gh is
# stubbed via a PATH shim so no real GitHub calls happen).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/open-pr-count.sh"
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

# PATH shim: a fake `gh` whose behavior is driven by GH_STUB_MODE. It prints
# "<open PRs listed> <tidy PRs among them>", as the script's --jq filter does,
# and fails a search read: the script must list, not search.
mkdir -p "$TEST_TMPDIR/bin"
cat >"$TEST_TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in *--search*) exit 64 ;; *"--limit 1000"*) ;; *) exit 65 ;; esac
case "${GH_STUB_MODE:-}" in
  count0) echo "5 0" ;;
  count1) echo "9 1" ;;
  count2) echo "9 2" ;;
  count3) echo "12 3" ;;
  full) echo "1000 0" ;;
  fail | *) exit 4 ;;
esac
EOF
chmod +x "$TEST_TMPDIR/bin/gh"
STUB_PATH="$TEST_TMPDIR/bin:$PATH"

# --- 1. --help contract ---------------------------------------------------------

help_out=$(bash "$SCRIPT" --help 2>&1)
help_exit=$?
assert_exit "--help exits 0" 0 "$help_exit"
assert_contains "--help mentions throttle" "$help_out" "Throttle"

# --- 2. Below-throttle count ----------------------------------------------------

out=$(PATH="$STUB_PATH" GH_STUB_MODE=count0 bash "$SCRIPT" 2>&1)
rc=$?
assert_exit "count 0 exits 0" 0 "$rc"
assert_contains "count 0 reported" "$out" "Open tidy PR count: 0"
assert_contains "count 0 throttle inactive" "$out" "Throttle active: no"

# --- 3. At-throttle count -------------------------------------------------------

out=$(PATH="$STUB_PATH" GH_STUB_MODE=count3 bash "$SCRIPT" 2>&1)
rc=$?
assert_exit "count 3 exits 0" 0 "$rc"
assert_contains "count 3 throttle active" "$out" "Throttle active: yes"

# --- 3b. A listing that fills its limit throttles -------------------------------

out=$(PATH="$STUB_PATH" GH_STUB_MODE=full bash "$SCRIPT" 2>&1)
rc=$?
assert_exit "full page exits 0" 0 "$rc"
assert_contains "full page reports a floor" "$out" "Open tidy PR count: 0 or more"
assert_contains "full page throttle active" "$out" "Throttle active: yes"

# --- 4. gh failure → unknown ----------------------------------------------------

out=$(PATH="$STUB_PATH" GH_STUB_MODE=fail bash "$SCRIPT" 2>&1)
rc=$?
assert_exit "gh failure exits 1" 1 "$rc"
assert_contains "gh failure reports unknown" "$out" "Open tidy PR count: unknown"

# --- 5. The limit comes from the upkeep_max_open setting ------------------------

# A repository whose home is <dir>; a consumer's own root, never the plugin's.
new_repo() {
  local repo="$TEST_TMPDIR/$1"
  mkdir -p "$repo/$2"
  git -C "$repo" init -q
  printf '%s\n' "$repo"
}
run_at() {
  PATH="$STUB_PATH" CLAUDE_PROJECT_DIR="$1" GH_STUB_MODE="$2" bash "$SCRIPT" 2>&1
}

repo="$(new_repo set2 docs/conventions)"
printf 'upkeep_max_open: 2\n' >"$repo/docs/conventions/code-tidying.yaml"
out="$(run_at "$repo" count2)"
assert_contains "setting 2, 2 open: throttled" "$out" "Throttle active: yes"
assert_contains "setting 2 names the team layer" "$out" "Throttle limit: 2, team"
out="$(run_at "$repo" count1)"
assert_contains "setting 2, 1 open: not throttled" "$out" "Throttle active: no"

repo="$(new_repo absent docs/conventions)"
out="$(run_at "$repo" count3)"
assert_contains "no file, 3 open: throttled" "$out" "Throttle active: yes"
assert_contains "no file names the default" "$out" "Throttle limit: 3, default"
out="$(run_at "$repo" count2)"
assert_contains "no file, 2 open: not throttled" "$out" "Throttle active: no"

repo="$(new_repo invalid docs/conventions)"
printf 'upkeep_max_open: 0\n' >"$repo/docs/conventions/code-tidying.yaml"
out="$(run_at "$repo" count2)"
assert_contains "invalid value falls to the default" "$out" "Throttle active: no"
assert_contains "invalid value is named" "$out" "docs/conventions/code-tidying.yaml upkeep_max_open: 0 is not valid"

repo="$(new_repo bound team/rules)"
# shellcheck disable=SC2016 # literal backticks: the pointer line's grammar.
printf '<!-- BEGIN GENERATED: convention-home -->\nConventions live in `team/rules`.\n<!-- END GENERATED: convention-home -->\n' >"$repo/AGENTS.md"
printf 'upkeep_max_open: 1\n' >"$repo/team/rules/code-tidying.yaml"
out="$(run_at "$repo" count1)"
assert_contains "the bound home is read" "$out" "Throttle active: yes"

# --- Final report ---------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
