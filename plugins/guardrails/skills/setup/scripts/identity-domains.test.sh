#!/usr/bin/env bash
# Tests for identity-domains.sh: a machine-profile fixture in, block-cross-domain's
# map out, written only to a temp CLAUDE_PLUGIN_DATA and only with --confirm. The
# fixture's trees, owners and directories are placeholders under the suite's own
# temp tree; the written map is then read by the guard itself.
# test-scope: plugins/guardrails/hooks/block-cross-domain.sh plugins/guardrails/hooks/guardrails-test-helpers.sh
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/identity-domains.sh"
PLUGIN_DIR="$(cd "$SELF_DIR/../../.." && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../hooks/guardrails-test-helpers.sh
source "$PLUGIN_DIR/hooks/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_CROSS_DOMAIN_ENABLED GUARDRAILS_CROSS_DOMAIN_TRACE

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required for these tests" >&2
  exit 1
fi

case "${OSTYPE:-}" in
msys* | cygwin* | win32) OS_KEY=windows ;;
darwin*) OS_KEY=macos ;;
*) OS_KEY=linux ;;
esac
OS_FACT=$(uname -s)

# The checkout this suite runs in, so it can show the script left it alone.
REPO_ROOT=$(git -C "$PLUGIN_DIR" rev-parse --show-toplevel 2>/dev/null || true)
repo_state() { [[ -z "$REPO_ROOT" ]] || git -C "$REPO_ROOT" status --porcelain --untracked-files=all 2>/dev/null; }
REPO_BEFORE=$(repo_state)

ALPHA="$TEST_TMPDIR/trees/alpha"
BETA="$TEST_TMPDIR/trees/beta"
mkdir -p "$ALPHA/repo" "$BETA/repo" "$TEST_TMPDIR/run"

gh_set() { # <dir>
  MSYS_NO_PATHCONV=1 jq -nc --arg v "$1" '{key: "gh_config_dir", value: $v, verdict: "set", observed_by: "grep", mode: "observed", supplied_by: "tree environment (.envrc)"}'
}
GH_UNEXAMINED='{"key":"gh_config_dir","verdict":"default-unexamined","skipped_because":"the tree has no .envrc"}'

# profile <tree> <gh record> [<tree> <gh record> ...]: a machine-profile
# document holding those domains.
profile() {
  local args=() i=0
  while (($#)); do
    args+=(--arg "t$i" "$1" --argjson "g$i" "$2")
    shift 2
    i=$((i + 1))
  done
  MSYS_NO_PATHCONV=1 jq -n --arg os "$OS_FACT" "${args[@]}" '
    {machine: {facts: [{key: "os", value: $os, verdict: "set", observed_by: "uname -s", mode: "observed", supplied_by: "host"}]},
     domains: ([$ARGS.named | to_entries[] | select(.key | test("^t")) | .key[1:] as $i | .value as $t
       | {key: $t, value: {tree: $t, identity: {gh_config_dir: $ARGS.named["g" + $i]}, facts: [], options: []}}] | from_entries)}'
}

# run <profile file> [arg ...]: the script from a neutral directory; sets OUT,
# ERR and RC.
run() {
  local prof="$1"
  shift
  RC=0
  OUT=$(cd "$TEST_TMPDIR/run" && bash "$SCRIPT" --profile "$prof" "$@" 2>"$TEST_TMPDIR/err") || RC=$?
  ERR=$(<"$TEST_TMPDIR/err")
}

# --- Two domains from the profile -------------------------------------------
TWO="$TEST_TMPDIR/two.json"
profile "$ALPHA" "$(gh_set /placeholder/gh-alpha)" "$BETA" "$(gh_set /placeholder/gh-beta)" >"$TWO"
DATA="$TEST_TMPDIR/plugin-data"

run "$TWO"
assert_exit "no --data-dir: prints the map" 0 "$RC"
assert_eq "both domains are named after their trees" "alpha,beta" "$(jq -r '.domains | keys | join(",")' <<<"$OUT")"
assert_contains "the notes say owners and markers are left out" "$ERR" "left out"

run "$TWO" --data-dir "$DATA"
assert_exit "no --confirm: dry run" 0 "$RC"
assert_contains "the dry run says nothing was written" "$ERR" "dry run, nothing written"
assert_file_absent "the dry run writes no map" "$DATA/identity-domains.json"

run "$TWO" --data-dir "$DATA" --confirm
assert_exit "--confirm: writes the map" 0 "$RC"
MAP_FILE="$DATA/identity-domains.json"
if [[ -f "$MAP_FILE" ]]; then ok "the map is in the plugin data directory"; else bad "no map at $MAP_FILE"; fi
assert_eq "alpha's root is its tree under this host's key" "$ALPHA" "$(jq -r --arg o "$OS_KEY" '.domains.alpha.roots[$o][0]' <"$MAP_FILE")"
assert_eq "beta's root is its tree under this host's key" "$BETA" "$(jq -r --arg o "$OS_KEY" '.domains.beta.roots[$o][0]' <"$MAP_FILE")"
assert_eq "alpha's gh_config_dir is the profile's" "/placeholder/gh-alpha" "$(jq -r '.domains.alpha.gh_config_dir' <"$MAP_FILE")"
assert_eq "beta's gh_config_dir is the profile's" "/placeholder/gh-beta" "$(jq -r '.domains.beta.gh_config_dir' <"$MAP_FILE")"
assert_eq "nothing the profile lacks is invented" "gh_config_dir,roots" "$(jq -r '[.domains[] | keys[]] | unique | join(",")' <"$MAP_FILE")"
assert_eq "no top-level key but domains" "domains" "$(jq -r 'keys | join(",")' <"$MAP_FILE")"
assert_eq "the data directory holds the map alone" "identity-domains.json" "$(ls -A "$DATA")"

run "$TWO" --data-dir "$DATA" --confirm
assert_exit "a rerun with the same map" 0 "$RC"
assert_contains "a rerun reports the map unchanged" "$ERR" "unchanged"

# --- The guard reads the written map ------------------------------------------
GUARD_UNDER_TEST="$PLUGIN_DIR/hooks/block-cross-domain.sh"
guard_invoke --cwd "$ALPHA/repo" --command "ls $BETA/repo" -- "CLAUDE_PLUGIN_DATA=$DATA" GUARDRAILS_CROSS_DOMAIN_TRACE=1
assert_exit "the guard on the written map: exit 0" 0 "$GUARD_RC"
assert_absent "the guard finds the map well formed" "$GUARD_OUT" "malformed"
assert_contains "the guard compiles the map" "$GUARD_ERR" "trace map-compile"
assert_contains "a command naming beta's tree hits the prefilter" "$GUARD_ERR" "trace prefilter-hit"
rm -f "$DATA/identity-domains.cache"

# --- A different map there is kept unless --replace --------------------------
OTHER="$TEST_TMPDIR/other.json"
profile "$ALPHA" "$GH_UNEXAMINED" >"$OTHER"
run "$OTHER" --data-dir "$DATA"
assert_exit "a different map in place: the dry run refuses too" 1 "$RC"
run "$OTHER" --data-dir "$DATA" --confirm
assert_exit "a different map in place: refused" 1 "$RC"
assert_contains "the refusal names --replace" "$ERR" "--replace"
assert_eq "the map in place is kept" "alpha,beta" "$(jq -r '.domains | keys | join(",")' <"$MAP_FILE")"
run "$OTHER" --data-dir "$DATA" --confirm --replace
assert_exit "--replace: writes" 0 "$RC"
assert_eq "the replaced map holds the new domains" "alpha" "$(jq -r '.domains | keys | join(",")' <"$MAP_FILE")"
assert_eq "an unexamined gh directory is left out" "null" "$(jq -r '.domains.alpha.gh_config_dir' <"$MAP_FILE")"
assert_contains "the notes say why gh_config_dir is left out" "$ERR" "default-unexamined"

# --- Operator values ------------------------------------------------------------
run "$TWO" --owner alpha=alpha-org --marker alpha=alpha-org --az-config-dir beta=/placeholder/az-beta \
  --shared-exception "alpha:beta=$BETA/shared"
assert_exit "operator values: exit 0" 0 "$RC"
assert_eq "an owner lands in its domain" "alpha-org" "$(jq -r '.domains.alpha.owners[0]' <<<"$OUT")"
assert_eq "a marker lands in its domain" "alpha-org" "$(jq -r '.domains.alpha.identity_markers[0]' <<<"$OUT")"
assert_eq "an az directory lands in its domain" "/placeholder/az-beta" "$(jq -r '.domains.beta.az_config_dir' <<<"$OUT")"
assert_eq "a shared exception is a top-level entry naming its domains" "$BETA/shared|alpha|beta" \
  "$(jq -r '.shared_exceptions[0] | "\(.path)|\(.from | join(","))|\(.to)"' <<<"$OUT")"

# --- Shared exceptions ------------------------------------------------------------
THREE="$TEST_TMPDIR/three.json"
GAMMA="$TEST_TMPDIR/trees/gamma"
profile "$ALPHA" "$GH_UNEXAMINED" "$BETA" "$GH_UNEXAMINED" "$GAMMA" "$GH_UNEXAMINED" >"$THREE"
run "$THREE" --shared-exception "alpha,gamma:beta=$BETA/shared" --shared-exception "beta:alpha=$ALPHA"
assert_exit "two shared exceptions: exit 0" 0 "$RC"
assert_eq "an exception from two domains" "alpha,gamma" "$(jq -r '.shared_exceptions[0].from | join(",")' <<<"$OUT")"
assert_eq "an exception that is the tree itself" "$ALPHA" "$(jq -r '.shared_exceptions[1].path' <<<"$OUT")"
SHARED_DATA="$TEST_TMPDIR/shared-data"
run "$THREE" --shared-exception "alpha:beta=$BETA/shared" --data-dir "$SHARED_DATA" --confirm
assert_exit "a map with a shared exception: written" 0 "$RC"
guard_invoke --cwd "$ALPHA/repo" --command "ls $BETA/shared/x" -- "CLAUDE_PLUGIN_DATA=$SHARED_DATA"
assert_silent "the guard allows the written exception from its from domain" "$GUARD_OUT"
guard_invoke --cwd "$GAMMA/repo" --command "ls $BETA/shared/x" -- "CLAUDE_PLUGIN_DATA=$SHARED_DATA"
assert_contains "the guard denies it from a domain it does not list" "$GUARD_OUT" '"permissionDecision":"deny"'
OWNER_SHARED="alpha:beta=$TEST_TMPDIR/home/src/github.com/beta-org/shared"
RC=0
OUT=$(cd "$TEST_TMPDIR/run" && HOME="$TEST_TMPDIR/home" bash "$SCRIPT" --profile "$TWO" --owner beta=beta-org \
  --shared-exception "$OWNER_SHARED" 2>"$TEST_TMPDIR/err") || RC=$?
assert_exit "an exception below an owner directory of its to domain: exit 0" 0 "$RC"
RC=0
OUT=$(cd "$TEST_TMPDIR/run" && HOME="$TEST_TMPDIR/home" bash "$SCRIPT" --profile "$TWO" \
  --shared-exception "$OWNER_SHARED" 2>"$TEST_TMPDIR/err") || RC=$?
assert_exit "the same path with no owner for its to domain: refused" 1 "$RC"
# shared_refused <label> <value> <what the refusal says>
shared_refused() {
  run "$TWO" --shared-exception "$2"
  assert_exit "$1: refused" 1 "$RC"
  assert_contains "$1: the refusal says why" "$ERR" "$3"
}
shared_refused "an exception outside its to domain" "alpha:beta=$ALPHA/shared" "is not the tree of domain beta"
shared_refused "an exception beside its to domain's tree" "alpha:beta=${BETA}x/shared" "is not the tree of domain beta"
NESTED="$TEST_TMPDIR/nested.json"
profile "$ALPHA" "$GH_UNEXAMINED" "$BETA" "$GH_UNEXAMINED" "$BETA/inner" "$GH_UNEXAMINED" >"$NESTED"
run "$NESTED" --shared-exception "alpha:beta=$BETA/inner/shared"
assert_exit "an exception below a domain nested in its to: refused" 1 "$RC"
assert_contains "an exception below a domain nested in its to: the refusal says why" "$ERR" "outside every domain nested there"
shared_refused "an exception from its own to" "beta:beta=$BETA/shared" "FROM lists TO"
shared_refused "an exception to a domain the profile lacks" "alpha:gamma=$BETA/shared" "names domain gamma"
shared_refused "an exception from a domain the profile lacks" "gamma:beta=$BETA/shared" "names domain gamma"
shared_refused "an exception with no to" "alpha=$BETA/shared" "takes FROM[,FROM...]:TO=PATH"
shared_refused "an exception with an empty from" ":beta=$BETA/shared" "takes FROM[,FROM...]:TO=PATH"
run "$TWO" --shared-exception "$BETA/shared"
assert_exit "an exception with no NAME=: usage" 2 "$RC"
run "$TWO" --owner alpha=alpha-org
assert_contains "a domain missing values gets its own note" "$ERR" "domain beta: owners, identity_markers, az_config_dir not in the profile"
run "$TWO" --owner alpha=-n --marker beta=--args
assert_exit "values that start with -: exit 0" 0 "$RC"
assert_eq "a value that starts with - is kept as text" "-n" "$(jq -r '.domains.alpha.owners[0]' <<<"$OUT")"
assert_eq "a value that names a jq option is kept as text" "--args" "$(jq -r '.domains.beta.identity_markers[0]' <<<"$OUT")"
run "$TWO" --owner gamma=gamma-org
assert_exit "an owner for a domain the profile lacks: refused" 1 "$RC"
assert_contains "the refusal lists the domains" "$ERR" "alpha, beta"
run "$TWO" --owner alpha
assert_exit "an owner with no NAME=: usage" 2 "$RC"

# --- Trees the map cannot hold, and name clashes ------------------------------
CLASH="$TEST_TMPDIR/clash.json"
profile "$ALPHA" "$GH_UNEXAMINED" "$TEST_TMPDIR/other/alpha" "$GH_UNEXAMINED" \
  "relative/tree" "$GH_UNEXAMINED" "$TEST_TMPDIR/glob/*" "$GH_UNEXAMINED" >"$CLASH"
run "$CLASH"
assert_exit "skips and clashes: exit 0" 0 "$RC"
assert_eq "a clashing name gets a suffix" "alpha,alpha-2" "$(jq -r '.domains | keys | join(",")' <<<"$OUT")"
assert_contains "a relative tree is skipped with a note" "$ERR" "skipped tree relative/tree"
assert_contains "a wildcard tree is skipped with a note" "$ERR" "holds a wildcard"

NONE="$TEST_TMPDIR/none.json"
profile "relative/tree" "$GH_UNEXAMINED" >"$NONE"
run "$NONE" --data-dir "$TEST_TMPDIR/none-data" --confirm
assert_exit "no usable tree: refused" 1 "$RC"
assert_file_absent "no usable tree: nothing written" "$TEST_TMPDIR/none-data"

mkdir -p "$TEST_TMPDIR/dir-data/identity-domains.json"
run "$TWO" --data-dir "$TEST_TMPDIR/dir-data" --confirm --replace
assert_exit "a directory where the map goes: refused" 1 "$RC"
assert_eq "a directory where the map goes: nothing written into it" "" "$(ls -A "$TEST_TMPDIR/dir-data/identity-domains.json")"

printf 'not json\n' >"$TEST_TMPDIR/bad.json"
run "$TEST_TMPDIR/bad.json" --data-dir "$TEST_TMPDIR/bad-data" --confirm
assert_exit "a profile that is not JSON: refused" 1 "$RC"
assert_file_absent "a profile that is not JSON: nothing written" "$TEST_TMPDIR/bad-data"

jq '.machine.facts = []' "$TWO" >"$TEST_TMPDIR/no-os.json"
run "$TEST_TMPDIR/no-os.json"
assert_exit "a profile with no os fact: refused" 1 "$RC"

# --- The checkout is untouched ----------------------------------------------------
if [[ -z "$REPO_ROOT" ]]; then
  echo "ok: checkout comparison skipped (not run from a git checkout)"
else
  assert_eq "no file under the repository checkout changed" "$REPO_BEFORE" "$(repo_state)"
fi

report
