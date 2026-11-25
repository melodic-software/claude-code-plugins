#!/usr/bin/env bash
# test-scope: plugins/work-items/tools/work-item-tracker/adapters/* docs/conventions/source-control.yaml plugins/work-items/tools/work-item-tracker/seeds/*/capabilities.json plugins/work-items/tools/work-item-tracker/seeds/*/adapter-spec.json
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$SCRIPT_DIR/generate-adapter.sh"
SEAM="$SCRIPT_DIR/../../../tools/work-item-tracker"
# shellcheck source=../../../tools/work-item-tracker/tests/lib.sh
source "$SEAM/tests/lib.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not available"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
OUT="$FIX/out"
mkdir -p "$OUT"

BASE_SPEC='{
  "spec_version": "1.0",
  "provider": "acmetracker",
  "display_name": "Acme Tracker",
  "api": {
    "base_path": "/api/v1",
    "host_suffix": ".acme.example",
    "auth_scheme": "bearer",
    "scope_pattern": "^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$",
    "sample_scope": "acme/webapp"
  },
  "verbs": {
    "create-item": true, "get-item": true, "claim": false, "renew-lease": false,
    "release": false,
    "reclaim": false, "link-blocks": false, "add-sub-item": false,
    "list-items": true, "list-sub-items": false, "label-provenance": false,
    "set-fields": false, "get-field-options": false, "get-statuses": false,
    "change-link": true, "add-recurrence": false, "capabilities": true
  },
  "features": { "cross_repo_edges": false, "sub_items": false, "leases": false, "labels": true },
  "limits": { "sub_items_per_parent": 0, "sub_item_depth": 0, "dependencies_per_type": 0, "list_items_max": 1000 },
  "change_link": { "branch_pattern": "^[a-z]+/([0-9]+)-" },
  "deferrals": []
}'

gen() {
  local spec="$1"
  shift
  printf '%s' "$spec" >"$FIX/spec.json"
  local root
  root="$(mktemp -d "$FIX/root.XXXXXX")"
  printf '%s' "$root" >"$FIX/last_root"
  bash "$S" --spec "$FIX/spec.json" --out-root "$root" "$@" >/dev/null 2>&1
  printf '%s' "$?"
}

last_root() { cat "$FIX/last_root"; }

gen_err() {
  printf '%s' "$1" >"$FIX/spec.json"
  local root
  root="$(mktemp -d "$FIX/root.XXXXXX")"
  printf '%s' "$root" >"$FIX/last_root"
  { bash "$S" --spec "$FIX/spec.json" --out-root "$root" >/dev/null; } 2>&1
}

with() { jq -c "$1" <<<"$BASE_SPEC"; }

assert_file() {
  if [[ -f "$2" ]]; then
    pass "$1"
  else
    fail "$1" "present" "missing"
  fi
}

bash "$S" --help >/dev/null 2>&1
assert_eq "--help → exit 0" "0" "$?"
help_out="$(bash "$S" --help 2>&1)"
assert_contains "--help documents --spec" "$help_out" "--spec"
assert_contains "--help documents --dry-run" "$help_out" "--dry-run"

bash "$S" >/dev/null 2>&1
assert_eq "no --spec → usage exit 2" "2" "$?"
bash "$S" --spec /nonexistent/spec.json >/dev/null 2>&1
assert_eq "missing spec file → usage exit 2" "2" "$?"
bash "$S" --spec "$S" --nope >/dev/null 2>&1
assert_eq "unknown argument → usage exit 2" "2" "$?"

bash "$S" --spec "$S" --out-root "" >/dev/null 2>&1
assert_eq "empty --out-root → usage exit 2" "2" "$?"
bash "$S" --spec "" --out-root "$OUT" >/dev/null 2>&1
assert_eq "empty --spec → usage exit 2" "2" "$?"

printf 'not json' >"$FIX/bad.json"
bash "$S" --spec "$FIX/bad.json" --out-root "$OUT" >/dev/null 2>&1
assert_eq "spec that is not JSON → exit 3" "3" "$?"

assert_eq "a coherent spec generates" "0" "$(gen "$BASE_SPEC")"
HAPPY_ROOT="$(last_root)"
A="$HAPPY_ROOT/tools/work-item-tracker/adapters/acmetracker"
B="$HAPPY_ROOT/tools/work-item-tracker/conformance/bindings"

for f in capabilities.json capabilities.sh capabilities.test.sh common.sh common.test.sh README.md \
  create-item.sh get-item.sh list-items.sh change-link.sh; do
  assert_file "generated $f" "$A/$f"
done
assert_file "generated the conformance binding" "$B/acmetracker.sh"

for f in claim.sh renew-lease.sh release.sh reclaim.sh link-blocks.sh add-sub-item.sh list-sub-items.sh; do
  if [[ -e "$A/$f" ]]; then
    fail "declared-false verb $f not generated" "absent" "present"
  else
    pass "declared-false verb $f not generated"
  fi
done

assert_unrendered() {
  local label="$1" dir="$2" binding="$3" leaked=""
  local f
  for f in "$dir"/* "$binding"; do
    [[ -f "$f" ]] || continue
    grep -q '@@' "$f" && leaked+=" $(basename "$f")"
  done
  if [[ -z "$leaked" ]]; then
    pass "$label"
  else
    fail "$label" "no @@placeholder@@ left" "leaked in:$leaked"
  fi
}
assert_unrendered "no placeholder survives rendering (vendor-suffix)" "$A" "$B/acmetracker.sh"

rc="$(gen "$(with '.api.host_suffix = "" | .api.sample_host = "git.example.com"')")"
assert_eq "self-hosted spec generates" "0" "$rc"
SELF_ROOT="$(last_root)"
assert_unrendered "no placeholder survives rendering (self-hosted)" \
  "$SELF_ROOT/tools/work-item-tracker/adapters/acmetracker" \
  "$SELF_ROOT/tools/work-item-tracker/conformance/bindings/acmetracker.sh"
assert_contains "self-hosted README names the provider in the pin posture" \
  "$(cat "$SELF_ROOT/tools/work-item-tracker/adapters/acmetracker/README.md")" \
  "Acme Tracker is self-hosted"

assert_eq "manifest provider" "acmetracker" "$(jq -r '.provider' "$A/capabilities.json")"
assert_eq "manifest keeps a declared-true verb" "true" "$(jq -r '.verbs["get-item"]' "$A/capabilities.json")"
assert_eq "manifest keeps a declared-false verb" "false" "$(jq -r '.verbs.claim' "$A/capabilities.json")"
assert_eq "manifest carries limits" "1000" "$(jq -r '.limits.list_items_max' "$A/capabilities.json")"
assert_eq "manifest carries the branch grammar" "^[a-z]+/([0-9]+)-" "$(jq -r '.change_link.branch_pattern' "$A/capabilities.json")"

assert_contains "generated globals carry the upper-cased provider" \
  "$(cat "$A/common.sh")" "WIT_ACMETRACKER_"

SEAM_VERSION="$(bash -c 'source "$1/lib/json.sh"; printf "%s" "$WIT_SCHEMA_VERSION"' _ "$SEAM")"
assert_eq "manifest stamps the seam's contract version" "$SEAM_VERSION" \
  "$(jq -r '.schema_version' "$A/capabilities.json")"

FAKE_SEAM="$FIX/fakeseam"
mkdir -p "$FAKE_SEAM/lib"
cp "$SEAM/lib/id.sh" "$FAKE_SEAM/lib/id.sh"
sed 's/^readonly WIT_SCHEMA_VERSION=.*/readonly WIT_SCHEMA_VERSION="9.9"/' \
  "$SEAM/lib/json.sh" >"$FAKE_SEAM/lib/json.sh"
FAKE_ROOT="$(mktemp -d "$FIX/root.XXXXXX")"
printf '%s' "$BASE_SPEC" >"$FIX/spec.json"
WIT_SEAM_DIR="$FAKE_SEAM" bash "$S" --spec "$FIX/spec.json" --out-root "$FAKE_ROOT" >/dev/null 2>&1
assert_eq "manifest follows the seam it was generated against" "9.9" \
  "$(jq -r '.schema_version' "$FAKE_ROOT/tools/work-item-tracker/adapters/acmetracker/capabilities.json")"

printf 'EDITED BY THE CONSUMER\n' >"$A/common.sh"
printf '%s' "$BASE_SPEC" >"$FIX/spec.json"
bash "$S" --spec "$FIX/spec.json" --out-root "$HAPPY_ROOT" >/dev/null 2>&1
assert_eq "re-run without --force still exits 0" "0" "$?"
assert_eq "re-run without --force keeps consumer edits" "EDITED BY THE CONSUMER" "$(cat "$A/common.sh")"
skip_msg="$({ bash "$S" --spec "$FIX/spec.json" --out-root "$HAPPY_ROOT" >/dev/null; } 2>&1)"
assert_contains "re-run names what it kept" "$skip_msg" "re-run with --force"

bash "$S" --spec "$FIX/spec.json" --out-root "$HAPPY_ROOT" --force >/dev/null 2>&1
if [[ "$(cat "$A/common.sh")" == "EDITED BY THE CONSUMER" ]]; then
  fail "--force overwrites" "regenerated" "kept"
else
  pass "--force overwrites"
fi

DRY_ROOT="$(mktemp -d "$FIX/root.XXXXXX")"
dry_out="$(bash "$S" --spec "$FIX/spec.json" --out-root "$DRY_ROOT" --dry-run 2>/dev/null)"
assert_contains "--dry-run says it would write" "$dry_out" "Would write"
if [[ -e "$DRY_ROOT/tools" ]]; then
  fail "--dry-run writes nothing" "no files" "files created"
else
  pass "--dry-run writes nothing"
fi

assert_eq "wrong spec_version → exit 3" "3" "$(gen "$(with '.spec_version = "2.0"')")"
assert_eq "missing display_name → exit 3" "3" "$(gen "$(with 'del(.display_name)')")"

assert_eq "display_name with an apostrophe → exit 3" "3" \
  "$(gen "$(with '.display_name = "Bobs'\'' Tracker"')")"
# shellcheck disable=SC2016  # the payload must reach the generator UNEXPANDED
assert_eq "display_name with command substitution → exit 3" "3" \
  "$(gen "$(with '.display_name = "X$(id)"')")"
assert_eq "display_name with a newline → exit 3" "3" \
  "$(gen "$(with '.display_name = "Acme\nTracker"')")"
# shellcheck disable=SC2016  # same reason as the case above
assert_eq "display_name with a backtick → exit 3" "3" \
  "$(gen "$(with '.display_name = "Acme `id`"')")"
assert_eq "a slashed display_name still generates" "0" \
  "$(gen "$(with '.display_name = "Gitea/Forgejo"')")"

for bad in '"Acme"' '"1acme"' '"acme_tracker"' '"../escape"' '"acme/tracker"' '""'; do
  assert_eq "provider $bad refused → exit 3" "3" "$(gen "$(with ".provider = $bad")")"
done

assert_eq "bad base_path → exit 3" "3" "$(gen "$(with '.api.base_path = "/api v1"')")"
assert_eq "base_path may be empty" "0" "$(gen "$(with '.api.base_path = ""')")"
assert_eq "host_suffix without a leading dot → exit 3" "3" "$(gen "$(with '.api.host_suffix = "acme.example"')")"
assert_eq "host_suffix may be empty (self-hosted)" "0" \
  "$(gen "$(with '.api.host_suffix = "" | .api.sample_host = "git.example.com"')")"
assert_eq "unknown auth_scheme → exit 3" "3" "$(gen "$(with '.api.auth_scheme = "oauth"')")"
for scheme in bearer token basic raw; do
  assert_eq "auth_scheme $scheme accepted" "0" "$(gen "$(with ".api.auth_scheme = \"$scheme\"")")"
done

assert_eq "unanchored scope_pattern → exit 3" "3" "$(gen "$(with '.api.scope_pattern = "[a-z]+"')")"
assert_eq "half-anchored scope_pattern → exit 3" "3" "$(gen "$(with '.api.scope_pattern = "^[a-z]+"')")"
anchor_err="$(gen_err "$(with '.api.scope_pattern = "[a-z]+"')")"
assert_contains "unanchored pattern names the risk" "$anchor_err" "conforming prefix"

assert_eq "single-quoted scope_pattern → exit 3" "3" \
  "$(gen "$(with '.api.scope_pattern = "^[A-Za-z0-9'\''][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"')")"
if [[ -d "$(last_root)/tools/work-item-tracker/adapters/acmetracker" ]]; then
  fail "a refused spec writes no adapter tree" "no adapter directory" "a directory of files"
else
  pass "a refused spec writes no adapter tree"
fi

assert_eq "sample_scope violating its own pattern → exit 3" "3" \
  "$(gen "$(with '.api.sample_scope = "no-slash-here"')")"

SCOPE_ANY='.api.scope_pattern = "^.*$"'
assert_eq "sample_scope with a double quote → exit 3" "3" \
  "$(gen "$(with "$SCOPE_ANY | .api.sample_scope = \"acme/web\\\"x\" | .api.sample_id = \"acmetracker:acme/webapp#12\"")")"
# shellcheck disable=SC2016  # the payload must reach the generator UNEXPANDED
assert_eq "sample_scope with command substitution → exit 3" "3" \
  "$(gen "$(with "$SCOPE_ANY"' | .api.sample_scope = "acme/webapp\"; $(id); echo \"x" | .api.sample_id = "acmetracker:acme/webapp#12"')")"
assert_eq "sample_scope with a newline → exit 3" "3" \
  "$(gen "$(with "$SCOPE_ANY"' | .api.sample_scope = "acme/webapp\nid" | .api.sample_id = "acmetracker:acme/webapp#12"')")"
# shellcheck disable=SC2016  # same reason: the backticks are the payload under test
assert_eq "sample_scope with a backtick → exit 3" "3" \
  "$(gen "$(with "$SCOPE_ANY"' | .api.sample_scope = "acme/`id`" | .api.sample_id = "acmetracker:acme/webapp#12"')")"
assert_eq "sample_scope with a single quote → exit 3" "3" \
  "$(gen "$(with "$SCOPE_ANY"' | .api.sample_scope = "acme/web'\''x" | .api.sample_id = "acmetracker:acme/webapp#12"')")"
assert_eq "an owner/repo sample_scope still generates" "0" \
  "$(gen "$(with '.api.sample_scope = "acme/webapp"')")"
assert_eq "a linear-shaped sample_scope still generates" "0" \
  "$(gen "$(with '.api.scope_pattern = "^[a-z0-9][a-z0-9-]*/[A-Z][A-Z0-9]*$" | .api.sample_scope = "acme/ENG"')")"
assert_eq "a bare project-key sample_scope still generates" "0" \
  "$(gen "$(with '.api.scope_pattern = "^[A-Za-z][A-Za-z0-9_]*$" | .api.sample_scope = "SW2"')")"
assert_eq "a dotted sample_scope still generates" "0" \
  "$(gen "$(with '.api.sample_scope = "acme.co/web_app-2"')")"
scope_err="$(gen_err "$(with "$SCOPE_ANY"' | .api.sample_scope = "acme/web\"x" | .api.sample_id = "acmetracker:acme/webapp#12"')")"
assert_contains "the sample_scope refusal names the executing context" "$scope_err" "would execute"

assert_eq "sample_host not a bare hostname → exit 3" "3" \
  "$(gen "$(with '.api.sample_host = "https://x.acme.example"')")"
assert_eq "sample_host outside host_suffix → exit 3" "3" \
  "$(gen "$(with '.api.sample_host = "x.elsewhere.example"')")"
assert_eq "auth_env_example that is not an env name → exit 3" "3" \
  "$(gen "$(with '.api.auth_env_example = "not-a-name"')")"

assert_eq "malformed sample_id → exit 3" "3" "$(gen "$(with '.api.sample_id = "acmetracker:acme#1"')")"
assert_eq "sample_id naming another provider → exit 3" "3" \
  "$(gen "$(with '.api.sample_id = "github:acme/webapp#1"')")"
assert_eq "explicit well-formed sample_id accepted" "0" \
  "$(gen "$(with '.api.sample_id = "acmetracker:acme/webapp#7"')")"

assert_eq "spec containing @@ → exit 3" "3" "$(gen "$(with '.display_name = "Acme @@PROVIDER@@"')")"

assert_eq "missing verb key → exit 3" "3" "$(gen "$(with 'del(.verbs["get-item"])')")"
assert_eq "non-boolean verb → exit 3" "3" "$(gen "$(with '.verbs["get-item"] = "yes"')")"
assert_eq "verb key outside the adapter surface → exit 3" "3" \
  "$(gen "$(with '.verbs["list-frontier"] = true')")"
extra_err="$(gen_err "$(with '.verbs["list-frontier"] = true')")"
assert_contains "extra verb key is named" "$extra_err" "list-frontier"
assert_eq "capabilities declared false → exit 3" "3" "$(gen "$(with '.verbs.capabilities = false')")"
assert_eq "missing feature key → exit 3" "3" "$(gen "$(with 'del(.features.leases)')")"
assert_eq "missing limit key → exit 3" "3" "$(gen "$(with 'del(.limits.list_items_max)')")"
assert_eq "negative limit → exit 3" "3" "$(gen "$(with '.limits.list_items_max = -1')")"
assert_eq "fractional limit → exit 3" "3" "$(gen "$(with '.limits.list_items_max = 1.5')")"
assert_eq "non-numeric limit → exit 3" "3" "$(gen "$(with '.limits.list_items_max = "lots"')")"

assert_eq "null limit on a supported capability is accepted" "0" \
  "$(gen "$(with '.verbs["link-blocks"] = true | .limits.dependencies_per_type = null')")"
assert_eq "null limit survives into the manifest" "null" \
  "$(jq -r '.limits.dependencies_per_type' "$(last_root)/tools/work-item-tracker/adapters/acmetracker/capabilities.json")"
assert_eq "0 on a supported capability is still refused" "3" \
  "$(gen "$(with '.verbs["link-blocks"] = true | .limits.dependencies_per_type = 0')")"
assert_eq "a ceiling on an unsupported capability is refused" "3" \
  "$(gen "$(with '.verbs["link-blocks"] = false | .limits.dependencies_per_type = null')")"
assert_eq "deferrals not an array of strings → exit 3" "3" "$(gen "$(with '.deferrals = [1,2]')")"

assert_eq "claim=true with leases=false → exit 3" "3" "$(gen "$(with '.verbs.claim = true')")"
assert_eq "leases=true without the three lease verbs → exit 3" "3" \
  "$(gen "$(with '.features.leases = true')")"
assert_eq "the full lease set is coherent" "0" \
  "$(gen "$(with '.features.leases = true | .verbs.claim = true | .verbs["renew-lease"] = true | .verbs.reclaim = true')")"
lease_err="$(gen_err "$(with '.verbs.claim = true')")"
assert_contains "lease incoherence explains itself" "$lease_err" "features.leases"

LEASES_NO_RELEASE='.features.leases = true | .verbs.claim = true | .verbs["renew-lease"] = true | .verbs.reclaim = true'
assert_eq "release=true with leases=false → exit 3" "3" "$(gen "$(with '.verbs.release = true')")"
release_err="$(gen_err "$(with '.verbs.release = true')")"
assert_contains "release incoherence names the verb" "$release_err" 'verbs["release"]=true but features.leases=false'
assert_eq "a spec missing the release key → exit 3" "3" "$(gen "$(with 'del(.verbs.release)')")"
assert_eq "release=true with leases=true is coherent" "0" \
  "$(gen "$(with "$LEASES_NO_RELEASE"' | .verbs.release = true')")"
assert_file "release=true emits a release.sh scaffold" \
  "$(last_root)/tools/work-item-tracker/adapters/acmetracker/release.sh"
assert_eq "release=false with leases=true generates" "0" "$(gen "$(with "$LEASES_NO_RELEASE")")"
LEASES_NO_RELEASE_A="$(last_root)/tools/work-item-tracker/adapters/acmetracker"
assert_eq "release=false survives into the manifest" "false" "$(jq -r '.verbs.release' "$LEASES_NO_RELEASE_A/capabilities.json")"
assert_eq "release=false emits no release.sh" "absent" \
  "$([[ -e "$LEASES_NO_RELEASE_A/release.sh" ]] && echo present || echo absent)"
assert_contains "the generated capabilities test checks release" \
  "$(cat "$LEASES_NO_RELEASE_A/capabilities.test.sh")" " release "

assert_eq "sub-item verb with sub_items=false → exit 3" "3" \
  "$(gen "$(with '.verbs["list-sub-items"] = true')")"
assert_eq "sub_items=false with a non-zero ceiling → exit 3" "3" \
  "$(gen "$(with '.limits.sub_items_per_parent = 100')")"
assert_eq "sub_items=true with a zero ceiling → exit 3" "3" \
  "$(gen "$(with '.features.sub_items = true | .verbs["list-sub-items"] = true | .verbs["add-sub-item"] = true')")"
assert_eq "the full sub-item set is coherent" "0" \
  "$(gen "$(with '.features.sub_items = true | .verbs["list-sub-items"] = true | .verbs["add-sub-item"] = true | .limits.sub_items_per_parent = 100 | .limits.sub_item_depth = 8')")"

assert_eq "list-items=true with a zero ceiling → exit 3" "3" \
  "$(gen "$(with '.limits.list_items_max = 0')")"
assert_eq "list-items=false with a non-zero ceiling → exit 3" "3" \
  "$(gen "$(with '.verbs["list-items"] = false')")"
assert_eq "consume-only (no list-items, zero ceiling) is coherent" "0" \
  "$(gen "$(with '.verbs["list-items"] = false | .limits.list_items_max = 0')")"
assert_eq "link-blocks=true with zero dependency ceiling → exit 3" "3" \
  "$(gen "$(with '.verbs["link-blocks"] = true')")"

gen_adapter() {
  local rc
  GEN_ADAPTER=""
  rc="$(gen "$2")"
  if [[ "$rc" != "0" ]]; then
    fail "$1 (generation)" "0" "$rc"
    return
  fi
  GEN_ADAPTER="$(last_root)/tools/work-item-tracker/adapters/acmetracker"
}

run_generated_suite() {
  gen_adapter "$1" "$2"
  [[ -n "$GEN_ADAPTER" ]] || return
  WIT_SEAM_LIB_DIR="$SEAM/lib" WIT_SEAM_TESTS_DIR="$SEAM/tests" \
    bash "$GEN_ADAPTER/common.test.sh" >/dev/null 2>&1
  assert_eq "$1" "0" "$?"
}

run_capabilities_suite() {
  gen_adapter "$1" "$2"
  [[ -n "$GEN_ADAPTER" ]] || return
  WIT_SEAM_TESTS_DIR="$SEAM/tests" bash "$GEN_ADAPTER/capabilities.test.sh" >/dev/null 2>&1
  assert_eq "$1" "0" "$?"
}
run_capabilities_suite "generated capabilities suite passes" "$BASE_SPEC"

rc="$(gen "$BASE_SPEC")"
DRIFT_A="$(last_root)/tools/work-item-tracker/adapters/acmetracker"
jq -c '.verbs["get-item"] = false' "$DRIFT_A/capabilities.json" >"$DRIFT_A/capabilities.json.tmp"
mv "$DRIFT_A/capabilities.json.tmp" "$DRIFT_A/capabilities.json"
WIT_SEAM_TESTS_DIR="$SEAM/tests" bash "$DRIFT_A/capabilities.test.sh" >/dev/null 2>&1
assert_eq "capabilities suite catches a manifest/filesystem disagreement" "1" "$?"

run_generated_suite "generated guards pass (bearer, vendor-suffix)" "$BASE_SPEC"
run_generated_suite "generated guards pass (token, self-hosted)" \
  "$(with '.api.auth_scheme = "token" | .api.host_suffix = "" | .api.sample_host = "git.example.com"')"
run_generated_suite "generated guards pass (basic auth)" \
  "$(with '.api.auth_scheme = "basic"')"

rc="$(gen "$(with '.api.auth_scheme = "basic"')")"
assert_eq "basic-auth spec generates" "0" "$rc"
BASIC_A="$(last_root)/tools/work-item-tracker/adapters/acmetracker"
assert_contains "basic auth requires an identity key" "$(cat "$BASIC_A/common.sh")" "auth_user"
assert_contains "basic auth documents the identity key" "$(cat "$BASIC_A/README.md")" "auth_user"

rc="$(gen "$(with '.features.leases = true | .verbs.claim = true | .verbs["renew-lease"] = true | .verbs.release = true | .verbs.reclaim = true | .features.sub_items = true | .verbs["list-sub-items"] = true | .verbs["add-sub-item"] = true | .limits.sub_items_per_parent = 100 | .limits.sub_item_depth = 8 | .verbs["link-blocks"] = true | .limits.dependencies_per_type = 50')")"
assert_eq "full-surface spec generates" "0" "$rc"
FULL_ROOT="$(last_root)"
FULL_A="$FULL_ROOT/tools/work-item-tracker/adapters/acmetracker"
FULL_B="$FULL_ROOT/tools/work-item-tracker/conformance/bindings/acmetracker.sh"

for v in create-item get-item claim renew-lease release reclaim link-blocks add-sub-item list-items list-sub-items; do
  assert_file "full surface emits $v.sh" "$FULL_A/$v.sh"
done

SC_RC="$(bash "$SCRIPT_DIR/../../../../../lib/org-standards.sh" dir --root "$SCRIPT_DIR/../../../../.." 2>/dev/null)/.shellcheckrc"
if ! command -v shellcheck >/dev/null 2>&1; then
  printf 'SKIP: shellcheck not available — generated-shell lint case not run\n' >&2
elif [[ ! -f "$SC_RC" && -n "${CI:-}${STANDARDS_DIR:-}" ]]; then
  assert_eq "the standards org layer's .shellcheckrc is readable where CI or STANDARDS_DIR says it must be" "readable" "unreadable"
elif [[ ! -f "$SC_RC" ]]; then
  printf 'SKIP: the standards org layer could not be read — generated-shell lint case not run\n' >&2
elif ! shellcheck --rcfile="$SC_RC" /dev/null >/dev/null 2>&1; then
  printf 'SKIP: shellcheck too old for --rcfile (needs 0.10.0+) — generated-shell lint case not run\n' >&2
else
  shellcheck --rcfile="$SC_RC" "$FULL_A"/*.sh "$FULL_B" >/dev/null 2>&1
  assert_eq "generated shell is ShellCheck-clean" "0" "$?"
fi

if command -v shfmt >/dev/null 2>&1; then
  shfmt -d -i 2 "$FULL_A"/*.sh "$FULL_B" >/dev/null 2>&1
  assert_eq "generated shell is shfmt-clean" "0" "$?"
else
  printf 'SKIP: shfmt not available — generated-shell format case not run\n' >&2
fi

verb() {
  WIT_SEAM_LIB_DIR="$SEAM/lib" bash "$@" >/dev/null 2>&1
}

verb "$FULL_A/get-item.sh" --help
assert_eq "scaffold --help → exit 0" "0" "$?"
verb "$FULL_A/get-item.sh"
assert_eq "scaffold with no id → exit 2" "2" "$?"
verb "$FULL_A/get-item.sh" "github:o/r#1"
assert_eq "scaffold rejects a foreign-provider id → exit 2" "2" "$?"
verb "$FULL_A/renew-lease.sh" "acmetracker:acme/webapp#1"
assert_eq "scaffold enforces a required flag → exit 2" "2" "$?"
verb "$FULL_A/release.sh" "acmetracker:acme/webapp#1"
assert_eq "release scaffold requires --lease-comment-id → exit 2" "2" "$?"
verb "$FULL_A/release.sh" "acmetracker:acme/webapp#1" --lease-comment-id abc
assert_eq "release scaffold rejects a non-numeric --lease-comment-id → exit 2" "2" "$?"
verb "$FULL_A/claim.sh" "acmetracker:acme/webapp#1" --ttl-minutes 60
assert_eq "claim scaffold rejects --ttl-minutes above 59 → exit 2" "2" "$?"
assert_contains "claim scaffold documents --ttl-minutes" "$(cat "$FULL_A/claim.sh")" "[--ttl-minutes <n>]"
assert_contains "release scaffold documents its usage" "$(cat "$FULL_A/release.sh")" "<id> --lease-comment-id <n>"

bash "$FULL_A/get-item.sh" "acmetracker:acme/webapp#1" >/dev/null 2>&1
assert_eq "no seam lib reachable → config exit 3" "3" "$?"
seam_err="$(bash "$FULL_A/get-item.sh" "acmetracker:acme/webapp#1" 2>&1 >/dev/null)"
assert_contains "missing seam lib names the remedy" "$seam_err" "WIT_SEAM_LIB_DIR"

ADAPTER_VERB_LIST="$(sed -n '/^readonly ADAPTER_VERBS=(/,/^)/p' "$S" | sed '1d;$d' | tr -s ' ' '\n' | sed '/^$/d' | sort)"
DISPATCH_VERB_LIST="$({
  awk '/case "\$verb" in/ { getline; print; exit }' "$SEAM/work-item-tracker.sh" | sed 's/).*//' | tr -d ' ' | tr '|' '\n'
  echo list-items
} | sort)"
assert_eq "the generator's verb set is non-empty" "true" "$([[ -n "$ADAPTER_VERB_LIST" ]] && echo true || echo false)"
assert_eq "ADAPTER_VERBS equals the dispatcher's verbs plus list-items" "$DISPATCH_VERB_LIST" "$ADAPTER_VERB_LIST"

for f in "$SEAM"/adapters/*/capabilities.json "$SEAM"/adapters/*/adapter-spec.json \
  "$SEAM"/seeds/*/capabilities.json "$SEAM"/seeds/*/adapter-spec.json; do
  [[ -f "$f" ]] || continue
  label="${f#"$SEAM"/}"
  assert_eq "$label carries exactly the adapter verbs" "$ADAPTER_VERB_LIST" \
    "$(jq -r '.verbs | keys[]' "$f" | tr -d '\r' | sort)"
  assert_eq "$label declares every verb as a boolean" "boolean" \
    "$(jq -r '[.verbs[] | type] | unique | join(",")' "$f" | tr -d '\r')"
done

[[ $FAILED -eq 0 ]] || exit 1
