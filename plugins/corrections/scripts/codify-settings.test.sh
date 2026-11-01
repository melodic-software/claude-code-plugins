#!/usr/bin/env bash
# Tests for codify-settings.mjs: the default, the team value, the overlay over the team value, and
# invalid values falling back with a note on stderr, and the per-layer cap on those notes.
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

# 6. A team value above the maximum falls to the default and says why on stderr.
new_repo
setting "$R/docs/conventions/corrections.yaml" 1001
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "over the maximum: default 2 from defaults" test "$(got '"\(.min_occurrences) \(.layer)"')" == "2 defaults"
check "over the maximum: stderr names the key and the bound" grep -q 'team (.*corrections.yaml).*recurrence.min_occurrences.*at most 1000' <<<"$ERR"
setting "$R/docs/conventions/corrections.yaml" 1000
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "at the maximum: 1000 from the team file" test "$(got '"\(.min_occurrences) \(.layer)"')" == "1000 team"

# 7. A layer's errors print the first five, then a count of the rest; five or fewer print in full.
new_repo
{
  for i in $(seq 1 1200); do printf 'unknown_%d: x\n' "$i"; done
  printf 'recurrence:\n  min_occurrences: 4\n'
} >"$R/docs/conventions/corrections.yaml"
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $(head -c 2000 <<<"$ERR")"
check "1200 unknown keys: the valid team value still applies" test "$(got '"\(.min_occurrences) \(.layer)"')" == "4 team"
check "1200 unknown keys: six stderr lines for the layer" test "$(grep -c 'team (' <<<"$ERR")" -eq 6
check "1200 unknown keys: the last line counts the rest" grep -q 'team (.*corrections.yaml): and 1195 more$' <<<"$ERR"
new_repo
{
  for i in $(seq 1 5); do printf 'unknown_%d: x\n' "$i"; done
} >"$R/docs/conventions/corrections.yaml"
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "five unknown keys: all five print" test "$(grep -c 'team (.*unknown key' <<<"$ERR")" -eq 5
check "five unknown keys: no count line" test "$(grep -c 'more$' <<<"$ERR")" -eq 0

# 8. ratchet_offer and review_mining_prs: default, user option, team over user, and an invalid team
# value falling to the default, never to the user option.
# run_user <repo> <reader flags...>: as run, with the flags.
run_user() {
  local dir="$1"
  shift
  (cd "$dir" && node "$READER" "$@") >"$TEST_TMPDIR/out" 2>"$TEST_TMPDIR/err"
  RC=$?
  OUT="$(cat "$TEST_TMPDIR/out")"
  ERR="$(cat "$TEST_TMPDIR/err")"
}
triple() { got "\"\(.$1.value) \(.$1.layer) \(.$1.path)\""; }
USER_OFF=(--user-ratchet-offer false --user-review-mining-prs 40)
new_repo
run_user "$R"
DETAIL="out: $OUT; stderr: $ERR"
check "neither layer: ratchet_offer true from defaults" test "$(triple ratchet_offer)" == "true defaults null"
check "neither layer: review_mining_prs 20 from defaults" test "$(triple review_mining_prs)" == "20 defaults null"
run_user "$R" "${USER_OFF[@]}"
DETAIL="out: $OUT; stderr: $ERR"
check "user only: ratchet_offer false from userConfig" test "$(triple ratchet_offer)" == "false userConfig null"
check "user only: review_mining_prs 40 from userConfig" test "$(triple review_mining_prs)" == "40 userConfig null"
# shellcheck disable=SC2016 # the literal, unrendered placeholder
run_user "$R" --user-ratchet-offer '${user_config.ratchet_offer}' --user-review-mining-prs ''
DETAIL="out: $OUT; stderr: $ERR"
check "placeholder and empty: unset, no note" test "$(triple ratchet_offer) $(triple review_mining_prs) [$ERR]" == "true defaults null 20 defaults null []"
run_user "$R" --user-ratchet-offer true --user-review-mining-prs 20
DETAIL="out: $OUT; stderr: $ERR"
check "a rendered default reads as unset" test "$(triple ratchet_offer) $(triple review_mining_prs)" == "true defaults null 20 defaults null"
run_user "$R" --user-ratchet-offer sometimes --user-review-mining-prs 1
DETAIL="out: $OUT; stderr: $ERR"
check "invalid user values: the defaults" test "$(triple ratchet_offer) $(triple review_mining_prs)" == "true defaults null 20 defaults null"
check "invalid user values: named on stderr" test "$(grep -c -E 'userConfig.*(ratchet_offer|review_mining_prs)' <<<"$ERR")" -eq 2
TEAM=docs/conventions/corrections.yaml
printf 'ratchet_offer: true\nreview_mining_prs: 60\n' >"$R/$TEAM"
run_user "$R" "${USER_OFF[@]}"
DETAIL="out: $OUT; stderr: $ERR"
check "team over user: ratchet_offer true from the team file" test "$(triple ratchet_offer)" == "true team $TEAM"
check "team over user: review_mining_prs 60 from the team file" test "$(triple review_mining_prs)" == "60 team $TEAM"
for bad in sometimes '[]' '"false"'; do
  printf 'ratchet_offer: %s\n' "$bad" >"$R/$TEAM"
  run_user "$R" "${USER_OFF[@]}"
  DETAIL="out: $OUT; stderr: $ERR"
  check "invalid team ratchet_offer ($bad): the default, not the user false" test "$(triple ratchet_offer)" == "true defaults null"
  check "invalid team ratchet_offer ($bad): named on stderr" grep -q 'team (.*corrections.yaml).*ratchet_offer' <<<"$ERR"
done
printf 'review_mining_prs: 201\n' >"$R/$TEAM"
run_user "$R" "${USER_OFF[@]}"
DETAIL="out: $OUT; stderr: $ERR"
check "team review_mining_prs over the maximum: the default, not the user 40" test "$(triple review_mining_prs)" == "20 defaults null"

# 9. A pointer line moves the convention home.
new_repo
mkdir -p "$R/conventions"
cat >"$R/AGENTS.md" <<'EOF'
<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `conventions`.
<!-- END GENERATED: convention-home -->
EOF
setting "$R/conventions/corrections.yaml" 4
run "$R"
DETAIL="exit $RC; out: $OUT; stderr: $ERR; AGENTS.md: $(cat "$R/AGENTS.md")"
check "pointer line: 4 from the team file under the named home" test "$(got '"\(.min_occurrences) \(.path)"')" == "4 conventions/corrections.yaml"

echo "1..$CASE_NUM"
if [[ $FAILED -gt 0 ]]; then
  echo "# $FAILED of $CASE_NUM failed"
  exit 1
fi
