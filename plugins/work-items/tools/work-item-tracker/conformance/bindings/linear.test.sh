#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# shellcheck disable=SC2030,SC2031  # each guard case runs in its own ( ) so its env changes stay local — that isolation is the point, not an accident
# linear.sh is a sourceable conformance binding — assert it sources cleanly, exposes the
# cb_setup/cb_teardown contract, and refuses to run without an explicitly named
# throwaway target, all without touching the network.
#
# Like github's and gitea's, this file does NOT run the suite. The linear manifest
# declares the full verb surface, so the suite creates, claims, and closes real issues;
# it is an on-demand binding, and the live pass is recorded as deferred in the adapter's
# README rather than quietly skipped here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../tests/lib.sh"
CB_REPO=""
# shellcheck source=linear.sh
source "$SCRIPT_DIR/linear.sh"

for fn in cb_setup cb_teardown; do
  if declare -F "$fn" >/dev/null; then
    pass "linear binding exposes $fn"
  else
    fail "linear binding exposes $fn" "declared" "missing"
  fi
done

# No retained default for either half of the target. Conformance mutates real items, so
# a binding that fell back to some default host or scope could point a destructive suite
# at a workspace someone is actually working in. Both guards fire before any network
# call, so these cases stay offline.
if (
  unset WIT_CONFORMANCE_LINEAR_HOST
  export WIT_CONFORMANCE_LINEAR_SCOPE="throwaway/SBX"
  cb_setup
) 2>/dev/null; then
  fail "cb_setup requires an explicit host" "nonzero exit" "succeeded"
else
  pass "cb_setup requires an explicit host (no retained default)"
fi

if (
  export WIT_CONFORMANCE_LINEAR_HOST="api.linear.app"
  unset WIT_CONFORMANCE_LINEAR_SCOPE
  cb_setup
) 2>/dev/null; then
  fail "cb_setup requires an explicit scope" "nonzero exit" "succeeded"
else
  pass "cb_setup requires an explicit scope (no retained default)"
fi

# With both named, cb_setup writes a binding the seam can actually read — a shape error
# here would surface as an opaque exit 3 partway through a live run.
#
# cb_setup also runs the clean-at-start pass, which talks to Linear's own GraphQL API.
# `curl` is PATH-stubbed to answer one empty page so that path executes for real —
# offline, but not bypassed. Stubbing it rather than skipping the cleanup keeps this
# test honest about what cb_setup actually does now.
CB_STUB_DIR="$(mktemp -d)"
cat >"$CB_STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
# Drain the stdin config (the credential arrives that way) so the writer never sees EPIPE.
cat >/dev/null
printf '{"data":{"issues":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
STUB
chmod +x "$CB_STUB_DIR/curl"

(
  export PATH="$CB_STUB_DIR:$PATH"
  export WIT_LINEAR_API_KEY="throwaway-not-a-real-key"
  export WIT_CONFORMANCE_LINEAR_HOST="api.linear.app"
  export WIT_CONFORMANCE_LINEAR_SCOPE="throwaway/SBX"
  cb_setup
  jq -e '.provider == "linear"
    and .config.linear.host == "api.linear.app"
    and (.config.linear.scopes == ["throwaway/SBX"])
    and (.config.linear.auth_env | type) == "string"' "$WORK_ITEM_TRACKER_BINDING" >/dev/null
  rc=$?
  cb_teardown
  exit $rc
)
assert_eq "cb_setup writes a well-formed linear binding" "0" "$?"

# --- the clean-at-start pass actually archives what it finds -------------------
# A cleanup that quietly does nothing is the failure mode this replaced: the suite then
# asserts counts against a previous run's leftovers and flaps. So assert the archive
# mutation is really sent, not just that cb_setup exits 0.
CB_LOG="$CB_STUB_DIR/requests.log"
cat >"$CB_STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
body=""
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--data-binary" ]] && body="$2"
  shift
done
cat >/dev/null
printf '%s\n' "$body" >>"$CB_LOG"
if [[ "$body" == *issueArchive* ]]; then
  printf '{"data":{"issueArchive":{"success":true}}}'
elif [[ -f "$CB_LOG.served" ]]; then
  printf '{"data":{"issues":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
else
  : >"$CB_LOG.served"
  printf '{"data":{"issues":{"nodes":[{"id":"uuid-issue-alpha"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
fi
STUB
chmod +x "$CB_STUB_DIR/curl"

(
  export PATH="$CB_STUB_DIR:$PATH" CB_LOG
  export WIT_LINEAR_API_KEY="throwaway-not-a-real-key"
  export WIT_CONFORMANCE_LINEAR_HOST="api.linear.app"
  export WIT_CONFORMANCE_LINEAR_SCOPE="throwaway/SBX"
  cb_setup
  rc=$?
  cb_teardown
  exit $rc
) >/dev/null 2>&1
assert_eq "clean-at-start completes when the provider answers" "0" "$?"
assert_eq "…and archives the issue it found" "1" \
  "$(grep -c 'issueArchive' "$CB_LOG" 2>/dev/null || echo 0)"
# The scope is <workspace>/<TEAMKEY> but Linear's filter takes the TEAM KEY alone.
# Sending the whole scope would silently match nothing and "clean" an empty set, which
# looks exactly like a successful cleanup — so assert the split, not just its presence.
assert_eq "…filtering on the bare team key" "yes" \
  "$(grep -q '"t":"SBX"' "$CB_LOG" && echo yes || echo no)"
assert_eq "…and never sending the workspace-qualified scope as the key" "no" \
  "$(grep -q '"t":"throwaway/SBX"' "$CB_LOG" && echo yes || echo no)"

# --- a provider error is surfaced, never swallowed -----------------------------
# Returning success here would let the suite run against an unknown starting state.
cat >"$CB_STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf '{"errors":[{"message":"rate limited"}]}'
STUB
chmod +x "$CB_STUB_DIR/curl"

(
  export PATH="$CB_STUB_DIR:$PATH"
  export WIT_LINEAR_API_KEY="throwaway-not-a-real-key"
  export WIT_CONFORMANCE_LINEAR_HOST="api.linear.app"
  export WIT_CONFORMANCE_LINEAR_SCOPE="throwaway/SBX"
  cb_setup
) >/dev/null 2>&1
assert_eq "a provider error during clean-at-start fails loudly" "1" "$?"

rm -rf "$CB_STUB_DIR"

[[ $FAILED -eq 0 ]] || exit 1
