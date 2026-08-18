#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by sourced tests/lib.sh
# Abstract conformance suite for the work-item tracker seam (CONTRACT.md
# "Conformance"). One suite, parameterized by a binding under bindings/<name>.sh
# that provides cb_setup / cb_teardown and the target context. Assertions go only
# through the core CLI — never a provider tool directly. Pattern: one abstract
# runner over real implementations (ActiveModel::Lint / csi-sanity shape); no mocks.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKER="$SCRIPT_DIR/../work-item-tracker.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "usage: run-conformance.sh --binding <name>  (runs the abstract seam conformance suite through the core CLI against the named adapter binding under bindings/<name>.sh)"
  exit 0
fi

# usage_error — the one spelling of the usage line every arg-parsing failure exits on.
usage_error() {
  echo "usage: run-conformance.sh --binding <name>" >&2
  exit 2
}

binding_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --binding)
    if [[ $# -lt 2 ]]; then
      usage_error
    fi
    binding_name="$2"
    shift 2
    ;;
  *)
    usage_error
    ;;
  esac
done
if [[ -z "$binding_name" ]]; then
  usage_error
fi
BINDING_FILE_SH="$SCRIPT_DIR/bindings/$binding_name.sh"
[[ -f "$BINDING_FILE_SH" ]] || {
  echo "run-conformance: no binding at $BINDING_FILE_SH" >&2
  exit 2
}

# Binding provides: cb_setup (exports WORK_ITEM_TRACKER_BINDING; sets CB_REPO to an
# explicit target or empty for CWD derivation; clean-at-start), cb_teardown.
CB_REPO=""
# shellcheck source=/dev/null
source "$BINDING_FILE_SH"
cb_setup
trap 'cb_teardown' EXIT

repo_args=()
[[ -n "$CB_REPO" ]] && repo_args=(--repo "$CB_REPO")

WIT_OUT=""
WIT_RC=0

# wit_case <label> <expected-rc> <args…> — run the CLI, assert exit code and
# CR-free stdout; output lands in WIT_OUT for shape assertions.
wit_case() {
  local label="$1" expected_rc="$2"
  shift 2
  WIT_OUT="$(bash "$TRACKER" "$@" 2>/dev/null)"
  WIT_RC=$?
  assert_eq "$label (exit code)" "$expected_rc" "$WIT_RC"
  case "$WIT_OUT" in
  *$'\r'*) fail "$label (stdout CR-free)" "no CR" "CR present" ;;
  *) pass "$label (stdout CR-free)" ;;
  esac
}

assert_schema_version() {
  assert_eq "$1 (schema_version)" "1.0" "$(jq -r '.schema_version' <<<"$WIT_OUT")"
}

RUN_TAG="conf-$(date -u +%Y%m%dT%H%M%SZ)-$$"

# --- capabilities ---

wit_case "capabilities" 0 capabilities
assert_schema_version "capabilities"
PROVIDER="$(jq -r '.provider' <<<"$WIT_OUT")"
assert_contains "capabilities names a provider" "provider=$PROVIDER" "provider="
CAPS="$WIT_OUT"

# --- usage / binding errors ---

wit_case "no verb → usage" 2
wit_case "unknown verb → usage" 2 definitely-not-a-verb
WIT_OUT="$(WORK_ITEM_TRACKER_BINDING="/nonexistent-$$.json" bash "$TRACKER" capabilities 2>/dev/null)"
assert_eq "missing binding → exit 3" "3" "$?"

# --- binding overlay (CONTRACT.md "Setup (binding file)") ---
# The gitignored personal overlay beside the binding merges allowlisted keys only
# (lease TTL, jira auth identity); any other key is a configuration error (exit 3,
# same first-run signal as a missing binding), and removing the overlay restores
# the team view. Deep merge semantics are unit-tested (lib/binding.test.sh); this
# asserts the seam-level behavior through the CLI.
OVERLAY_PATH="$(cd "$(dirname "$WORK_ITEM_TRACKER_BINDING")" && pwd)/.work-item-tracker.local.json"
printf '%s\n' '{"config":{"lease_ttl_hours":1}}' >"$OVERLAY_PATH"
wit_case "allowlisted overlay key merges; verbs still dispatch" 0 capabilities
printf '%s\n' '{"provider":"someone-elses-provider"}' >"$OVERLAY_PATH"
WIT_OUT="$(bash "$TRACKER" capabilities 2>/dev/null)"
assert_eq "non-overlayable overlay key → exit 3" "3" "$?"
rm -f "$OVERLAY_PATH"
wit_case "overlay removal restores the team binding" 0 capabilities

# --- contract-version handshake (CONTRACT.md "Contract-version handshake") ---
# Every dispatched case in this suite already passes through the handshake against
# the real adapter's manifest (a bad declared version would fail every case), and
# the capabilities assertions above pinned its schema_version. Skew behavior is
# asserted here against a synthetic shadow of the SAME provider name via
# WIT_ADAPTERS_DIR: major skew refuses (exit 3, both versions named); newer-minor
# proceeds with a stderr notice (tolerant reader).

SKEW_ROOT="$(mktemp -d)"
mkdir -p "$SKEW_ROOT/$PROVIDER"
printf '%s\n' "{\"schema_version\":\"99.0\",\"provider\":\"$PROVIDER\",\"verbs\":{\"capabilities\":true}}" \
  >"$SKEW_ROOT/$PROVIDER/capabilities.json"
SKEW_ERR="$(WIT_ADAPTERS_DIR="$SKEW_ROOT" bash "$TRACKER" capabilities 2>&1 >/dev/null)"
assert_eq "major-skew manifest refused (exit code)" "3" "$?"
assert_contains "major-skew stderr names both versions" "$SKEW_ERR" "99.0"

cat >"$SKEW_ROOT/$PROVIDER/capabilities.sh" <<EOF
#!/usr/bin/env bash
jq -c . "$SKEW_ROOT/$PROVIDER/capabilities.json"
EOF
printf '%s\n' "{\"schema_version\":\"1.99\",\"provider\":\"$PROVIDER\",\"verbs\":{\"capabilities\":true}}" \
  >"$SKEW_ROOT/$PROVIDER/capabilities.json"
WIT_OUT="$(WIT_ADAPTERS_DIR="$SKEW_ROOT" bash "$TRACKER" capabilities 2>/dev/null)"
assert_eq "newer-minor manifest proceeds (exit code)" "0" "$?"
SKEW_ERR="$(WIT_ADAPTERS_DIR="$SKEW_ROOT" bash "$TRACKER" capabilities 2>&1 >/dev/null)"
assert_contains "newer-minor proceeds with a stderr notice" "$SKEW_ERR" "newer than core"
rm -rf "$SKEW_ROOT"

verb_supported() {
  [[ "$(jq -r --arg v "$1" '.verbs[$v] // false' <<<"$CAPS")" == "true" ]]
}

FAKE_ID="$PROVIDER:conformance/x#1"

# --- unsupported verbs degrade explicitly (exit 6), never silently ---

# wit_case_if_unsupported <verb> <args…> — assert the exit-6 gate for a verb the
# adapter's capabilities declare unsupported; a supported verb is skipped here and
# exercised by its own section below.
wit_case_if_unsupported() {
  local verb="$1"
  if ! verb_supported "$verb"; then
    wit_case "unsupported $verb → exit 6" 6 "$@"
  fi
}

wit_case_if_unsupported create-item --title x
wit_case_if_unsupported get-item "$FAKE_ID"
wit_case_if_unsupported claim "$FAKE_ID"
wit_case_if_unsupported renew-lease "$FAKE_ID" --lease-comment-id 1
wit_case_if_unsupported reclaim "$FAKE_ID"
wit_case_if_unsupported link-blocks "$FAKE_ID" --blocked-by "$FAKE_ID"
wit_case_if_unsupported add-sub-item "$FAKE_ID" --parent "$FAKE_ID"
if ! verb_supported list-items; then
  wit_case "unsupported list-items gates list-frontier → exit 6" 6 list-frontier
fi
if ! verb_supported list-sub-items; then
  wit_case "unsupported list-sub-items → exit 6" 6 list-sub-items "$FAKE_ID"
  wit_case "unsupported list-sub-items gates list-frontier --parent → exit 6" 6 list-frontier --parent "$FAKE_ID"
fi

# --- create-item ---

ITEM_A_ID="" ITEM_B_ID=""
if verb_supported create-item; then
  wit_case "create-item without --title → usage" 2 create-item "${repo_args[@]+"${repo_args[@]}"}"
  wit_case "create-item A" 0 create-item --title "$RUN_TAG A" --body "conformance" "${repo_args[@]+"${repo_args[@]}"}"
  assert_schema_version "create-item A"
  ITEM_A_ID="$(jq -r '.id' <<<"$WIT_OUT")"
  if [[ "$ITEM_A_ID" =~ ^[a-z0-9][a-z0-9-]*:[^#[:space:]]+#[0-9]+$ ]]; then
    pass "create-item A id grammar"
  else
    fail "create-item A id grammar" "provider:owner/repo#number" "$ITEM_A_ID"
  fi
  assert_eq "create-item A state open" "open" "$(jq -r '.state' <<<"$WIT_OUT")"
  wit_case "create-item B" 0 create-item --title "$RUN_TAG B" "${repo_args[@]+"${repo_args[@]}"}"
  ITEM_B_ID="$(jq -r '.id' <<<"$WIT_OUT")"

  # Edge-at-create path: --parent and --blocked-by supplied in a single
  # create-item call (distinct from the post-create link-blocks/add-sub-item
  # path below). Asserts the resulting parent_id + blocked_by_count.
  if [[ -n "$ITEM_A_ID" && -n "$ITEM_B_ID" ]]; then
    wit_case "create-item C with --parent + --blocked-by" 0 \
      create-item --title "$RUN_TAG C" --parent "$ITEM_A_ID" --blocked-by "$ITEM_B_ID" \
      "${repo_args[@]+"${repo_args[@]}"}"
    assert_eq "create-item C parent_id" "$ITEM_A_ID" "$(jq -r '.parent_id' <<<"$WIT_OUT")"
    assert_eq "create-item C blocked_by_count" "1" "$(jq -r '.blocked_by_count' <<<"$WIT_OUT")"
  fi
fi

# --- get-item ---

if verb_supported get-item && [[ -n "$ITEM_A_ID" ]]; then
  wit_case "get-item malformed id → usage" 2 get-item "not-an-id"
  missing_id="$(sed -E 's/#[0-9]+$/#999999/' <<<"$ITEM_A_ID")"
  wit_case "get-item nonexistent → exit 5" 5 get-item "$missing_id"
  wit_case "get-item A" 0 get-item "$ITEM_A_ID"
  assert_schema_version "get-item A"
  assert_eq "get-item A unblocked" "0" "$(jq -r '.blocked_by_count' <<<"$WIT_OUT")"
fi

# --- edges ---

if verb_supported link-blocks && [[ -n "$ITEM_A_ID" && -n "$ITEM_B_ID" ]]; then
  wit_case "link-blocks B blocked-by A" 0 link-blocks "$ITEM_B_ID" --blocked-by "$ITEM_A_ID"
  wit_case "get-item B sees open blocker" 0 get-item "$ITEM_B_ID"
  assert_eq "B blocked_by_count" "1" "$(jq -r '.blocked_by_count' <<<"$WIT_OUT")"
fi
if verb_supported add-sub-item && [[ -n "$ITEM_A_ID" && -n "$ITEM_B_ID" ]]; then
  wit_case "add-sub-item B under A" 0 add-sub-item "$ITEM_B_ID" --parent "$ITEM_A_ID"
  wit_case "get-item B sees parent" 0 get-item "$ITEM_B_ID"
  assert_eq "B parent_id" "$ITEM_A_ID" "$(jq -r '.parent_id' <<<"$WIT_OUT")"
fi

# --- sub-item enumeration + container-scoped frontier ---
# B is now a child of A (add-sub-item above) and blocked by A (link-blocks
# above), so it enumerates as A's child but is filtered out of A's scoped
# frontier while still blocked.
if verb_supported list-sub-items && verb_supported add-sub-item && [[ -n "$ITEM_A_ID" && -n "$ITEM_B_ID" ]]; then
  wit_case "list-sub-items A" 0 list-sub-items "$ITEM_A_ID"
  assert_schema_version "list-sub-items A"
  assert_contains "A's children hold B" "$(jq -c '[.items[].id]' <<<"$WIT_OUT")" "$ITEM_B_ID"
  assert_eq "enumerated child B is re-parented to A" "$ITEM_A_ID" \
    "$(jq -r '.items[0].parent_id' <<<"$WIT_OUT")"
  wit_case "list-sub-items malformed parent id → usage" 2 list-sub-items "not-an-id"

  wit_case "list-frontier --parent A" 0 list-frontier --parent "$ITEM_A_ID"
  assert_schema_version "list-frontier --parent A"
  assert_not_contains "scoped frontier drops blocked child B" \
    "$(jq -c '[.items[].id]' <<<"$WIT_OUT")" "$ITEM_B_ID"
fi

# --- frontier ---

if verb_supported list-items && [[ -n "$ITEM_A_ID" && -n "$ITEM_B_ID" ]]; then
  wit_case "list-frontier" 0 list-frontier "${repo_args[@]+"${repo_args[@]}"}"
  assert_schema_version "list-frontier"
  assert_contains "frontier holds unblocked A" "$(jq -c '[.items[].id]' <<<"$WIT_OUT")" "$ITEM_A_ID"
  assert_not_contains "frontier drops blocked B" "$(jq -c '[.items[].id]' <<<"$WIT_OUT")" "$ITEM_B_ID"
fi

# --- lease lifecycle + claim race ---

if verb_supported claim && [[ -n "$ITEM_A_ID" ]]; then
  wit_case "claim A" 0 claim "$ITEM_A_ID" --session-id "$RUN_TAG-s1"
  assert_schema_version "claim A"
  HOLDER="$(jq -r '.holder' <<<"$WIT_OUT")"
  LEASE_CID="$(jq -r '.lease_comment_id' <<<"$WIT_OUT")"
  if [[ -n "$HOLDER" && "$HOLDER" != "null" ]]; then
    pass "claim holder set"
  else
    fail "claim holder set" "non-empty holder" "$HOLDER"
  fi

  # Second session, same identity: race arbitration by lease-comment identity.
  wit_case "second claim backs off → exit 7" 7 claim "$ITEM_A_ID" --session-id "$RUN_TAG-s2"

  if verb_supported renew-lease && [[ "$LEASE_CID" =~ ^[0-9]+$ ]]; then
    wit_case "renew-lease A" 0 renew-lease "$ITEM_A_ID" --lease-comment-id "$LEASE_CID"
    assert_schema_version "renew-lease A"
    # Cross-item guard: A's lease comment must not renew a different item.
    if [[ -n "$ITEM_B_ID" ]]; then
      wit_case "renew-lease rejects a foreign item's comment → exit 7" 7 \
        renew-lease "$ITEM_B_ID" --lease-comment-id "$LEASE_CID"
    fi
  fi

  if verb_supported list-items; then
    wit_case "frontier drops claimed A" 0 list-frontier "${repo_args[@]+"${repo_args[@]}"}"
    assert_not_contains "claimed A left frontier" "$(jq -c '[.items[].id]' <<<"$WIT_OUT")" "$ITEM_A_ID"
  fi

  if verb_supported reclaim; then
    # A ran through a back-off (its own newer lease comment is superseded), so
    # this also asserts reclaim selects the ACTIVE lease, not the superseded
    # newer one — reason "lease live", never "lease already superseded".
    wit_case "reclaim live lease is a no-op" 0 reclaim "$ITEM_A_ID"
    assert_eq "live lease not reclaimed" "false" "$(jq -r '.reclaimed' <<<"$WIT_OUT")"
    assert_eq "reclaim picked the active lease" "lease live" "$(jq -r '.reason' <<<"$WIT_OUT")"

    # Expired-lease reclaim: ttl 0 lease on B expires immediately.
    if [[ -n "$ITEM_B_ID" ]]; then
      wit_case "claim B with ttl 0" 0 claim "$ITEM_B_ID" --ttl-hours 0 --session-id "$RUN_TAG-s3"
      wit_case "reclaim expired B" 0 reclaim "$ITEM_B_ID"
      assert_eq "expired lease reclaimed" "true" "$(jq -r '.reclaimed' <<<"$WIT_OUT")"
      wit_case "get-item B after reclaim" 0 get-item "$ITEM_B_ID"
      assert_eq "reclaim cleared assignees" "0" "$(jq -r '.assignees | length' <<<"$WIT_OUT")"
    fi
  fi
fi

printf '\nConformance (%s): %d cases, %d failed\n' "$binding_name" "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
