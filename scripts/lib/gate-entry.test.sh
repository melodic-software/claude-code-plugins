#!/usr/bin/env bash
# Entry-protocol tests. The subshell cases run in a child bash: a fatal inside
# this process would take the suite down with it, which is the property under
# test.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
# shellcheck source=changed-files.sh
. "$SELF_DIR/changed-files.sh"
# shellcheck source=gate-entry.sh
. "$SELF_DIR/gate-entry.sh"
# shellcheck source=../test-git-helpers.sh
. "$SELF_DIR/../test-git-helpers.sh"
# shellcheck source=test-harness.sh
. "$SELF_DIR/test-harness.sh"

LIB="$SELF_DIR/gate-entry.sh"

child() {
  local script="$1"
  shift
  bash -c "$script" bash "$LIB" "$@"
}

# --- finish: one 0/1/2 map ------------------------------------------------

rc=0
child 'source "$1"; gate_entry::finish 0' || rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "finish maps 0 to 0"
else
  fail "finish 0 exited $rc"
fi
rc=0
child 'source "$1"; gate_entry::finish 1' || rc=$?
if [[ "$rc" -eq 1 ]]; then
  ok "finish maps 1 to 1"
else
  fail "finish 1 exited $rc"
fi
rc=0
child 'source "$1"; gate_entry::finish 9' || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "finish maps any other status to 2"
else
  fail "finish 9 exited $rc"
fi
rc=0
child 'source "$1"; gate_entry::finish' || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "finish with no status is fail-closed 2"
else
  fail "finish with no status exited $rc"
fi

# --- mode dispatch --------------------------------------------------------

rc=0
out="$(child 'source "$1"; gate_entry::classify --all; printf "%s" "$GE_MODE"')" || rc=$?
if [[ "$rc" -eq 0 && "$out" == "all" ]]; then
  ok "classify --all sets the all mode"
else
  fail "classify --all rc=$rc out=$out"
fi
rc=0
out="$(child 'source "$1"; gate_entry::classify --paths a.sh b.sh; printf "%s %s" "$GE_MODE" "${GE_PATHS[*]}"')" || rc=$?
if [[ "$rc" -eq 0 && "$out" == "paths a.sh b.sh" ]]; then
  ok "classify --paths keeps the file list and does not exit"
else
  fail "classify --paths rc=$rc out=$out"
fi
rc=0
child 'source "$1"; gate_entry::classify' || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "classify with no arguments returns 2"
else
  fail "classify with no arguments exited $rc"
fi
rc=0
child 'source "$1"; gate_entry::classify --paths' || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "classify --paths with no files returns 2"
else
  fail "classify --paths with no files exited $rc"
fi
rc=0
child 'source "$1"; gate_entry::classify --all extra' || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "classify --all rejects extra arguments"
else
  fail "classify --all extra exited $rc"
fi
rc=0
child 'source "$1"; gate_entry::classify --nope' || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "classify rejects an unknown flag"
else
  fail "classify --nope exited $rc"
fi

# --all and --paths must not consult a ref, even when git cannot resolve one.
log="$(mktemp)"
rc=0
child 'source "$1"; git() { printf x >>"$2"; return 1; }; gate_entry::classify --all' "$log" || rc=$?
if [[ "$rc" -eq 0 && ! -s "$log" ]]; then
  ok "--all does not consult a ref"
else
  fail "--all consulted git or failed (rc=$rc log=$(cat "$log"))"
fi
: >"$log"
rc=0
child 'source "$1"; git() { printf x >>"$2"; return 1; }; gate_entry::classify --paths f.sh' "$log" || rc=$?
if [[ "$rc" -eq 0 && ! -s "$log" ]]; then
  ok "--paths does not consult a ref"
else
  fail "--paths consulted git or failed (rc=$rc log=$(cat "$log"))"
fi
rm -f "$log"

# --- unresolvable base exits 2, including from a subshell -----------------

rc=0
out="$(child 'source "$1"; gate_entry::require_base definitely-not-a-ref' 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && "$out" == *"not a valid commit"* ]]; then
  ok "an unresolvable base ref exits 2 from the parent shell"
else
  fail "parent require_base rc=$rc out=$out"
fi

rc=0
out="$(child 'source "$1"; mapfile -t files < <(gate_entry::require_base definitely-not-a-ref); echo SWALLOWED; exit 0' 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && "$out" != *SWALLOWED* ]]; then
  ok "mapfile cannot swallow an unresolvable base ref"
else
  fail "mapfile swallow rc=$rc out=$out"
fi

rc=0
out="$(child 'source "$1"; files="$(gate_entry::require_base definitely-not-a-ref)"; echo SWALLOWED; exit 0' 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && "$out" != *SWALLOWED* ]]; then
  ok "command substitution cannot swallow an unresolvable base ref"
else
  fail "command-substitution swallow rc=$rc out=$out"
fi

rc=0
out="$(child 'source "$1"; gate_entry::classify definitely-not-a-ref' 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && "$out" == *"not a valid commit"* ]]; then
  ok "classify of an unresolvable base ref exits 2"
else
  fail "classify bad ref rc=$rc out=$out"
fi

# --- empty discovery is not a failed discovery ----------------------------

repo="$(mktemp -d)"
git_init_test_repo "$repo" >/dev/null
printf 'seed\n' >"$repo/f.txt"
git_test_config "$repo" add -A >/dev/null
git_test_config "$repo" commit -qm base >/dev/null

paths=()
GE_DISCOVERY=""
if (
  cd "$repo" || exit 1
  gate_entry::collect_changed paths HEAD --
  [[ "$GE_DISCOVERY" == "empty" && ${#paths[@]} -eq 0 ]]
); then
  ok "a clean diff is an empty discovery, not a failure"
else
  fail "empty discovery was not reported (GE_DISCOVERY=${GE_DISCOVERY:-} n=${#paths[@]})"
fi

printf 'changed\n' >"$repo/f.txt"
paths=()
GE_DISCOVERY=""
if (
  cd "$repo" || exit 1
  gate_entry::collect_changed paths HEAD --
  [[ "$GE_DISCOVERY" == "populated" && ${#paths[@]} -eq 1 && "${paths[0]}" == "f.txt" ]]
); then
  ok "a real change is a populated discovery"
else
  fail "populated discovery was ${GE_DISCOVERY:-} (${paths[*]-})"
fi

# The commit object still resolves; its tree does not. That is a failed
# discovery, and it must not come back as an empty set at exit 0.
base="$(git -C "$repo" rev-parse HEAD)"
subtree="$(git -C "$repo" rev-parse "HEAD^{tree}")"
rm -f "$repo/.git/objects/${subtree:0:2}/${subtree:2}"
rc=0
out="$(child 'source "$1"; cd "$2" || exit 1; gate_entry::collect_changed paths "$3" --; echo SWALLOWED; exit 0' "$repo" "$base" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && "$out" != *SWALLOWED* && "$out" == *"refusing to report an empty change set"* ]]; then
  ok "a failed diff exits 2 instead of an empty discovery"
else
  fail "failed diff rc=$rc out=$out"
fi
rm -rf "$repo"

# --- no gate hand-rolls the commit-existence predicate --------------------

hits="$(grep -nE 'rev-parse --verify --quiet' "$REPO_ROOT"/scripts/check-*.sh "$REPO_ROOT"/scripts/check-*.test.sh || true)"
if [[ -z "$hits" ]]; then
  ok "no gate or gate test hand-rolls the base-ref predicate"
else
  fail "hand-rolled base-ref predicate still present: $hits"
fi

test_harness::report
