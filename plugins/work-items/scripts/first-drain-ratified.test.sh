#!/usr/bin/env bash
# A fake `gh` on PATH serves an issue and its event pages from fixture files, so
# the suite decides the ratification verdict from the label and who applied it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/first-drain-ratified.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}
check_rc() { # $1 expected $2 actual $3 label
  if [[ "$2" == "$1" ]]; then
    pass "$3"
  else
    fail "$3 (expected exit $1, got $2)"
  fi
}

BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/gh" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
endpoint=""
for a in "$@"; do
  case "$a" in
  api | -*) : ;;
  *) [[ -z "$endpoint" ]] && endpoint="$a" ;;
  esac
done
path="${endpoint%%\?*}"
fails=" ${FAKE_GH_FAIL:-} "
case "$path" in
*/events)
  [[ "$fails" == *" events "* ]] && exit 1
  cat "$FAKE_DIR"/events-*.json 2>/dev/null || printf '[]\n'
  ;;
*)
  [[ "$fails" == *" issue "* ]] && exit 1
  cat "$FAKE_DIR/issue.json"
  ;;
esac
FAKE
chmod +x "$BIN/gh"
PATH="$BIN:$PATH"
export PATH

LABEL="loop-lane: first-drain-ratified"
REPO=melodic-software/example-repo
ISSUE=42

fresh() {
  FAKE_DIR="$WORK/fx"
  rm -rf "$FAKE_DIR"
  mkdir -p "$FAKE_DIR"
  unset FAKE_GH_FAIL
  export FAKE_DIR
}
labels() { # issue labels, one name per argument
  jq -n '{labels: [$ARGS.positional[] | {name: .}]}' --args "$@" >"$FAKE_DIR/issue.json"
}
event() { # $1 page file, $2 event, $3 label, $4 actor type, $5 actor login, [$6 app slug]
  jq -n --arg e "$2" --arg l "$3" --arg t "$4" --arg a "$5" --arg app "${6:-}" \
    '[{event: $e, label: {name: $l}, actor: {type: $t, login: $a},
       performed_via_github_app: (if $app == "" then null else {slug: $app} end)}]' >"$FAKE_DIR/$1"
}
run() {
  bash "$CHECK" --repo "$REPO" --issue "$ISSUE" >"$WORK/out" 2>"$WORK/err"
  RC=$?
}

# --- a person applied the label: ratified -----------------------------------
fresh
labels "$LABEL" "agent-ready"
event events-1.json labeled "$LABEL" User kyle
run
check_rc 0 "$RC" "a label a User applied is ratified"

# --- the label is absent: not ratified, even with an old labeled event ------
fresh
labels "agent-ready"
event events-1.json labeled "$LABEL" User kyle
run
check_rc 1 "$RC" "a removed label is not ratified"

# --- a Bot applied the label: the lane cannot ratify itself -----------------
fresh
labels "$LABEL"
event events-1.json labeled "$LABEL" Bot 'lane-app[bot]'
run
check_rc 1 "$RC" "a label a Bot applied is not ratified"
if grep -q 'lane-app\[bot\]' "$WORK/err"; then
  pass "the refusal names who applied the label"
else
  fail "bot refusal stderr: $(cat "$WORK/err")"
fi

# --- the most recent application decides, across pages ---------------------
fresh
labels "$LABEL"
event events-1.json labeled "$LABEL" User kyle
event events-2.json labeled "$LABEL" Bot 'lane-app[bot]'
run
check_rc 1 "$RC" "a Bot re-application on a later page overrides an earlier User one"

fresh
labels "$LABEL"
event events-1.json labeled "$LABEL" Bot 'lane-app[bot]'
event events-2.json labeled "$LABEL" User kyle
run
check_rc 0 "$RC" "a User re-application on a later page ratifies"

# --- an App acting through a user token is not a person ---------------------
fresh
labels "$LABEL"
event events-1.json labeled "$LABEL" User kyle lane-app
run
check_rc 1 "$RC" "a User-typed actor acting via a GitHub App is not ratified"

# --- a removal after the last application revokes it ------------------------
# The label reappearing with no fresh application (a rename onto this name)
# must not revive the operator's earlier one.
fresh
labels "$LABEL"
event events-1.json labeled "$LABEL" User kyle
event events-2.json unlabeled "$LABEL" User kyle
run
check_rc 1 "$RC" "a label whose last event is a removal is not ratified"

# --- a labeled event for a different label does not count -------------------
fresh
labels "$LABEL"
event events-1.json labeled "agent-ready" User kyle
run
check_rc 1 "$RC" "a label with no applying event of its own is not ratified"

# --- reads that fail are fail-closed ----------------------------------------
fresh
labels "$LABEL"
FAKE_GH_FAIL=issue
export FAKE_GH_FAIL
run
check_rc 11 "$RC" "a failed issue read exits 11"

fresh
labels "$LABEL"
event events-1.json labeled "$LABEL" User kyle
FAKE_GH_FAIL=events
export FAKE_GH_FAIL
run
check_rc 11 "$RC" "a failed event read exits 11"

fresh
printf 'not json\n' >"$FAKE_DIR/issue.json"
run
check_rc 11 "$RC" "an unparsable issue read exits 11"

# --- argument refusals -------------------------------------------------------
fresh
bash "$CHECK" --repo "owner/repo/../../other" --issue "$ISSUE" >/dev/null 2>&1
check_rc 6 "$?" "a traversal-shaped --repo exits 6"
bash "$CHECK" --repo "../.." --issue "$ISSUE" >/dev/null 2>&1
check_rc 6 "$?" "a dot-segment --repo exits 6"
bash "$CHECK" --repo "$REPO" --issue "4a" >/dev/null 2>&1
check_rc 7 "$?" "a non-numeric --issue exits 7"
bash "$CHECK" --repo "$REPO" --issue "$ISSUE" --bogus >/dev/null 2>&1
check_rc 2 "$?" "an unknown argument exits 2"

if ((FAILED == 0)); then
  printf 'all first-drain-ratified tests passed\n'
  exit 0
fi
printf '%s test(s) failed\n' "$FAILED" >&2
exit 1
