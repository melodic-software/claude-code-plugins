#!/usr/bin/env bash
# Unit tests for check-contract-slice-prune.sh. Each scenario builds a throwaway
# git repo, commits a base, applies a branch change, and asserts the gate's
# verdict. The deletion and graduation cases are the ones that matter most: a
# gate that red-lined the prune commit would forbid the very step the topic-docs
# convention requires.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-contract-slice-prune.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

git_q() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

# mk_repo <baseline-content>: throwaway git repo with the gate installed, one
# base commit on a `base` branch, and a checked-out `work` branch.
mk_repo() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/docs/topics"
  cp "$SCRIPT" "$dir/scripts/check-contract-slice-prune.sh"
  printf '%s' "${1:-}" >"$dir/scripts/contract-slice-baseline.txt"
  printf 'seed\n' >"$dir/README.md"
  (
    cd "$dir" || exit 1
    git_q init -b base
    git_q add -A
    git_q commit -m base
    git_q checkout -b work
  )
  printf '%s' "$dir"
}

# commit everything currently in the tree onto the work branch
commit_work() { (cd "$1" && git_q add -A && git_q commit -m work); }

run_diff() { (cd "$1" && bash scripts/check-contract-slice-prune.sh --check-diff base 2>&1); }
run_check() { (cd "$1" && bash scripts/check-contract-slice-prune.sh --check 2>&1); }

# --- adding a new slice is the core violation ------------------------------
repo="$(mk_repo)"
mkdir -p "$repo/docs/topics/newslug"
printf 'plan\n' >"$repo/docs/topics/newslug/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "an added slice must be red-lined"; else ok "added slice is red-lined"; fi
rm -rf "$repo"

# --- deleting a slice is the prune step and must pass ----------------------
repo="$(mk_repo)"
mkdir -p "$repo/docs/topics/oldslug"
printf 'plan\n' >"$repo/docs/topics/oldslug/PLAN.md"
(cd "$repo" && git_q add -A && git_q commit -m seed-slice && git_q checkout base && git_q merge work && git_q checkout work)
rm -rf "${repo:?}/docs/topics/oldslug"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then ok "pure deletion passes (the prune commit)"; else fail "the prune commit must not be red-lined"; fi
rm -rf "$repo"

# --- a change set that never touches the contract dir passes ---------------
repo="$(mk_repo)"
printf 'edit\n' >>"$repo/README.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then ok "untouched contract dir passes"; else fail "unrelated change wrongly red-lined"; fi
rm -rf "$repo"

# --- a grandfathered slug is exempt from edits AND additions ---------------
repo="$(mk_repo $'# c\nlegacy\n')"
mkdir -p "$repo/docs/topics/legacy"
printf 'plan\n' >"$repo/docs/topics/legacy/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then ok "grandfathered slug is exempt"; else fail "baseline entry failed to exempt its slug"; fi
rm -rf "$repo"

# --- a NEW slug is still red-lined while a baseline exists -----------------
repo="$(mk_repo $'# c\nlegacy\n')"
mkdir -p "$repo/docs/topics/brandnew"
printf 'plan\n' >"$repo/docs/topics/brandnew/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "a non-baselined slug must still be red-lined"; else ok "baseline does not blanket-exempt new slugs"; fi
rm -rf "$repo"

# --- graduation: git mv OUT of the contract dir must pass ------------------
repo="$(mk_repo)"
mkdir -p "$repo/docs/topics/grad" "$repo/docs/adr"
printf 'a durable decision worth graduating, long enough to score as a rename\n' >"$repo/docs/topics/grad/PLAN.md"
(cd "$repo" && git_q add -A && git_q commit -m seed-slice && git_q checkout base && git_q merge work && git_q checkout work)
(cd "$repo" && git_q mv docs/topics/grad/PLAN.md docs/adr/0005-decision.md)
commit_work "$repo"
if run_diff "$repo" >/dev/null; then ok "graduation out of the contract dir passes"; else fail "history-preserving graduation must not be red-lined"; fi
rm -rf "$repo"

# --- a rename INTO the contract dir is still a violation -------------------
repo="$(mk_repo)"
printf 'content that will be moved into the contract dir, long enough to rename-score\n' >"$repo/docs/stray.md"
(cd "$repo" && git_q add -A && git_q commit -m seed && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/docs/topics/moved"
(cd "$repo" && git_q mv docs/stray.md docs/topics/moved/PLAN.md)
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "a rename INTO the contract dir must be red-lined"; else ok "rename into the contract dir is red-lined"; fi
rm -rf "$repo"

# --- fail-closed on an unresolvable base ref -------------------------------
repo="$(mk_repo)"
out="$(cd "$repo" && bash scripts/check-contract-slice-prune.sh --check-diff no/such/ref 2>&1)"
rc=$?
if ((rc == 2)) && [[ "$out" == *"not a resolvable commit"* ]]; then ok "unresolvable base ref exits 2"; else fail "unresolvable base ref must exit 2, got rc=$rc"; fi
rm -rf "$repo"

# --- --check: a live baseline entry passes ---------------------------------
repo="$(mk_repo $'legacy\n')"
mkdir -p "$repo/docs/topics/legacy"
printf 'plan\n' >"$repo/docs/topics/legacy/PLAN.md"
if run_check "$repo" >/dev/null; then ok "--check passes while the slice exists"; else fail "--check wrongly flagged a live baseline entry"; fi
rm -rf "$repo"

# --- --check: a stale baseline entry fails ---------------------------------
repo="$(mk_repo $'ghost\n')"
out="$(run_check "$repo")"
if [[ "$out" == *"STALE BASELINE"* ]]; then ok "--check fails on a stale baseline entry"; else fail "a baseline entry outliving its slice must fail --check"; fi
rm -rf "$repo"

# --- usage ------------------------------------------------------------------
repo="$(mk_repo)"
(cd "$repo" && bash scripts/check-contract-slice-prune.sh --bogus >/dev/null 2>&1)
if (($? == 2)); then ok "unknown mode exits 2"; else fail "unknown mode must exit 2"; fi
rm -rf "$repo"

echo ""
echo "check-contract-slice-prune.test.sh: $PASS passed, $FAIL failed"
((FAIL == 0))
