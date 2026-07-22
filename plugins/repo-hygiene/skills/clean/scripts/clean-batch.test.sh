#!/usr/bin/env bash
# Tests for clean-batch.sh — the selective-tier fleet orchestrator.
#
# Covers the field-observed requirements: one gate over many repos; the batch
# plan IS the gated set (apply consumes it, tolerating a vanished repo); a
# skip-listed repo is skipped and an unmatched skip is surfaced; the git tier
# prunes each shared object store once (worktrees deduped).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

BATCH="$SCRIPT_DIR/clean-batch.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

mkrepo() {
  # mkrepo <name> — a repo with a removable cache + build dir.
  local d="$TEST_TMPDIR/$1"
  git init "$d" >/dev/null 2>&1
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  mkdir -p "$d/.pytest_cache" && echo x >"$d/.pytest_cache/x"
  mkdir -p "$d/bin" && echo b >"$d/bin/b"
  git -C "$d" commit --allow-empty -m init >/dev/null 2>&1
  printf '%s' "$d"
}

# --- 1. usage guards ---
rc=0
bash "$BATCH" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

rc=0
bash "$BATCH" --repo "$TEST_TMPDIR" >/dev/null 2>&1 || rc=$?
assert_exit "missing --tier exits 2" 2 "$rc"

rc=0
bash "$BATCH" --tier bogus --repo "$TEST_TMPDIR" >/dev/null 2>&1 || rc=$?
assert_exit "unknown tier exits 2" 2 "$rc"

rc=0
bash "$BATCH" --tier caches >/dev/null 2>&1 || rc=$?
assert_exit "no repos exits 2" 2 "$rc"

rc=0
bash "$BATCH" --tier caches --apply --repo "$(mkrepo apponly)" >/dev/null 2>&1 || rc=$?
assert_exit "apply without --batch-plan exits 2 (mandatory gate)" 2 "$rc"

# A missing --batch-plan parent is created (mkdir -p), so that path is helpful:
NEWPLAN="$TEST_TMPDIR/fresh/nested/plan"
rc=0
out="$(bash "$BATCH" --tier caches --repo "$(mkrepo planparent)" --batch-plan "$NEWPLAN" 2>&1)" || rc=$?
assert_exit "missing --batch-plan parent is created, dry-run succeeds" 0 "$rc"
assert_file_exists "plan actually written at the requested path" "$NEWPLAN"

# But an UNCREATABLE plan dir (parent is a regular file) must fail loudly with a
# nonzero exit — never print BatchPlan/Summary and exit 0 with no plan written.
echo blocker >"$TEST_TMPDIR/afile"
rc=0
out="$(bash "$BATCH" --tier caches --repo "$(mkrepo planparent2)" --batch-plan "$TEST_TMPDIR/afile/sub/plan" 2>&1)" || rc=$?
assert_exit "uncreatable --batch-plan dir exits 2" 2 "$rc"
assert_not_contains "no BatchPlan printed on plan-write failure" "$out" "BatchPlan:"

# --- 2. caches dry-run over 2 repos: one plan, aggregate summary ---
R1="$(mkrepo r1)"
R2="$(mkrepo r2)"
out="$(bash "$BATCH" --tier caches --repo "$R1" "$R2")"
assert_contains "dry-run announces fleet" "$out" "Fleet Clean (dry-run)"
assert_contains "dry-run counts 2 repos" "$out" "Repos: 2"
assert_contains "per-repo outcome would-clean" "$out" "Outcome: would-clean"
assert_contains "aggregate planned summary" "$out" "Summary: repos=2 planned=2"
PLAN="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
assert_file_exists "batch plan written" "$PLAN"
if grep -q '^REPO	' "$PLAN"; then
  pass "plan has REPO lines"
else
  fail "plan has REPO lines" "REPO lines" "$(cat "$PLAN")"
fi
assert_file_exists "cache still present after dry-run" "$R1/.pytest_cache/x"

# --- 3. caches apply consumes the gated plan ---
out="$(bash "$BATCH" --tier caches --apply --batch-plan "$PLAN")"
assert_contains "apply announces fleet" "$out" "Fleet Clean (apply)"
assert_contains "apply cleaned outcome" "$out" "Outcome: cleaned"
assert_contains "apply aggregate summary" "$out" "Summary: removed=2 failed=0"
assert_file_absent "cache removed after apply r1" "$R1/.pytest_cache/x"
assert_file_absent "cache removed after apply r2" "$R2/.pytest_cache/x"

# --- 4. fleet-race: a repo that vanished after the dry-run is tolerated ---
R3="$(mkrepo r3)"
R4="$(mkrepo r4)"
out="$(bash "$BATCH" --tier caches --repo "$R3" "$R4")"
PLAN2="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
# Simulate a repo that vanished between dry-run and apply by renaming it away.
# (Rename, not `rm -rf`: on Windows a git repo's packed objects can be transiently
# locked, so `rm -rf` leaves a partial dir and flakes; a rename is atomic and
# models a gone repo exactly — the plan's toplevel no longer resolves.)
mv "$R4" "${R4}.gone"
rc=0
out="$(bash "$BATCH" --tier caches --apply --batch-plan "$PLAN2")" || rc=$?
assert_exit "apply tolerates a vanished repo (exit 0)" 0 "$rc"
assert_contains "vanished repo reported skipped" "$out" "vanished after dry-run"
assert_contains "surviving repo still cleaned" "$out" "removed=1"

# --- 4b. fail-closed: a repo that lost its .git mid-apply (dir remains, child
#         refuses "not a git repository" and exits before any Summary line) must
#         count as a failure — batch exits 1, never a silent removed=0/exit-0. ---
R6="$(mkrepo r6)"
out="$(bash "$BATCH" --tier caches --repo "$R6")"
PLAN_R6="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
mv "$R6/.git" "$R6/.gitgone" # repo dir stays, git metadata gone (rename, not rm)
rc=0
out="$(bash "$BATCH" --tier caches --apply --batch-plan "$PLAN_R6" 2>&1)" || rc=$?
assert_exit "de-gitted repo fails the batch closed (exit 1)" 1 "$rc"
assert_contains "de-gitted repo reported failed" "$out" "Outcome: failed"
assert_contains "aggregate summary counts the failure" "$out" "failed=1"

# --- 4c. malformed plan record: a REPO line with an EMPTY manifest field must
#         fail closed at apply, never pass --manifest "" to the child (which would
#         re-walk the live repo and remove artifacts outside the gated plan). ---
R7="$(mkrepo r7)"
BADPLANFILE="$TEST_TMPDIR/badplan"
printf 'REPO\t%s\tcaches\t\n' "$(git -C "$R7" rev-parse --show-toplevel)" >"$BADPLANFILE"
rc=0
out="$(bash "$BATCH" --tier caches --apply --batch-plan "$BADPLANFILE" 2>&1)" || rc=$?
assert_exit "malformed REPO record (empty manifest) fails closed (exit 1)" 1 "$rc"
assert_contains "malformed record reported" "$out" "malformed plan record"
assert_file_exists "live repo cache NOT re-walked/removed" "$R7/.pytest_cache/x"

# --- 5. skip list + unmatched skip ---
out="$(bash "$BATCH" --tier caches --repo "$R1" "$R2" --skip r2 --skip nosuchrepo)"
assert_contains "skip-listed repo skipped" "$out" "skip-list (r2)"
assert_contains "unmatched skip surfaced" "$out" "UnmatchedSkip: nosuchrepo"

# --- 5b. collision-free manifests: two repos whose sanitized keys collide
#         (differ only by punctuation) must get DISTINCT manifest paths. ---
RA="$(mkrepo 'repo-x')"
RB="$(mkrepo 'repo_x')"
out="$(bash "$BATCH" --tier caches --repo "$RA" "$RB")"
CPLAN="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
n_manifests="$(awk -F'\t' '$1=="REPO"{print $4}' "$CPLAN" | sort -u | wc -l)"
if [[ "$n_manifests" -eq 2 ]]; then
  pass "punctuation-colliding repo keys get distinct manifests"
else
  fail "distinct manifests for colliding keys" 2 "$n_manifests"
fi

# --- 6. build tier folds caches into the manifest ---
R5="$(mkrepo r5)"
out="$(bash "$BATCH" --tier build --repo "$R5")"
PLAN3="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
if grep -q '^REPO	.*	build	' "$PLAN3"; then
  pass "build tier writes a build child token"
else
  fail "build tier token" "build" "$(cat "$PLAN3")"
fi
out="$(bash "$BATCH" --tier build --apply --batch-plan "$PLAN3")"
assert_file_absent "build dir removed" "$R5/bin/b"
assert_file_absent "cache removed by build tier (folds caches)" "$R5/.pytest_cache/x"

# --- 7. git tier: one prune per shared object store (worktree deduped) ---
GR="$(mkrepo gitrepo)"
git -C "$GR" worktree add "$TEST_TMPDIR/gitrepo-wt" -b wt >/dev/null 2>&1
out="$(bash "$BATCH" --tier git --repo "$GR" "$TEST_TMPDIR/gitrepo-wt")"
assert_contains "git tier reports gitdirs=1 (worktree deduped)" "$out" "gitdirs=1"
GPLAN="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
if [[ "$(grep -c '^GITDIR	' "$GPLAN")" -eq 1 ]]; then
  pass "plan has exactly one GITDIR line"
else
  fail "one GITDIR line" 1 "$(grep -c '^GITDIR	' "$GPLAN")"
fi
rc=0
out="$(bash "$BATCH" --tier git --apply --batch-plan "$GPLAN")" || rc=$?
assert_exit "git apply exits 0" 0 "$rc"
assert_contains "git apply prunes the store once" "$out" "Outcome: pruned"

# --- 8. all tier: build manifest + git dedup in one plan ---
AR="$(mkrepo allrepo)"
out="$(bash "$BATCH" --tier all --repo "$AR")"
APLAN="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
if grep -q '^REPO	' "$APLAN" && grep -q '^GITDIR	' "$APLAN"; then
  pass "all tier plan carries both REPO and GITDIR lines"
else
  fail "all tier plan REPO+GITDIR" "both" "$(cat "$APLAN")"
fi

[[ $FAILED -eq 0 ]] || exit 1
echo "clean-batch.test.sh: all passed"
