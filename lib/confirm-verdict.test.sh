#!/usr/bin/env bash
# Tests for lib/confirm-verdict.sh: a /verification:confirm verdict is stored for the head it
# judged, and the ready report reads it for that head only, without ever refusing.
#
# Expected values come from the verdict words and plan-item statuses /verification:confirm
# defines (CONFIRMED, NEEDS WORK, NOT VERIFIED; MISSING, PARTIAL), not from the script.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/confirm-verdict.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "want exit $2, got $3"; fi
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi
}
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "[$2] lacks [$3]"; fi
}
assert_not_contains() {
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "[$2] has [$3]"; fi
}

export CONFIRM_VERDICT_DIR="$TMP/state"
HEAD_A=$(printf 'a%.0s' $(seq 40))
HEAD_B=$(printf 'b%.0s' $(seq 40))

out=$(bash "$SCRIPT" show --head "$HEAD_A" 2>&1)
assert_exit "show with nothing recorded exits 0" 0 "$?"
assert_eq "show with nothing recorded says no verdict for the head" \
  "confirm: no verdict recorded for head $HEAD_A" "$out"

bash "$SCRIPT" record --head "$HEAD_A" --verdict 'NEEDS WORK' \
  --missing 'AC2: the report names the verdict' --partial 'AC3: earlier-head case untested'
assert_exit "recording a NEEDS WORK verdict with items succeeds" 0 "$?"
assert_eq "the record stores the verdict and each item for that head" \
  "verdict: NEEDS WORK
MISSING: AC2: the report names the verdict
PARTIAL: AC3: earlier-head case untested" "$(cat "$CONFIRM_VERDICT_DIR/$HEAD_A")"

out=$(bash "$SCRIPT" show --head "$HEAD_A" 2>&1)
assert_exit "show of a NEEDS WORK verdict exits 0, so it cannot stop the flip" 0 "$?"
assert_eq "show names the verdict, the head and each MISSING or PARTIAL item" \
  "confirm: NEEDS WORK for head $HEAD_A
  MISSING: AC2: the report names the verdict
  PARTIAL: AC3: earlier-head case untested" "$out"

out=$(bash "$SCRIPT" show --head "$HEAD_B" 2>&1)
assert_exit "show for a later head exits 0" 0 "$?"
assert_eq "a verdict recorded for an earlier head does not cover a later head" \
  "confirm: no verdict recorded for head $HEAD_B" "$out"
assert_not_contains "the later head's report carries none of the earlier head's items" "$out" "MISSING"

bash "$SCRIPT" record --head "$HEAD_A" --verdict CONFIRMED
assert_exit "recording a verdict with no items succeeds" 0 "$?"
out=$(bash "$SCRIPT" show --head "$HEAD_A" 2>&1)
assert_eq "a later record for the same head replaces the earlier one" \
  "confirm: CONFIRMED for head $HEAD_A" "$out"

bash "$SCRIPT" record --head "$HEAD_B" --verdict 'NOT VERIFIED'
assert_eq "NOT VERIFIED is stored as given" "verdict: NOT VERIFIED" "$(cat "$CONFIRM_VERDICT_DIR/$HEAD_B")"

HEAD_C=$(printf 'c%.0s' $(seq 40))
printf 'garbage\n' >"$CONFIRM_VERDICT_DIR/$HEAD_C"
out=$(bash "$SCRIPT" show --head "$HEAD_C" 2>&1)
assert_exit "an unreadable record still exits 0" 0 "$?"
assert_contains "an unreadable record is reported as such" "$out" "unreadable verdict record for head $HEAD_C"
printf 'verdict: MAYBE\n' >"$CONFIRM_VERDICT_DIR/$HEAD_C"
out=$(bash "$SCRIPT" show --head "$HEAD_C" 2>&1)
assert_contains "an unknown recorded verdict is reported as unreadable" "$out" "unreadable"

bash "$SCRIPT" record --head "$HEAD_A" --verdict maybe >/dev/null 2>&1
assert_exit "an unknown verdict is a usage error" 1 "$?"
bash "$SCRIPT" record --head "$HEAD_A" --verdict CONFIRMED --missing '' >/dev/null 2>&1
assert_exit "an empty item is a usage error" 1 "$?"
bash "$SCRIPT" record --head "$HEAD_A" --verdict CONFIRMED --missing $'two\nlines' >/dev/null 2>&1
assert_exit "a multi-line item is a usage error" 1 "$?"
bash "$SCRIPT" show --head "$HEAD_A" --verdict CONFIRMED >/dev/null 2>&1
assert_exit "show with --verdict is a usage error" 1 "$?"
bash "$SCRIPT" show --head abc123 >/dev/null 2>&1
assert_exit "a short sha is a usage error" 1 "$?"
bash "$SCRIPT" bogus >/dev/null 2>&1
assert_exit "an unknown subcommand is a usage error" 1 "$?"

# Without CONFIRM_VERDICT_DIR, a record made from a linked worktree reaches a show from the main
# checkout of the same repository.
unset CONFIRM_VERDICT_DIR
REPO="$TMP/main" WT="$TMP/linked"
git init -q "$REPO" && git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$REPO" worktree add -q -b feat "$WT"
HEAD_W=$(git -C "$WT" rev-parse HEAD)
(cd "$WT" && bash "$SCRIPT" record --head "$HEAD_W" --verdict 'NEEDS WORK' --missing 'AC1')
out=$(cd "$REPO" && bash "$SCRIPT" show --head "$HEAD_W" 2>&1)
assert_contains "a record from a linked worktree reaches a show from the main checkout" "$out" "NEEDS WORK for head $HEAD_W"
git -C "$WT" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m next
HEAD_W2=$(git -C "$WT" rev-parse HEAD)
out=$(cd "$WT" && bash "$SCRIPT" show --head "$HEAD_W2" 2>&1)
assert_eq "a commit after the record voids it for the new head" "confirm: no verdict recorded for head $HEAD_W2" "$out"

mkdir -p "$TMP/norepo"
export GIT_CEILING_DIRECTORIES="$TMP"
out=$(cd "$TMP/norepo" && bash "$SCRIPT" show --head "$HEAD_A" 2>&1)
assert_exit "show outside a repository exits 0" 0 "$?"
assert_contains "show outside a repository says no verdict is readable" "$out" "no verdict readable"
(cd "$TMP/norepo" && bash "$SCRIPT" record --head "$HEAD_A" --verdict CONFIRMED >/dev/null 2>&1)
assert_exit "record outside a repository cannot write state" 2 "$?"

((FAILED == 0)) || exit 1
exit 0
