#!/usr/bin/env bash
# Entry-protocol tests. The subshell cases run in a child bash: a fatal inside
# this process would take the suite down with it, which is the property under
# test.
#
# test-scope: scripts/*.sh
# shellcheck disable=SC2016  # child programs stay single-quoted so this shell does not expand $1 before bash -c
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

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
log="$(mktemp "$TMP_ROOT/f.XXXXXX")"
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

# --- declared flag modes --------------------------------------------------

rc=0
out="$(child 'source "$1"; GE_FLAGS=(--check --check-bump:ref); gate_entry::classify --check-bump HEAD; printf "%s %s" "$GE_MODE" "$GE_REF"')" || rc=$?
if [[ "$rc" -eq 0 && "$out" == "--check-bump HEAD" ]]; then
  ok "a declared ref mode sets the flag and the ref"
else
  fail "declared ref mode rc=$rc out=$out"
fi
rc=0
out="$(child 'source "$1"; GE_FLAGS=(--check-bump:ref); GE_BAD_REF_MSG="gate: bad ref"; gate_entry::classify --check-bump definitely-not-a-ref' 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && "$out" == "gate: bad ref" ]]; then
  ok "a declared ref mode exits 2 with the gate's own diagnostic on a bad ref"
else
  fail "declared ref mode bad ref rc=$rc out=$out"
fi
rc=0
out="$(child 'source "$1"; GE_FLAGS=(--check --check-bump:ref); gate_entry::classify --check; printf "%s|%s" "$GE_MODE" "$GE_REF"')" || rc=$?
if [[ "$rc" -eq 0 && "$out" == "--check|" ]]; then
  ok "a declared no-ref mode sets the flag and no ref"
else
  fail "declared no-ref mode rc=$rc out=$out"
fi
rc=0
child 'source "$1"; GE_FLAGS=(--check); gate_entry::classify --check extra' || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "a declared no-ref mode rejects extra arguments"
else
  fail "declared no-ref mode with extra exited $rc"
fi
rc=0
out="$(child 'source "$1"; GE_FLAGS=(--check); gate_entry::classify --check-bump HEAD' 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && -z "$out" ]]; then
  ok "an undeclared flag returns 2 without printing"
else
  fail "undeclared flag rc=$rc out=$out"
fi
rc=0
out="$(child 'source "$1"; GE_FLAGS=(--check); gate_entry::classify --all || gate_entry::classify HEAD' 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && -z "$out" ]]; then
  ok "declared flags replace the legacy modes"
else
  fail "legacy mode under declared flags rc=$rc out=$out"
fi
rc=0
out="$(child 'source "$1"; GE_FLAGS=(--check-bump:ref); gate_entry::classify --check-bump' 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && -z "$out" ]]; then
  ok "a declared ref mode with no ref returns 2 without printing"
else
  fail "missing ref rc=$rc out=$out"
fi
rc=0
child 'source "$1"; GE_FLAGS=(--check-bump:ref); gate_entry::classify --check-bump HEAD extra' || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "a declared ref mode rejects extra arguments"
else
  fail "declared ref mode with extra exited $rc"
fi
rc=0
out="$(child 'source "$1"; gate_entry::classify --check' 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && -z "$out" ]]; then
  ok "a gate that declares nothing still rejects a flag"
else
  fail "legacy flag rejection rc=$rc out=$out"
fi
rc=0
out="$(child 'source "$1"; gate_entry::classify HEAD; printf "%s %s" "$GE_MODE" "$GE_REF"')" || rc=$?
if [[ "$rc" -eq 0 && "$out" == "base HEAD" ]]; then
  ok "classify of a resolvable base ref still sets the base mode"
else
  fail "legacy base mode rc=$rc out=$out"
fi

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

repo="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
git_init_test_repo "$repo" >/dev/null
printf 'seed\n' >"$repo/f.txt"
git_test_config "$repo" add -A >/dev/null
git_test_config "$repo" commit -qm base >/dev/null

paths=()
if (
  cd "$repo" || exit 1
  gate_entry::collect_changed paths HEAD --
  [[ ${#paths[@]} -eq 0 ]]
); then
  ok "a clean diff is an empty discovery, not a failure"
else
  fail "empty discovery was not reported"
fi

printf 'changed\n' >"$repo/f.txt"
paths=()
if (
  cd "$repo" || exit 1
  gate_entry::collect_changed paths HEAD --
  [[ ${#paths[@]} -eq 1 && "${paths[0]}" == "f.txt" ]]
); then
  ok "a real change is a populated discovery"
else
  fail "populated discovery returned the wrong paths"
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

# Every rev-parse in a script that verifies or peels to a commit is either
# changed_files::verify_base or one of these, each keyed by "<file>|<fixed
# substring of the line>|<why it is not the existence predicate>". An entry whose
# line is gone fails, so the list cannot outlive what it excuses.
BASE_REF_ALLOW=(
  'check-silent-revert.sh|sha="$(git rev-parse --verify "${commit}^{commit}"|captures the resolved sha'
  'check-silent-revert.sh|git rev-parse --verify "${sha}^1"|captures the first parent'
  'check-silent-revert.sh|git rev-parse --verify "${parent}:${file}"|captures a blob id'
  'check-silent-revert.sh|git rev-parse --verify "${commit}:${file}"|captures a blob id'
  'check-stale-base-overlap.sh|base_tip="$(git rev-parse "${base_ref}^{commit}")"|captures the resolved sha'
  "check-changelog-parity.sh|git rev-parse -q --verify 'HEAD^2'|probes for a merge commit, not a base ref"
  "check-changelog-fragments.sh|git rev-parse -q --verify 'HEAD^2'|probes for a merge commit, not a base ref"
  "dependabot-plugin-bump.sh|git rev-parse -q --verify 'HEAD^2'|probes for a merge commit, not a base ref"
  "changelog-fragments.sh|git rev-parse -q --verify 'HEAD^2'|probes for a merge commit, not a base ref"
)

# Prints the rev-parse lines under <scripts-dir> that peel to a commit or use
# --verify, comments and changed-files.sh excluded, and not on BASE_REF_ALLOW.
# The pattern is assembled so this file does not match itself.
base_ref_predicate_hits() {
  local dir="$1" f name line entry allowed
  local pattern="rev-parse.*(\\^\\{commit\\}|--ver""ify)"
  for f in "$dir"/*.sh "$dir"/lib/*.sh; do
    [[ -f "$f" ]] || continue
    name="${f##*/}"
    [[ "$name" == changed-files.sh || "$name" == gate-entry.test.sh ]] && continue
    while IFS= read -r line; do
      [[ "${line#*:}" =~ ^[[:space:]]*# ]] && continue
      allowed=0
      for entry in "${BASE_REF_ALLOW[@]}"; do
        [[ "${entry%%|*}" == "$name" && "$line" == *"$(cut -d'|' -f2 <<<"$entry")"* ]] && allowed=1
      done
      ((allowed)) || printf '%s:%s\n' "$name" "$line"
    done < <(grep -nE "$pattern" "$f" || true)
  done
}

# Prints each BASE_REF_ALLOW entry that matches no line under <scripts-dir>.
stale_base_ref_allow() {
  local dir="$1" entry file sub
  for entry in "${BASE_REF_ALLOW[@]}"; do
    file="${entry%%|*}"
    sub="$(cut -d'|' -f2 <<<"$entry")"
    # An entry names a file under scripts/ or scripts/lib/, as the scan reads both.
    grep -qF -- "$sub" "$dir/$file" "$dir/lib/$file" 2>/dev/null || printf '%s\n' "$entry"
  done
}

hits="$(base_ref_predicate_hits "$REPO_ROOT/scripts")"
if [[ -z "$hits" ]]; then
  ok "no script hand-rolls the base-ref predicate"
else
  fail "hand-rolled base-ref predicate still present: $hits"
fi

stale="$(stale_base_ref_allow "$REPO_ROOT/scripts")"
if [[ -z "$stale" ]]; then
  ok "every base-ref allowlist entry still matches a line"
else
  fail "stale base-ref allowlist entries: $stale"
fi

scratch="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
printf '%s\n' 'git rev-parse -q --verify "$b^{commit}" >/dev/null || exit 2' >"$scratch/scratch.sh"
if [[ -n "$(base_ref_predicate_hits "$scratch")" ]]; then
  ok "a scratch script hand-rolling the predicate is caught"
else
  fail "the guard missed a hand-rolled predicate"
fi
if [[ -n "$(stale_base_ref_allow "$scratch")" ]]; then
  ok "an allowlist entry matching no line is reported stale"
else
  fail "the stale allowlist check passed against a tree with none of the entries"
fi
rm -rf "$scratch"

test_harness::report
