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
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tests/lib.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "usage: run-conformance.sh --binding <name>  (runs the abstract seam conformance suite through the core CLI against the named adapter binding under bindings/<name>.sh)"
  exit 0
fi

binding_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --binding)
      [[ $# -ge 2 ]] || {
        echo "usage: run-conformance.sh --binding <name>" >&2
        exit 2
      }
      binding_name="$2"
      shift 2
      ;;
    *)
      echo "usage: run-conformance.sh --binding <name>" >&2
      exit 2
      ;;
  esac
done
[[ -n "$binding_name" ]] || {
  echo "usage: run-conformance.sh --binding <name>" >&2
  exit 2
}
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

verb_supported() {
  [[ "$(jq -r --arg v "$1" '.verbs[$v] // false' <<<"$CAPS")" == "true" ]]
}

FAKE_ID="$PROVIDER:conformance/x#1"

# --- unsupported verbs degrade explicitly (exit 6), never silently ---

for verb in create-item get-item claim renew-lease reclaim link-blocks add-sub-item; do
  if ! verb_supported "$verb"; then
    case "$verb" in
      create-item) wit_case "unsupported $verb → exit 6" 6 create-item --title x ;;
      get-item) wit_case "unsupported $verb → exit 6" 6 get-item "$FAKE_ID" ;;
      claim) wit_case "unsupported $verb → exit 6" 6 claim "$FAKE_ID" ;;
      renew-lease) wit_case "unsupported $verb → exit 6" 6 renew-lease "$FAKE_ID" --lease-comment-id 1 ;;
      reclaim) wit_case "unsupported $verb → exit 6" 6 reclaim "$FAKE_ID" ;;
      link-blocks) wit_case "unsupported $verb → exit 6" 6 link-blocks "$FAKE_ID" --blocked-by "$FAKE_ID" ;;
      add-sub-item) wit_case "unsupported $verb → exit 6" 6 add-sub-item "$FAKE_ID" --parent "$FAKE_ID" ;;
      *) ;;
    esac
  fi
done
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
