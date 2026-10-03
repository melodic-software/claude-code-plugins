#!/usr/bin/env bash
# Unit tests for resolve-diff-base.sh. Each case builds a throwaway linear
# history, puts a fake `gh` first on PATH that answers the runs listing and the
# head_sha lookups from fixture files (through the real jq, so the script's own
# filters are exercised), and asserts the ref the script writes to
# GITHUB_OUTPUT and the reason it logs.
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/resolve-diff-base.sh"
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

command -v jq >/dev/null || {
  fail "jq is required"
  test_harness::report
}

BIN="$TMP_ROOT/bin"
mkdir -p "$BIN"
# The listing is $FAKE/listed ("<sha> <conclusion>" per line, in response
# order) and a lookup answers from $FAKE/runs (same shape). A file named
# listing-fails or lookup-fails makes that call exit 1, as gh does on an HTTP
# error. Every call's URL is appended to $FAKE/calls.
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = api ] && [ "$3" = --jq ] || exit 2
printf '%s\n' "$2" >>"$FAKE/calls"
runs_json() { jq -Rn '{workflow_runs: [inputs | split(" ") | {head_sha: .[0], conclusion: .[1]}]}'; }
case "$2" in
*head_sha=*)
  [ ! -e "$FAKE/lookup-fails" ] || { echo 'HTTP 502' >&2; exit 1; }
  grep "^${2##*head_sha=} " "$FAKE/runs" | runs_json | jq -r "$4"
  ;;
*)
  [ ! -e "$FAKE/listing-fails" ] || { echo 'HTTP 503' >&2; exit 1; }
  runs_json <"$FAKE/listed" | jq -r "$4"
  ;;
esac
EOF
chmod +x "$BIN/gh"

repo='' FAKE='' OUT='' REF=''
SHA=()

# mk_repo <commits>: a fresh repo whose main holds that many commits, each
# touching plugins/p/f; SHA[1] is the root and SHA[<commits>] is HEAD. Clears
# the fake's state: nothing listed, no runs.
mk_repo() {
  local i
  repo="$(mktemp -d "$TMP_ROOT/repo.XXXXXX")"
  git_test_config "$repo" init -q -b main
  SHA=('')
  for ((i = 1; i <= $1; i++)); do
    mkdir -p "$repo/plugins/p"
    printf '%s\n' "$i" >"$repo/plugins/p/f"
    git_test_config "$repo" add -A
    git_test_config "$repo" commit -qm "c$i"
    SHA+=("$(git -C "$repo" rev-parse HEAD)")
  done
  FAKE="$(mktemp -d "$TMP_ROOT/fake.XXXXXX")"
  : >"$FAKE/listed"
  : >"$FAKE/runs"
  : >"$FAKE/calls"
}

listed() { printf '%s %s\n' "$@" >>"$FAKE/listed"; }
runs() { printf '%s %s\n' "$@" >>"$FAKE/runs"; }

# resolve [event] [dir]: run the script; OUT is what it printed, REF the ref it
# wrote (empty for the whole tree).
resolve() {
  local gho="$TMP_ROOT/gho"
  : >"$gho"
  OUT="$(cd "${2:-$repo}" && env PATH="$BIN:$PATH" FAKE="$FAKE" GITHUB_OUTPUT="$gho" \
    GITHUB_EVENT_NAME="${1:-push}" GITHUB_REPOSITORY=o/r GITHUB_REF_NAME=main \
    GITHUB_SHA="${SHA[-1]}" BASE_REF=main bash "$SCRIPT" 2>&1)"
  REF="$(sed -n 's/^ref=//p' "$gho")"
}

# expect <label> <ref or ""> <text the output must hold>
expect() {
  if [[ "$REF" == "$2" && "$OUT" == *"$3"* ]]; then
    ok "$1"
  else
    fail "$1: expected ref '$2' and output holding '$3'; got ref '$REF', output:
$OUT"
  fi
}

lookups() { grep -c 'head_sha=' "$FAKE/calls"; }

# check <label> <condition...>: records the condition's verdict.
check() {
  local label="$1"
  shift
  if "$@"; then ok "$label"; else fail "$label"; fi
}

# --- the common case: HEAD's parent is green and listed ----------------------
mk_repo 4
listed "${SHA[3]}" success "${SHA[2]}" success
resolve
expect "parent green in the listing" "${SHA[3]}" "1 back on the first-parent line, green in the listing"
check "no head_sha lookup when the listing answers" test "$(lookups)" = 0

# --- #6134: the listing lacks the newer green runs ---------------------------
# It returns an old green run first; the parent's run failed and the
# grandparent's passed, but only a head_sha lookup shows the latter.
mk_repo 6
listed "${SHA[1]}" success
runs "${SHA[5]}" failure "${SHA[4]}" success
resolve
expect "a green run missing from the listing is found by lookup" "${SHA[4]}" "green by head_sha lookup, missing from the listing"
expect "the rejected parent is logged with its reason" "${SHA[4]}" "Skipped ${SHA[5]:0:9} (1 back): no green ci push run."
expect "the listing size is logged" "${SHA[4]}" "holds 1 green; newest first: ${SHA[1]:0:9}"

# --- order of the listing does not decide: topology does ---------------------
mk_repo 6
listed "${SHA[1]}" success "${SHA[2]}" success "${SHA[4]}" success "${SHA[5]}" cancelled
runs "${SHA[5]}" cancelled
resolve
expect "an out-of-order listing still yields the nearest green ancestor" "${SHA[4]}" "2 back"

# --- runs that are not green, or not ancestors, are never the base -----------
mk_repo 4
side="$(git -C "$repo" commit-tree -p "${SHA[3]}" -m side "$(git -C "$repo" rev-parse 'HEAD^{tree}')")"
listed "$side" success "${SHA[4]}" success "${SHA[3]}" failure "${SHA[2]}" success
runs "${SHA[3]}" failure
resolve
expect "HEAD's own run, a red run and a non-ancestor are passed over" "${SHA[2]}" "2 back"

# --- the listing fails: lookups still find the base --------------------------
mk_repo 4
touch "$FAKE/listing-fails"
runs "${SHA[3]}" success
resolve
expect "a failed listing falls back to lookups" "${SHA[3]}" "could not be listed"

# --- no green ancestor: the whole tree ---------------------------------------
mk_repo 4
listed "${SHA[3]}" failure
runs "${SHA[3]}" failure
resolve
expect "no green ancestor tests the whole tree" "" "No commit among the last 200 on HEAD's first-parent line has a green ci push run; this push run tests the whole tree."

mk_repo 4
touch "$FAKE/listing-fails" "$FAKE/lookup-fails"
resolve
expect "every API call failing tests the whole tree" "" "the head_sha lookup failed (HTTP 502)"
expect "and says so" "" "this push run tests the whole tree."

# --- lookups are bounded; the listing still reaches further back -------------
mk_repo 25
listed "${SHA[1]}" success
resolve
expect "past the lookup budget the listing still answers" "${SHA[1]}" "24 back on the first-parent line, green in the listing"
check "at most 20 head_sha lookups" test "$(lookups)" = 20

# --- a range that touches the shared test machinery --------------------------
mk_repo 3
mkdir -p "$repo/scripts/lib"
printf 'x\n' >"$repo/scripts/lib/x.sh"
git_test_config "$repo" add -A
git_test_config "$repo" commit -qm lib
SHA+=("$(git -C "$repo" rev-parse HEAD)")
listed "${SHA[3]}" success
resolve
expect "a machinery change tests the whole tree" "" "touches the shared test machinery: scripts/lib/x.sh"

# --- ancestry that cannot be read --------------------------------------------
mk_repo 4
listed "${SHA[3]}" success
shallow="$TMP_ROOT/shallow"
git clone -q --depth 1 "file://$repo" "$shallow"
resolve push "$shallow"
expect "a shallow clone tests the whole tree" "" "History is shallow"
rm -rf "$shallow"

mk_repo 1
resolve
expect "a root commit tests the whole tree" "" "HEAD's ancestry could not be read"

# --- other events -------------------------------------------------------------
mk_repo 2
resolve pull_request
expect "a pull request diffs against its base branch" "origin/main" ""
check "a pull request makes no API call" test ! -s "$FAKE/calls"
resolve schedule
expect "a schedule run tests the whole tree" "" "A schedule run has no diff base; this schedule run tests the whole tree."

test_harness::report
