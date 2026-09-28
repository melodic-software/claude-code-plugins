#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# RUNS the full abstract suite against the consume-only jira adapter.
# Every exercised path is pre-network. The run keeps a private temp root, a
# private git config, and a PATH that cannot see another job's fixture bin or
# the real gh/curl (#3694). One CPU already passed this suite 10/10, so the
# serial allowlist was shared state, not a CPU budget.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../run-conformance.sh"
source "$SCRIPT_DIR/../../tests/lib.sh"

# shellcheck source=jira.sh
source "$SCRIPT_DIR/jira.sh"

PRIVATE="$(mktemp -d)"
trap 'rm -rf "$PRIVATE"' EXIT
mkdir -p "$PRIVATE/tmp" "$PRIVATE/home" "$PRIVATE/bin"
export TMPDIR="$PRIVATE/tmp"
export TMP="$PRIVATE/tmp"
export TEMP="$PRIVATE/tmp"
export HOME="$PRIVATE/home"
export GIT_CONFIG_GLOBAL="$PRIVATE/home/.gitconfig"
export GIT_CONFIG_NOSYSTEM=1
: >"$GIT_CONFIG_GLOBAL"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

# System directories only. The inherited PATH carries other jobs' fixture bins
# (and this checkout's node_modules/.bin). gh and curl exist only as the
# blocking shim, on both passes.
SAFE_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
write_blocking_network_shim "$PRIVATE/bin"
export PATH="$PRIVATE/bin:$SAFE_PATH"

assert_eq "gh on the conformance PATH is the blocking shim" \
  "$PRIVATE/bin/gh" "$(command -v gh)"
assert_eq "curl on the conformance PATH is the blocking shim" \
  "$PRIVATE/bin/curl" "$(command -v curl)"
assert_eq "conformance temp root is private" "$PRIVATE/tmp" "$TMPDIR"

CB_REPO=""
for fn in cb_setup cb_teardown; do
  assert_succeeds "jira binding exposes $fn" "declared" "missing" declare -F "$fn"
done
assert_eq "consume-only binding leaves CB_REPO empty" "" "$CB_REPO"

# Both passes are pre-network. The second name is the historical shim case.
bash "$RUNNER" --binding jira >/dev/null 2>&1
assert_eq "conformance --binding jira exit 0" "0" "$?"

bash "$RUNNER" --binding jira >/dev/null 2>&1
assert_eq "conformance --binding jira exit 0 under gh/curl-blocking shim" "0" "$?"

[[ $FAILED -eq 0 ]] || exit 1
