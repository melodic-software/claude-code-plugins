#!/usr/bin/env bash
# Tests for resolve-clean-action.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

RESOLVE="$SCRIPT_DIR/resolve-clean-action.sh"
FAILED=0

assert_action() {
  local label="$1" args="$2" want="$3"
  local out argv
  read -ra argv <<<"$args"
  out="$(bash "$RESOLVE" "${argv[@]}")"
  assert_contains "$label" "$out" "Action: $want"
}

# assert_note LABEL WANT ARG... — args passed verbatim (each a distinct token) so
# a multi-word note stays one logical note.
assert_note() {
  local label="$1" want="$2"
  shift 2
  local out
  out="$(bash "$RESOLVE" "$@")"
  assert_contains "$label" "$out" "Note: $want"
}

assert_no_note() {
  local label="$1"
  shift
  local out
  out="$(bash "$RESOLVE" "$@")"
  assert_not_contains "$label" "$out" "Note:"
}

assert_action "empty -> menu" "" "menu"
assert_action "scan" "scan" "scan"
assert_action "inventory alias" "inventory" "scan"
assert_action "fresh alias" "fresh" "tree"
assert_action "fresh-pull alias" "fresh-pull" "tree"
assert_action "build alias" "artifacts" "build"
assert_action "git alias" "branches" "git"
assert_action "stash token" "stash" "stash"
assert_action "stashes alias" "stashes" "stash"
assert_action "stash-audit alias" "stash-audit" "stash"
assert_action "tree-batch token" "tree-batch" "tree-batch"
assert_action "batch alias" "batch" "tree-batch"
assert_action "fleet alias" "fleet" "tree-batch"
assert_action "every-repo phrase" "reset every repo" "tree-batch"
assert_action "ghq list phrase" "reset from ghq list" "tree-batch"
assert_action "conflicting tokens -> menu" "scan tree" "menu"
# A bare "all" token must not preempt a fleet phrase: "reset all my repos" is the
# multi-repo tree-batch, not the single-repo `all` sweep.
assert_action "all-my-repos phrase beats bare all token" "reset all my repos" "tree-batch"
assert_action "reset-all phrase -> tree-batch" "reset all" "tree-batch"
# Regression guard: bare "all" with no fleet phrase is still the single-repo tier.
assert_action "bare all -> single-repo all" "all" "all"
assert_action "everything alias -> single-repo all" "everything" "all"
# A genuine conflict (explicit non-all token + fleet phrase) still routes to menu.
assert_action "scan + fleet phrase -> menu" "scan all repos" "menu"

# Multi-arg intent: a leading action token still resolves, and the trailing free
# text (a question, live-session constraints) surfaces as an advisory Note.
assert_action "action token before note still resolves" "all mind the live sessions" "all"
assert_note "trailing text becomes note" "mind the live sessions" all mind the live sessions
assert_note "question after action becomes note" "does this include stashes" scan does this include stashes
# A single quoted multi-line note stays one note verbatim.
assert_note "multiline note preserved" $'6-7 live sessions\nmind WIP' all $'6-7 live sessions\nmind WIP'
# No spurious note when the action stands alone or the whole input is one phrase.
assert_no_note "bare action emits no note" all
assert_no_note "fleet phrase emits no note" reset all my repos

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: resolve-clean-action.sh tests passed"
