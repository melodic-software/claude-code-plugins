#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# Wires the jira conformance run into shell-test discovery (offline, in-CI). Like the
# local-markdown binding test, this RUNS the full abstract conformance suite through
# the core CLI against the jira adapter — once normally, once under a PATH shim that
# makes gh/curl fail. The consume-only jira manifest means every exercised path is
# pre-network (capabilities cats the manifest; write verbs + list-sub-items exit 6 at
# the gate; read verbs are never seeded because create-item=false), so the suite must
# pass even with curl blocked — proving no exercised path reaches Jira.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../run-conformance.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/lib.sh"

CB_REPO=""
# shellcheck source=jira.sh
source "$SCRIPT_DIR/jira.sh"
for fn in cb_setup cb_teardown; do
  if declare -F "$fn" >/dev/null; then
    pass "jira binding exposes $fn"
  else
    fail "jira binding exposes $fn" "declared" "missing"
  fi
done
assert_eq "consume-only binding leaves CB_REPO empty" "" "$CB_REPO"

# Full suite, exit 0.
bash "$RUNNER" --binding jira >/dev/null 2>&1
assert_eq "conformance --binding jira exit 0" "0" "$?"

# Zero-network: a PATH shim makes gh + curl exit 1; the suite must still pass,
# proving the consume-only adapter never reaches for a network tool on any exercised
# path (no unshare -n on Git Bash).
SHIM="$(mktemp -d)"
# shellcheck disable=SC2016  # shim body is literal by design — $(basename) evaluates at shim runtime
printf '#!/usr/bin/env bash\necho "blocked: $(basename "$0")" >&2\nexit 1\n' >"$SHIM/gh"
cp "$SHIM/gh" "$SHIM/curl"
chmod +x "$SHIM/gh" "$SHIM/curl"
PATH="$SHIM:$PATH" bash "$RUNNER" --binding jira >/dev/null 2>&1
assert_eq "conformance --binding jira exit 0 under gh/curl-blocking shim" "0" "$?"
rm -rf "$SHIM"

[[ $FAILED -eq 0 ]] || exit 1
