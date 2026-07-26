#!/usr/bin/env bash
# Unit tests for check-contract-slice-prune.sh. Each scenario builds a throwaway
# git repo, commits a base, applies a branch change, and asserts the gate's
# verdict. The deletion and graduation cases are the ones that matter most: a
# gate that red-lined the prune commit would forbid the very step the topic-docs
# convention requires.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-contract-slice-prune.sh"
PARSE_LIB="$SELF_DIR/../lib/parse-concern-value.sh"

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
  mkdir -p "$dir/scripts" "$dir/lib" "$dir/docs/topics"
  cp "$SCRIPT" "$dir/scripts/check-contract-slice-prune.sh"
  # The gate delegates the concern-file scalar parse to the shared helper, so a
  # fixture repo must carry it too — running against a repo without it is the
  # fail-closed case, not the normal one.
  cp "$PARSE_LIB" "$dir/lib/parse-concern-value.sh"
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

# --- a PR cannot self-grandfather: baseline is read from the BASE revision ---
# Without this, one diff adding docs/topics/<slug>/ AND the matching baseline
# line would exempt itself and the gate would be decorative.
repo="$(mk_repo)"
mkdir -p "$repo/docs/topics/sneaky"
printf 'plan\n' >"$repo/docs/topics/sneaky/PLAN.md"
printf 'sneaky\n' >"$repo/scripts/contract-slice-baseline.txt"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "a PR adding its own baseline line must NOT exempt itself"; else ok "baseline read from base revision: self-grandfathering is rejected"; fi
rm -rf "$repo"

# --- a baseline entry that already existed at base still exempts -------------
repo="$(mk_repo $'legacy\n')"
mkdir -p "$repo/docs/topics/legacy"
printf 'plan\n' >"$repo/docs/topics/legacy/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then ok "a pre-existing baseline entry still exempts"; else fail "base-revision read must not break legitimate grandfathering"; fi
rm -rf "$repo"

# --- contract_dir resolves from the tracked concern file --------------------
# A repo that relocates its contract root must not have the gate silently keep
# checking docs/topics and leave the real root unguarded.
repo="$(mk_repo)"
mkdir -p "$repo/.claude"
printf 'contract_dir: docs/slices   # relocated\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q add -A && git_q commit -m concern && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/docs/slices/relocated"
printf 'plan\n' >"$repo/docs/slices/relocated/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "a slice under the configured contract_dir must be red-lined"; else ok "contract_dir resolves from .claude/topic-docs.yaml"; fi
rm -rf "$repo"

# --- with a relocated contract_dir, the OLD default is no longer policed -----
repo="$(mk_repo)"
mkdir -p "$repo/.claude"
printf 'contract_dir: docs/slices\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q add -A && git_q commit -m concern && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/docs/topics/stale"
printf 'plan\n' >"$repo/docs/topics/stale/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then ok "a relocated contract_dir moves the gate's scope"; else fail "docs/topics must not stay policed once contract_dir moves"; fi
rm -rf "$repo"

# --- a root-equivalent contract_dir is refused, not silently honoured --------
repo="$(mk_repo)"
mkdir -p "$repo/.claude"
printf 'contract_dir: .\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q add -A && git_q commit -m concern && git_q checkout base && git_q merge work && git_q checkout work)
printf 'edit\n' >>"$repo/README.md"
commit_work "$repo"
out="$(run_diff "$repo")"
rc=$?
if ((rc == 2)) && [[ "$out" == *"root-equivalent"* ]]; then ok "root-equivalent contract_dir exits 2"; else fail "root-equivalent contract_dir must exit 2, got rc=$rc"; fi
rm -rf "$repo"

# --- a slug-less baseline must not abort under set -u -----------------------
# This is the END state #1419 drives toward, so a crash here would block the
# very cleanup the gate exists to enable.
repo="$(mk_repo $'# only a comment, no slugs\n')"
out="$(run_check "$repo")"
rc=$?
if ((rc == 0)) && [[ "$out" != *"unbound variable"* ]]; then ok "--check survives a slug-less baseline"; else fail "empty baseline must not abort: rc=$rc out=$out"; fi
rm -rf "$repo"

# --- relocating contract_dir cannot smuggle a slice under the NEW root -------
# --check-diff resolves the base root so a PR cannot narrow its own scope; it
# must ALSO police the head root, or a relocation leaves the root it selected
# uninspected.
repo="$(mk_repo $'legacy\n')"
mkdir -p "$repo/docs/topics/legacy"
printf 'plan\n' >"$repo/docs/topics/legacy/PLAN.md"
(cd "$repo" && git_q add -A && git_q commit -m seed && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/.claude" "$repo/docs/slices/legacy" "$repo/docs/slices/newslug"
printf 'contract_dir: docs/slices\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q mv docs/topics/legacy/PLAN.md docs/slices/legacy/PLAN.md)
printf 'plan\n' >"$repo/docs/slices/newslug/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "a slice under a same-PR-relocated root must be red-lined"; else ok "both base and head contract roots are policed"; fi
rm -rf "$repo"

# --- migrating a grandfathered slice to a relocated root still passes -------
# The union must not punish a legitimate relocation that carries its debt over.
repo="$(mk_repo $'legacy\n')"
mkdir -p "$repo/docs/topics/legacy"
printf 'plan\n' >"$repo/docs/topics/legacy/PLAN.md"
(cd "$repo" && git_q add -A && git_q commit -m seed && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/.claude" "$repo/docs/slices/legacy"
printf 'contract_dir: docs/slices\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q mv docs/topics/legacy/PLAN.md docs/slices/legacy/PLAN.md)
commit_work "$repo"
if run_diff "$repo" >/dev/null; then ok "a grandfathered slice may migrate to a relocated root"; else fail "carrying existing debt to a new root must not be red-lined"; fi
rm -rf "$repo"

# --- a contract_dir with reducible segments still matches git's diff paths ---
# Git names paths canonically, so an unnormalized root would match nothing and
# the configured root would go unpoliced while the gate reported success.
repo="$(mk_repo)"
mkdir -p "$repo/.claude"
printf 'contract_dir: ./docs/topics\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q add -A && git_q commit -m concern && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/docs/topics/newslug"
printf 'plan\n' >"$repo/docs/topics/newslug/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "a './'-prefixed contract_dir must still police its root"; else ok "contract_dir is canonicalized before matching"; fi
rm -rf "$repo"

repo="$(mk_repo)"
mkdir -p "$repo/.claude"
printf 'contract_dir: docs/x/../topics\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q add -A && git_q commit -m concern && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/docs/topics/newslug"
printf 'plan\n' >"$repo/docs/topics/newslug/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "a contract_dir with a '..' segment must resolve to its real root"; else ok "'..' segments are resolved, not matched literally"; fi
rm -rf "$repo"

# --- a contract_dir that escapes the repo root is refused --------------------
repo="$(mk_repo)"
mkdir -p "$repo/.claude"
printf 'contract_dir: ../outside\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q add -A && git_q commit -m concern && git_q checkout base && git_q merge work && git_q checkout work)
printf 'edit\n' >>"$repo/README.md"
commit_work "$repo"
out="$(run_diff "$repo")"
rc=$?
if ((rc == 2)) && [[ "$out" == *"escapes the repo root"* ]]; then ok "an escaping contract_dir exits 2"; else fail "an escaping contract_dir must exit 2, got rc=$rc"; fi
rm -rf "$repo"

# --- a literal hash inside contract_dir is not a comment ---------------------
# Truncating at an adjacent '#' would silently police 'docs/a' and leave the
# real 'docs/a#b' root unchecked.
repo="$(mk_repo)"
mkdir -p "$repo/.claude"
printf 'contract_dir: docs/a#b\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q add -A && git_q commit -m concern && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/docs/a#b/newslug"
printf 'plan\n' >"$repo/docs/a#b/newslug/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "an adjacent '#' must stay part of contract_dir"; else ok "a literal hash in contract_dir survives the parse"; fi
rm -rf "$repo"

# --- a trailing comment on contract_dir is still stripped --------------------
repo="$(mk_repo)"
mkdir -p "$repo/.claude"
printf 'contract_dir: docs/slices   # relocated root\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q add -A && git_q commit -m concern && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/docs/slices/newslug"
printf 'plan\n' >"$repo/docs/slices/newslug/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "a trailing ' #' comment must not become part of the root"; else ok "a trailing comment is still stripped"; fi
rm -rf "$repo"

# --- nested roots: the MOST SPECIFIC root owns a path -----------------------
# Relocating contract_dir beneath a grandfathered slice used to let the outer
# root match first, naming the exempt slug 'legacy' for every path inside the
# new root — so a brand-new slice smuggled in alongside the migrated one passed.
repo="$(mk_repo $'legacy\n')"
mkdir -p "$repo/docs/topics/legacy"
printf 'plan\n' >"$repo/docs/topics/legacy/PLAN.md"
(cd "$repo" && git_q add -A && git_q commit -m seed && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/.claude" "$repo/docs/topics/legacy/legacy" "$repo/docs/topics/legacy/newslug"
printf 'contract_dir: docs/topics/legacy\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q mv docs/topics/legacy/PLAN.md docs/topics/legacy/legacy/PLAN.md)
printf 'plan\n' >"$repo/docs/topics/legacy/newslug/PLAN.md"
commit_work "$repo"
if run_diff "$repo" >/dev/null; then fail "a new slice under a nested relocated root must be red-lined"; else ok "the most specific contract root owns a path"; fi
rm -rf "$repo"

# --- nested roots: migrating the grandfathered slice itself still passes -----
repo="$(mk_repo $'legacy\n')"
mkdir -p "$repo/docs/topics/legacy"
printf 'plan\n' >"$repo/docs/topics/legacy/PLAN.md"
(cd "$repo" && git_q add -A && git_q commit -m seed && git_q checkout base && git_q merge work && git_q checkout work)
mkdir -p "$repo/.claude" "$repo/docs/topics/legacy/legacy"
printf 'contract_dir: docs/topics/legacy\n' >"$repo/.claude/topic-docs.yaml"
(cd "$repo" && git_q mv docs/topics/legacy/PLAN.md docs/topics/legacy/legacy/PLAN.md)
commit_work "$repo"
if run_diff "$repo" >/dev/null; then ok "a grandfathered slice may migrate into a nested root"; else fail "most-specific matching must not punish a legitimate migration"; fi
rm -rf "$repo"

# --- usage ------------------------------------------------------------------
repo="$(mk_repo)"
(cd "$repo" && bash scripts/check-contract-slice-prune.sh --bogus >/dev/null 2>&1)
if (($? == 2)); then ok "unknown mode exits 2"; else fail "unknown mode must exit 2"; fi
rm -rf "$repo"

echo ""
echo "check-contract-slice-prune.test.sh: $PASS passed, $FAIL failed"
((FAIL == 0))
