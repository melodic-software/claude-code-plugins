#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# Contract tests for generate-adapter.sh — the deterministic half of
# /work-items:onboard-adapter.
#
# Spec-validation cases are the bulk: a refusal that silently stopped working would
# be invisible in the generated output, which would look fine and be wrong.
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

# A minimal spec every case starts from. Self-hosted shape (no vendor host suffix),
# consume-plus-create verb set, coherent by construction.
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
    "reclaim": false, "link-blocks": false, "add-sub-item": false,
    "list-items": true, "list-sub-items": false, "capabilities": true
  },
  "features": { "cross_repo_edges": false, "sub_items": false, "leases": false, "labels": true },
  "limits": { "sub_items_per_parent": 0, "sub_item_depth": 0, "dependencies_per_type": 0, "list_items_max": 1000 },
  "deferrals": []
}'

# gen <spec-json> [extra-args…] — write the spec to a temp file, run the generator
# into a FRESH out-root, and echo its exit code. A fresh root per case keeps
# no-clobber behavior from leaking between cases.
#
# gen runs in a $(…) subshell, so it hands the root back through a file: read it with
# last_root, never a variable gen appears to set.
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

# last_root — the out-root the most recent gen call generated into.
last_root() { cat "$FIX/last_root"; }

# gen_err <spec-json> — the same, echoing stderr for message assertions.
gen_err() {
  printf '%s' "$1" >"$FIX/spec.json"
  local root
  root="$(mktemp -d "$FIX/root.XXXXXX")"
  printf '%s' "$root" >"$FIX/last_root"
  { bash "$S" --spec "$FIX/spec.json" --out-root "$root" >/dev/null; } 2>&1
}

# with <jq-filter> — BASE_SPEC transformed.
with() { jq -c "$1" <<<"$BASE_SPEC"; }

# assert_file <label> <path> scores one case per file the generator must have written.
assert_file() {
  if [[ -f "$2" ]]; then
    pass "$1"
  else
    fail "$1" "present" "missing"
  fi
}

# --- argument handling ---

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

# An EMPTY --out-root must be refused, not treated as "not given", or a caller whose
# variable failed to expand generates into the current repository.
bash "$S" --spec "$S" --out-root "" >/dev/null 2>&1
assert_eq "empty --out-root → usage exit 2" "2" "$?"
bash "$S" --spec "" --out-root "$OUT" >/dev/null 2>&1
assert_eq "empty --spec → usage exit 2" "2" "$?"

printf 'not json' >"$FIX/bad.json"
bash "$S" --spec "$FIX/bad.json" --out-root "$OUT" >/dev/null 2>&1
assert_eq "spec that is not JSON → exit 3" "3" "$?"

# --- the happy path ---

assert_eq "a coherent spec generates" "0" "$(gen "$BASE_SPEC")"
HAPPY_ROOT="$(last_root)"
A="$HAPPY_ROOT/tools/work-item-tracker/adapters/acmetracker"
B="$HAPPY_ROOT/tools/work-item-tracker/conformance/bindings"

for f in capabilities.json capabilities.sh capabilities.test.sh common.sh common.test.sh README.md \
  create-item.sh get-item.sh list-items.sh; do
  assert_file "generated $f" "$A/$f"
done
# #2950 requires the conformance binding be generated alongside the adapter — without
# it the generated adapter cannot be conformance-verified at all.
assert_file "generated the conformance binding" "$B/acmetracker.sh"

# Declared-false verbs get NO script: the core capability gate answers them with
# exit 6 before any script would run, and shipping an inert file invites someone to
# fill it in without flipping the manifest.
for f in claim.sh renew-lease.sh reclaim.sh link-blocks.sh add-sub-item.sh list-sub-items.sh; do
  if [[ -e "$A/$f" ]]; then
    fail "declared-false verb $f not generated" "absent" "present"
  else
    pass "declared-false verb $f not generated"
  fi
done

# NO generated file may still contain a placeholder: render() walks its keys once, so an
# @@…@@ token inside a value leaks verbatim. Checked per value, across both host postures.
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
# The self-hosted README must say the pin is absent, in the provider's own name.
assert_contains "self-hosted README names the provider in the pin posture" \
  "$(cat "$SELF_ROOT/tools/work-item-tracker/adapters/acmetracker/README.md")" \
  "Acme Tracker is self-hosted"

# The manifest carries exactly the spec's declarations, plus the seam's version.
assert_eq "manifest provider" "acmetracker" "$(jq -r '.provider' "$A/capabilities.json")"
assert_eq "manifest keeps a declared-true verb" "true" "$(jq -r '.verbs["get-item"]' "$A/capabilities.json")"
assert_eq "manifest keeps a declared-false verb" "false" "$(jq -r '.verbs.claim' "$A/capabilities.json")"
assert_eq "manifest carries limits" "1000" "$(jq -r '.limits.list_items_max' "$A/capabilities.json")"

# The global/env spelling of the provider name is UPPER-cased. A skipped fold stays
# self-consistent across generated files, so nothing else here would notice it.
assert_contains "generated globals carry the upper-cased provider" \
  "$(cat "$A/common.sh")" "WIT_ACMETRACKER_"

# The version is the SEAM's, read from lib/json.sh, never the spec's; proven against a
# stand-in seam declaring 9.9.
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

# --- no-clobber, --force, --dry-run ---

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

# --- spec validation: identity and shape ---

assert_eq "wrong spec_version → exit 3" "3" "$(gen "$(with '.spec_version = "2.0"')")"
assert_eq "missing display_name → exit 3" "3" "$(gen "$(with 'del(.display_name)')")"

# One case per context display_name reaches literally: an apostrophe in a single-quoted
# printf, `$(…)` in a double-quoted ${VAR:?…}, a newline ending a `#` line.
assert_eq "display_name with an apostrophe → exit 3" "3" \
  "$(gen "$(with '.display_name = "Bobs'\'' Tracker"')")"
# shellcheck disable=SC2016  # the payload must reach the generator UNEXPANDED — an
# expanded $(id) would test the guard against this shell's output instead of against
# the command-substitution syntax, which is the whole point of the case.
assert_eq "display_name with command substitution → exit 3" "3" \
  "$(gen "$(with '.display_name = "X$(id)"')")"
assert_eq "display_name with a newline → exit 3" "3" \
  "$(gen "$(with '.display_name = "Acme\nTracker"')")"
# shellcheck disable=SC2016  # same reason as the case above: the backticks are the
# payload under test and must arrive at the generator as literal text.
assert_eq "display_name with a backtick → exit 3" "3" \
  "$(gen "$(with '.display_name = "Acme `id`"')")"
# Real names still pass — the guard must not be so tight it rejects the shipped ones.
assert_eq "a slashed display_name still generates" "0" \
  "$(gen "$(with '.display_name = "Gitea/Forgejo"')")"

# The provider name becomes a directory, a path segment, a function-name fragment and
# a jq key, so it is constrained once at the door.
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

# An unanchored scope pattern would accept a conforming PREFIX of a hostile value —
# exactly the hole the guard exists to close, so it is refused rather than repaired.
assert_eq "unanchored scope_pattern → exit 3" "3" "$(gen "$(with '.api.scope_pattern = "[a-z]+"')")"
assert_eq "half-anchored scope_pattern → exit 3" "3" "$(gen "$(with '.api.scope_pattern = "^[a-z]+"')")"
anchor_err="$(gen_err "$(with '.api.scope_pattern = "[a-z]+"')")"
assert_contains "unanchored pattern names the risk" "$anchor_err" "conforming prefix"

# quote_safe() is scope_pattern's only guard and must ABORT the run, not one $(render)
# subshell. The exit code and the empty-tree assertion are two halves of one case.
assert_eq "single-quoted scope_pattern → exit 3" "3" \
  "$(gen "$(with '.api.scope_pattern = "^[A-Za-z0-9'\''][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"')")"
if [[ -d "$(last_root)/tools/work-item-tracker/adapters/acmetracker" ]]; then
  fail "a refused spec writes no adapter tree" "no adapter directory" "a directory of files"
else
  pass "a refused spec writes no adapter tree"
fi

# The generated fixtures must satisfy the generated guards, or the adapter would fail
# its own tests the moment it was created.
assert_eq "sample_scope violating its own pattern → exit 3" "3" \
  "$(gen "$(with '.api.sample_scope = "no-slash-here"')")"

# sample_scope has its OWN charset because scope_pattern can permit anything (`^.*$`).
# Each case pins one escape route from the double-quoted argument it lands in.
SCOPE_ANY='.api.scope_pattern = "^.*$"'
assert_eq "sample_scope with a double quote → exit 3" "3" \
  "$(gen "$(with "$SCOPE_ANY | .api.sample_scope = \"acme/web\\\"x\" | .api.sample_id = \"acmetracker:acme/webapp#12\"")")"
# shellcheck disable=SC2016  # the payload must reach the generator UNEXPANDED — an
# expanded $(id) would test the guard against this shell's output instead of against
# the command-substitution syntax, which is the whole point of the case.
assert_eq "sample_scope with command substitution → exit 3" "3" \
  "$(gen "$(with "$SCOPE_ANY"' | .api.sample_scope = "acme/webapp\"; $(id); echo \"x" | .api.sample_id = "acmetracker:acme/webapp#12"')")"
assert_eq "sample_scope with a newline → exit 3" "3" \
  "$(gen "$(with "$SCOPE_ANY"' | .api.sample_scope = "acme/webapp\nid" | .api.sample_id = "acmetracker:acme/webapp#12"')")"
# shellcheck disable=SC2016  # same reason: the backticks are the payload under test
# and must arrive at the generator as literal text.
assert_eq "sample_scope with a backtick → exit 3" "3" \
  "$(gen "$(with "$SCOPE_ANY"' | .api.sample_scope = "acme/`id`" | .api.sample_id = "acmetracker:acme/webapp#12"')")"
assert_eq "sample_scope with a single quote → exit 3" "3" \
  "$(gen "$(with "$SCOPE_ANY"' | .api.sample_scope = "acme/web'\''x" | .api.sample_id = "acmetracker:acme/webapp#12"')")"
# …and the guard must not be tighter than the shapes the bundled providers actually
# use: gitea/github `owner/repo`, linear `<workspace>/<TEAMKEY>`, jira bare project key.
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

# sample_id must satisfy the seam's OWN id grammar (two path segments), which a
# host+scope composition does not always yield.
assert_eq "malformed sample_id → exit 3" "3" "$(gen "$(with '.api.sample_id = "acmetracker:acme#1"')")"
assert_eq "sample_id naming another provider → exit 3" "3" \
  "$(gen "$(with '.api.sample_id = "github:acme/webapp#1"')")"
assert_eq "explicit well-formed sample_id accepted" "0" \
  "$(gen "$(with '.api.sample_id = "acmetracker:acme/webapp#7"')")"

# The placeholder delimiter in a spec value would substitute into rendered output.
assert_eq "spec containing @@ → exit 3" "3" "$(gen "$(with '.display_name = "Acme @@PROVIDER@@"')")"

# --- spec validation: the verb/feature/limit surface ---

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

# `null` is a THIRD limit value, distinct from 0: supported with no provider ceiling,
# so a ceiling-free provider need not invent a number.
assert_eq "null limit on a supported capability is accepted" "0" \
  "$(gen "$(with '.verbs["link-blocks"] = true | .limits.dependencies_per_type = null')")"
assert_eq "null limit survives into the manifest" "null" \
  "$(jq -r '.limits.dependencies_per_type' "$(last_root)/tools/work-item-tracker/adapters/acmetracker/capabilities.json")"
assert_eq "0 on a supported capability is still refused" "3" \
  "$(gen "$(with '.verbs["link-blocks"] = true | .limits.dependencies_per_type = 0')")"
assert_eq "a ceiling on an unsupported capability is refused" "3" \
  "$(gen "$(with '.verbs["link-blocks"] = false | .limits.dependencies_per_type = null')")"
assert_eq "deferrals not an array of strings → exit 3" "3" "$(gen "$(with '.deferrals = [1,2]')")"

# --- coherence: the manifest is a promise the core routes on ---

assert_eq "claim=true with leases=false → exit 3" "3" "$(gen "$(with '.verbs.claim = true')")"
assert_eq "leases=true without the three lease verbs → exit 3" "3" \
  "$(gen "$(with '.features.leases = true')")"
assert_eq "the full lease set is coherent" "0" \
  "$(gen "$(with '.features.leases = true | .verbs.claim = true | .verbs["renew-lease"] = true | .verbs.reclaim = true')")"
lease_err="$(gen_err "$(with '.verbs.claim = true')")"
assert_contains "lease incoherence explains itself" "$lease_err" "features.leases"

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

# --- the generated security skeleton actually passes its own tests ---
# The guards are generated, so their proof is generated with them and runs here.

# gen_adapter <label> <spec>: generate <spec> and set GEN_ADAPTER to the generated
# adapter directory, or record a generation FAIL and clear GEN_ADAPTER. Written into a
# variable rather than echoed so `fail` stays in the caller's shell, where FAILED lives.
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

# The generated capabilities suite proves the manifest agrees with the FILESYSTEM — a
# verb declared true with no script behind it, or a script left behind for a verb since
# set to false, shows up in no other test.
run_capabilities_suite() {
  gen_adapter "$1" "$2"
  [[ -n "$GEN_ADAPTER" ]] || return
  WIT_SEAM_TESTS_DIR="$SEAM/tests" bash "$GEN_ADAPTER/capabilities.test.sh" >/dev/null 2>&1
  assert_eq "$1" "0" "$?"
}
run_capabilities_suite "generated capabilities suite passes" "$BASE_SPEC"

# And it CATCHES the disagreement it exists for: flipping a verb to false in the
# manifest while its script is still on disk must fail the suite.
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

# Basic auth adds a required identity key; its absence must be a config error, not a
# request sent with a half-built credential.
rc="$(gen "$(with '.api.auth_scheme = "basic"')")"
assert_eq "basic-auth spec generates" "0" "$rc"
BASIC_A="$(last_root)/tools/work-item-tracker/adapters/acmetracker"
assert_contains "basic auth requires an identity key" "$(cat "$BASIC_A/common.sh")" "auth_user"
assert_contains "basic auth documents the identity key" "$(cat "$BASIC_A/README.md")" "auth_user"

# --- generated shell is lint-clean and correctly formatted ---
# Generated code lands in a consumer's repo and goes through their CI; emitting code
# that trips the linters would make the generator a source of busywork.

rc="$(gen "$(with '.features.leases = true | .verbs.claim = true | .verbs["renew-lease"] = true | .verbs.reclaim = true | .features.sub_items = true | .verbs["list-sub-items"] = true | .verbs["add-sub-item"] = true | .limits.sub_items_per_parent = 100 | .limits.sub_item_depth = 8 | .verbs["link-blocks"] = true | .limits.dependencies_per_type = 50')")"
assert_eq "full-surface spec generates" "0" "$rc"
FULL_ROOT="$(last_root)"
FULL_A="$FULL_ROOT/tools/work-item-tracker/adapters/acmetracker"
FULL_B="$FULL_ROOT/tools/work-item-tracker/conformance/bindings/acmetracker.sh"

# Every verb of the adapter surface is emitted when all are declared.
for v in create-item get-item claim renew-lease reclaim link-blocks add-sub-item list-items list-sub-items; do
  assert_file "full surface emits $v.sh" "$FULL_A/$v.sh"
done

SC_RC="$SCRIPT_DIR/../../../../../.shellcheckrc"
# ShellCheck before 0.10.0 rejects `--rcfile` with exit 3 (bad syntax, not issues found),
# so probe whether THIS binary accepts the flag rather than trusting the exit status.
if ! command -v shellcheck >/dev/null 2>&1; then
  printf 'SKIP: shellcheck not available — generated-shell lint case not run\n' >&2
elif ! shellcheck --rcfile="$SC_RC" /dev/null >/dev/null 2>&1; then
  printf 'SKIP: shellcheck too old for --rcfile (needs 0.10.0+) — generated-shell lint case not run\n' >&2
else
  shellcheck --rcfile="$SC_RC" "$FULL_A"/*.sh "$FULL_B" >/dev/null 2>&1
  assert_eq "generated shell is ShellCheck-clean" "0" "$?"
fi

if command -v shfmt >/dev/null 2>&1; then
  # -i 2 matches the repo's .editorconfig for [*.{sh,bash}]; passed explicitly
  # because the generated tree under a temp root has no .editorconfig of its own.
  shfmt -d -i 2 "$FULL_A"/*.sh "$FULL_B" >/dev/null 2>&1
  assert_eq "generated shell is shfmt-clean" "0" "$?"
else
  printf 'SKIP: shfmt not available — generated-shell format case not run\n' >&2
fi

# An unmapped scaffold exits 1, never 6, which would launder unfinished work as a
# provider limitation.
#
# These cases call verbs directly, so they export WIT_SEAM_LIB_DIR as the dispatcher
# would; a generated adapter has no ../../lib to fall back to.
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

# Without the export and without a vendored seam, a verb fails as a SETUP error (3)
# naming the fix — not as a sourcing crash or a malformed record.
bash "$FULL_A/get-item.sh" "acmetracker:acme/webapp#1" >/dev/null 2>&1
assert_eq "no seam lib reachable → config exit 3" "3" "$?"
seam_err="$(bash "$FULL_A/get-item.sh" "acmetracker:acme/webapp#1" 2>&1 >/dev/null)"
assert_contains "missing seam lib names the remedy" "$seam_err" "WIT_SEAM_LIB_DIR"

[[ $FAILED -eq 0 ]] || exit 1
