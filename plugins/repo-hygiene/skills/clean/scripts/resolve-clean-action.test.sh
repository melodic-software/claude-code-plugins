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

assert_action "empty -> menu" "" "menu"
assert_action "scan" "scan" "scan"
assert_action "inventory alias" "inventory" "scan"
assert_action "fresh alias" "fresh" "tree"
assert_action "fresh-pull alias" "fresh-pull" "tree"
assert_action "build alias" "artifacts" "build"
assert_action "git alias" "branches" "git"
assert_action "tree-batch token" "tree-batch" "tree-batch"
assert_action "batch alias" "batch" "tree-batch"
assert_action "fleet alias" "fleet" "tree-batch"
assert_action "every-repo phrase" "reset every repo" "tree-batch"
assert_action "ghq list phrase" "reset from ghq list" "tree-batch"
assert_action "conflicting tokens -> menu" "scan tree" "menu"
# Selective-tier fleet spellings — sanctioned explicit tokens.
assert_action "caches-batch token" "caches-batch" "caches-batch"
assert_action "caches-fleet alias" "caches-fleet" "caches-batch"
assert_action "build-batch token" "build-batch" "build-batch"
assert_action "build-fleet alias" "build-fleet" "build-batch"
assert_action "git-batch token" "git-batch" "git-batch"
assert_action "prune-batch alias" "prune-batch" "git-batch"
assert_action "all-batch token" "all-batch" "all-batch"
assert_action "sweep-batch alias" "sweep-batch" "all-batch"
# all-batch must NOT be preempted by the fleet-phrase upgrade that targets bare `all`.
assert_action "all-batch is selective, not tree-batch" "all-batch" "all-batch"
# A selective tier token + a fleet indicator must route to the (non-destructive)
# selective batch form, never the destructive tree-batch. This is the safety fix:
# "clean caches across all repos" previously went to menu / risked tree-batch.
assert_action "caches + across-all-repos phrase -> caches-batch" "clean caches across all repos" "caches-batch"
assert_action "caches + bare fleet token -> caches-batch (not tree-batch)" "caches fleet" "caches-batch"
assert_action "build + all-my-repos phrase -> build-batch" "clear build artifacts across all my repos" "build-batch"
assert_action "git + fleet phrase -> git-batch" "prune git across the fleet" "git-batch"
# No selective tier present: a bare fleet phrase is still the destructive tree-batch.
assert_action "bare fleet phrase still tree-batch" "reset the whole fleet" "tree-batch"
# A bare "all" token must not preempt a fleet phrase: "reset all my repos" is the
# multi-repo tree-batch, not the single-repo `all` sweep.
assert_action "all-my-repos phrase beats bare all token" "reset all my repos" "tree-batch"
assert_action "reset-all phrase -> tree-batch" "reset all" "tree-batch"
# Regression guard: bare "all" with no fleet phrase is still the single-repo tier.
assert_action "bare all -> single-repo all" "all" "all"
assert_action "everything alias -> single-repo all" "everything" "all"
# A genuine conflict (explicit non-all token + fleet phrase) still routes to menu.
assert_action "scan + fleet phrase -> menu" "scan all repos" "menu"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: resolve-clean-action.sh tests passed"
