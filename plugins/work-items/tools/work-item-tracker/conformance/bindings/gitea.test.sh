#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# shellcheck disable=SC2030,SC2031  # each guard case runs in its own ( ) so its env changes stay local — that isolation is the point, not an accident
# gitea.sh is a sourceable conformance binding — assert it sources cleanly, exposes the
# cb_setup/cb_teardown contract, and refuses to run without an explicitly named
# throwaway target, all without touching the network.
#
# It does NOT run the suite: create-item is true, so every case would be a live call.
# The live pass is recorded as deferred in the adapter's README.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../tests/lib.sh"
CB_REPO=""
# shellcheck source=gitea.sh
source "$SCRIPT_DIR/gitea.sh"

for fn in cb_setup cb_teardown; do
  assert_succeeds "gitea binding exposes $fn" "declared" "missing" declare -F "$fn"
done

# No default for either half of the target: a destructive suite must never fall back to a
# coordination instance. Both guards fire before any network call.
if (
  unset WIT_CONFORMANCE_GITEA_HOST
  export WIT_CONFORMANCE_GITEA_SCOPE="throwaway/sandbox"
  cb_setup
) 2>/dev/null; then
  fail "cb_setup requires an explicit host" "nonzero exit" "succeeded"
else
  pass "cb_setup requires an explicit host (no retained default)"
fi

if (
  export WIT_CONFORMANCE_GITEA_HOST="git.throwaway.invalid"
  unset WIT_CONFORMANCE_GITEA_SCOPE
  cb_setup
) 2>/dev/null; then
  fail "cb_setup requires an explicit scope" "nonzero exit" "succeeded"
else
  pass "cb_setup requires an explicit scope (no retained default)"
fi

# With both named, cb_setup writes a binding the seam can actually read — a shape error
# here would surface as an opaque exit 3 partway through a live run.
(
  export WIT_CONFORMANCE_GITEA_HOST="git.throwaway.invalid"
  export WIT_CONFORMANCE_GITEA_SCOPE="throwaway/sandbox"
  cb_setup
  jq -e '.provider == "gitea"
    and .config.gitea.host == "git.throwaway.invalid"
    and (.config.gitea.scopes == ["throwaway/sandbox"])
    and (.config.gitea.auth_env | type) == "string"' "$WORK_ITEM_TRACKER_BINDING" >/dev/null
  rc=$?
  cb_teardown
  exit $rc
)
assert_eq "cb_setup writes a well-formed gitea binding" "0" "$?"

[[ $FAILED -eq 0 ]] || exit 1
