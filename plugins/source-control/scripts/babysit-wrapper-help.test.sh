#!/usr/bin/env bash
# Regression tests for the bin/ wrappers' --help path.
#
# /source-control:setup's lane-script reachability probe (#787) invokes
# `bin/source-control-babysit-merge --help` as a permission canary: the exact
# path form the lane mandates for every merge, chosen because it is provably
# non-mutating. That framing is only honest while --help genuinely short-circuits
# -- reaching no network, needing no allowlist, and exiting 0. If it ever
# regressed to a live call, a read-only `check` run would start touching the
# fleet it was asked to inspect. So the canary's harmlessness is pinned here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SCRIPT_DIR/../bin"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 ||
  skip_suite "no python interpreter; the wrappers cannot run"

# A gh stub that fails loudly stands in for the network: --help must never reach
# it, so any invocation at all is the regression this suite exists to catch.
NO_NET_BIN="$(mktemp -d)"
trap 'rm -rf "$NO_NET_BIN"' EXIT
cat >"$NO_NET_BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh must not be invoked by --help\n' >&2
exit 90
STUB
chmod +x "$NO_NET_BIN/gh"

# --- Case: merge wrapper --help is the non-mutating canary -------------------
merge_out=$(PATH="$NO_NET_BIN:$PATH" bash "$BIN/source-control-babysit-merge" --help 2>&1)
assert_exit "merge --help exit 0 (canary is a PASS when reachable)" 0 "$?"
assert_contains "merge --help prints usage" "$merge_out" "usage: babysit_merge.py"
assert_not_contains "merge --help never reaches gh" "$merge_out" "gh must not be invoked"
# No --allowed-owners is supplied and no `pr` positional either: had --help not
# short-circuited, argparse would have demanded the positional and the
# fail-closed allowlist guard would have refused, instead of printing usage.
# (The flag NAME appears in the usage text, so the assertion keys on the
# refusal's JSON payload, not on the word.)
assert_not_contains "merge --help does not reach the fail-closed guard" \
  "$merge_out" '"inScope"'

# --- Case: the resolve wrapper behaves the same ------------------------------
resolve_out=$(PATH="$NO_NET_BIN:$PATH" bash "$BIN/source-control-babysit-resolve-thread" --help 2>&1)
assert_exit "resolve --help exit 0" 0 "$?"
assert_contains "resolve --help prints usage" "$resolve_out" "usage: babysit_resolve_thread.py"
assert_not_contains "resolve --help never reaches gh" "$resolve_out" "gh must not be invoked"

# --- Case: the wrapper's own refusal is not weakened by --help ---------------
# --allow-unpinned-head is refused BEFORE the interpreter runs, so pairing it
# with --help must still refuse (exit 2) rather than printing usage -- the guard
# is not a help-time nicety.
unpinned_out=$(bash "$BIN/source-control-babysit-merge" --help --allow-unpinned-head 2>&1)
assert_exit "unpinned-head refused even alongside --help" 2 "$?"
assert_contains "unpinned-head refusal names the flag" "$unpinned_out" "--allow-unpinned-head"

[[ $FAILED -eq 0 ]] || exit 1
