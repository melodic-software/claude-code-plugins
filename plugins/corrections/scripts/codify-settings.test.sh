#!/usr/bin/env bash
# Tests for codify-settings.mjs: the default, the team value, the overlay over the team value, and
# invalid values falling back with a note on stderr.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$SCRIPT_DIR/codify-settings.mjs"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'ok %d - %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n' "$CASE_NUM" "$1"
  if [[ -n "${2:-}" ]]; then printf '  %s\n' "$2"; fi
}
# check <name> <command...>: passes when the command exits 0.
check() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name" "${DETAIL:-}"; fi
  DETAIL=""
}

for tool in git node jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "1..0 # SKIP $tool not available"
    exit 0
  fi
done

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
N=0

# new_repo: sets R to a new empty git repository.
new_repo() {
  N=$((N + 1))
  R="$TEST_TMPDIR/repo$N"
  mkdir -p "$R/docs/conventions"
  git -C "$R" init -q
}
# setting <file> <value>: writes recurrence.min_occurrences into <file>.
setting() { printf 'recurrence:\n  min_occurrences: %s\n' "$2" >"$1"; }
# run <repo>: the reader from inside <repo>; stdout to $OUT, stderr to $ERR.
run() {
  (cd "$1" && node "$READER") >"$TEST_TMPDIR/out" 2>"$TEST_TMPDIR/err"
  RC=$?
  OUT="$(cat "$TEST_TMPDIR/out")"
  ERR="$(cat "$TEST_TMPDIR/err")"
}
# got <jq-filter>: the filter applied to $OUT.
got() { jq -r "$1" <<<"$OUT" 2>/dev/null; }

# 1. No settings file: the default 2 from the defaults layer.
new_repo
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "no file: exits 0" test "$RC" -eq 0
check "no file: default 2 from defaults" test "$(got '"\(.min_occurrences) \(.layer) \(.path)"')" == "2 defaults null"
check "no file: stderr is empty" test -z "$ERR"

# 2. The team file sets the value.
new_repo
setting "$R/docs/conventions/corrections.yaml" 3
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "team: 3 from the team file" test "$(got '"\(.min_occurrences) \(.layer) \(.path)"')" == "3 team docs/conventions/corrections.yaml"

# 3. The personal overlay wins over the team file.
setting "$R/docs/conventions/corrections.local.yaml" 5
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "overlay: 5 from the overlay over the team 3" test "$(got '"\(.min_occurrences) \(.layer) \(.path)"')" == "5 local docs/conventions/corrections.local.yaml"

# 4. An invalid overlay value leaves the team value standing and says why on stderr.
setting "$R/docs/conventions/corrections.local.yaml" 0
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "invalid overlay: exits 0" test "$RC" -eq 0
check "invalid overlay: the team 3 stands" test "$(got '"\(.min_occurrences) \(.layer)"')" == "3 team"
check "invalid overlay: stderr names the key and the overlay" grep -q 'local (.*corrections.local.yaml).*recurrence.min_occurrences' <<<"$ERR"

# 5. An invalid team value falls to the default and says why on stderr.
new_repo
setting "$R/docs/conventions/corrections.yaml" '"three"'
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "invalid team: exits 0" test "$RC" -eq 0
check "invalid team: default 2 from defaults" test "$(got '"\(.min_occurrences) \(.layer)"')" == "2 defaults"
check "invalid team: stderr names the key and the team file" grep -q 'team (.*corrections.yaml).*recurrence.min_occurrences' <<<"$ERR"

# 6. A pointer line moves the convention home.
new_repo
mkdir -p "$R/conventions"
printf '<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in `conventions`.\n<!-- END GENERATED: convention-home -->\n' >"$R/AGENTS.md"
setting "$R/conventions/corrections.yaml" 4
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR; AGENTS.md: $(cat "$R/AGENTS.md")"
check "pointer line: 4 from the team file under the named home" test "$(got '"\(.min_occurrences) \(.path)"')" == "4 conventions/corrections.yaml"

echo "1..$CASE_NUM"
if [[ $FAILED -gt 0 ]]; then
  echo "# $FAILED of $CASE_NUM failed"
  exit 1
fi
