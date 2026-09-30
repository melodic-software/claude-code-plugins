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
# Run from a non-repo cwd so default plans land under the per-user state dir in
# TEST_TMPDIR and are cleaned up with it.
export XDG_STATE_HOME="$TEST_TMPDIR/state"
cd "$TEST_TMPDIR" || exit 1

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

# A --batch-plan pointing at an existing NON-plan file (a typo onto user data)
# must be refused, not truncated.
USERFILE="$TEST_TMPDIR/precious.txt"
printf 'important user data\nsecond line\n' >"$USERFILE"
rc=0
out="$(bash "$BATCH" --tier caches --repo "$(mkrepo planparent3)" --batch-plan "$USERFILE" 2>&1)" || rc=$?
assert_exit "refuses to truncate a non-plan file (exit 2)" 2 "$rc"
assert_contains "refusal reported" "$out" "not a batch plan"
if [[ "$(cat "$USERFILE")" == "important user data"$'\n'"second line" ]]; then
  pass "non-plan file left intact, not truncated"
else
  fail "non-plan file preserved" "important user data..." "$(cat "$USERFILE")"
fi
# An existing VALID batch plan is resumable (overwrite allowed).
VALIDPLAN="$TEST_TMPDIR/valid.plan"
printf 'REPO\t/x\tcaches\t/x/m.manifest\nGITDIR\t/y\tkey\n' >"$VALIDPLAN"
rc=0
out="$(bash "$BATCH" --tier caches --repo "$(mkrepo planparent4)" --batch-plan "$VALIDPLAN" 2>&1)" || rc=$?
assert_exit "existing batch plan is overwritable (resumable)" 0 "$rc"

# --- 1b. default plan location: the state dir, never /tmp or inside a repo; explicit --batch-plan wins ---
RD="$(mkrepo defplan)"
out="$(cd "$RD" && bash "$BATCH" --tier caches --repo "$RD" 2>&1)"
P="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
assert_contains "in-repo default plan lands under the state dir" "$P" "$TEST_TMPDIR/state/repo-hygiene/"
assert_file_exists "in-repo default plan written" "$P"
assert_not_contains "the invoking repo gains no .work/" "$(git -C "$RD" status --porcelain)" ".work"
NOREPO="$TEST_TMPDIR/norepo"
mkdir -p "$NOREPO"
out="$(cd "$NOREPO" && bash "$BATCH" --tier caches --repo "$RD" 2>&1)"
P="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
assert_contains "out-of-repo default plan lands under the state dir" "$P" "$TEST_TMPDIR/state/repo-hygiene/"
assert_file_exists "out-of-repo default plan written" "$P"
EXPLICIT="$TEST_TMPDIR/explicit/plan"
out="$(cd "$RD" && bash "$BATCH" --tier caches --repo "$RD" --batch-plan "$EXPLICIT" 2>&1)"
assert_contains "explicit --batch-plan overrides the default" "$out" "BatchPlan: $EXPLICIT"

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

# --- 4d. tier-authorization: a plan built for a BROADER tier must be refused when
#         applied under a NARROWER --tier, before anything is removed. The exact
#         repro: a `--tier build` dry-run plan (REPO/build records that fold caches)
#         applied with `--tier caches` must NOT remove bin/ OR .pytest_cache/. ---
R8="$(mkrepo r8)"
out="$(bash "$BATCH" --tier build --repo "$R8")"
PLAN_R8="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
rc=0
out="$(bash "$BATCH" --tier caches --apply --batch-plan "$PLAN_R8" 2>&1)" || rc=$?
assert_exit "build plan under --tier caches is refused (exit 2)" 2 "$rc"
assert_contains "tier-mismatch refusal reported" "$out" "does not match --tier caches"
assert_not_contains "no apply banner printed on tier mismatch" "$out" "Fleet Clean (apply)"
assert_file_exists "build dir NOT removed by mismatched apply" "$R8/bin/b"
assert_file_exists "cache NOT removed by mismatched apply" "$R8/.pytest_cache/x"

# --- 4e. tier-authorization: a GITDIR record must be refused under a non-git tier
#         (gate the GITDIR arm on a git-bearing tier). ---
GR2="$(mkrepo gitrepo2)"
out="$(bash "$BATCH" --tier git --repo "$GR2")"
GPLAN2="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
rc=0
out="$(bash "$BATCH" --tier caches --apply --batch-plan "$GPLAN2" 2>&1)" || rc=$?
assert_exit "git plan under --tier caches is refused (exit 2)" 2 "$rc"
assert_contains "GITDIR-under-non-git refusal reported" "$out" "GITDIR record requires --tier git or all"

# --- 4f. tier-authorization is not over-strict: an `all` plan (REPO/build + GITDIR)
#         applied under --tier all authorizes BOTH record kinds and runs them. ---
AR2="$(mkrepo allrepo2)"
out="$(bash "$BATCH" --tier all --repo "$AR2")"
APLAN2="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
rc=0
out="$(bash "$BATCH" --tier all --apply --batch-plan "$APLAN2" 2>&1)" || rc=$?
assert_exit "all plan under --tier all applies (exit 0)" 0 "$rc"
assert_contains "all apply cleans the build/caches manifest" "$out" "Outcome: cleaned"
assert_contains "all apply prunes the shared object store" "$out" "Outcome: pruned"
assert_file_absent "all apply removed build dir" "$AR2/bin/b"
assert_file_absent "all apply removed cache" "$AR2/.pytest_cache/x"

# --- 4g. tier-authorization runs in BOTH directions: `all` authorizes both record
#         kinds, so a NARROWER plan passes every per-record test while applying only
#         part of the requested tier. A `build` plan (no GITDIR) under --tier all
#         would clean build artifacts and silently skip every prune; a `git` plan
#         (no REPO) would prune and silently skip every build removal. Both are the
#         same scope misrepresentation as 4d, from the other side. ---
AR3="$(mkrepo allrepo3)"
out="$(bash "$BATCH" --tier build --repo "$AR3")"
BPLAN3="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
rc=0
out="$(bash "$BATCH" --tier all --apply --batch-plan "$BPLAN3" 2>&1)" || rc=$?
assert_exit "build plan under --tier all is refused (exit 2)" 2 "$rc"
assert_contains "missing-GITDIR refusal reported" "$out" "carries no well-formed GITDIR record"
assert_not_contains "no apply banner on missing-GITDIR refusal" "$out" "Fleet Clean (apply)"
assert_file_exists "build dir NOT removed by under-scoped all apply" "$AR3/bin/b"

AR4="$(mkrepo allrepo4)"
out="$(bash "$BATCH" --tier git --repo "$AR4")"
GPLAN4="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
rc=0
out="$(bash "$BATCH" --tier all --apply --batch-plan "$GPLAN4" 2>&1)" || rc=$?
assert_exit "git plan under --tier all is refused (exit 2)" 2 "$rc"
assert_contains "missing-REPO refusal reported" "$out" "carries no well-formed REPO record"
assert_not_contains "no apply banner on missing-REPO refusal" "$out" "Fleet Clean (apply)"

# An EMPTY plan plans nothing for either kind and removes nothing, so the presence
# requirement must not turn it into an error under --tier all.
EMPTYPLAN="$TEST_TMPDIR/empty-all.plan"
: >"$EMPTYPLAN"
rc=0
out="$(bash "$BATCH" --tier all --apply --batch-plan "$EMPTYPLAN" 2>&1)" || rc=$?
assert_exit "empty plan under --tier all applies as a no-op (exit 0)" 0 "$rc"
assert_contains "empty all apply reports gitdirs=0" "$out" "gitdirs=0"

# --- 4h. only a STRUCTURALLY WELL-FORMED record satisfies the `all` both-kinds
#         requirement. A truncated record (`GITDIR\t\t`, `REPO\t\tbuild\t`) names no
#         target, so counting it as presence would let a narrower plan clear 4g's
#         check on a record that removes nothing — apply would print `Tier: all` and
#         a gitdirs= tally while performing no cleanup for that half. The apply loop
#         fails such a record closed (exit 1, structural corruption) — a distinct
#         class from 4d/4g's well-formed-but-wrong-tier plan (exit 2, atomic). ---
AR5="$(mkrepo allrepo5)"
out="$(bash "$BATCH" --tier build --repo "$AR5")"
BPLAN5="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
printf 'GITDIR\t\t\n' >>"$BPLAN5" # truncated: no representative worktree
rc=0
out="$(bash "$BATCH" --tier all --apply --batch-plan "$BPLAN5" 2>&1)" || rc=$?
assert_exit "truncated GITDIR does not satisfy --tier all (exit 2)" 2 "$rc"
assert_contains "truncated GITDIR still reported as missing" "$out" "carries no well-formed GITDIR record"
assert_not_contains "no apply banner on truncated-GITDIR refusal" "$out" "Fleet Clean (apply)"
assert_file_exists "build dir NOT removed by truncated-GITDIR all apply" "$AR5/bin/b"

# The mirror: a truncated REPO record must not satisfy the build half either. The
# reachable truncation is a missing MANIFEST field (as in 4c) — tab is IFS
# whitespace, so `read` collapses consecutive tabs and an empty leading field
# cannot survive plan parsing.
AR6="$(mkrepo allrepo6)"
out="$(bash "$BATCH" --tier git --repo "$AR6")"
GPLAN6="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
printf 'REPO\t%s\tbuild\t\n' "$AR6" >>"$GPLAN6" # truncated: no manifest path
rc=0
out="$(bash "$BATCH" --tier all --apply --batch-plan "$GPLAN6" 2>&1)" || rc=$?
assert_exit "truncated REPO does not satisfy --tier all (exit 2)" 2 "$rc"
assert_contains "truncated REPO still reported as missing" "$out" "carries no well-formed REPO record"
assert_not_contains "no apply banner on truncated-REPO refusal" "$out" "Fleet Clean (apply)"
assert_file_exists "nothing pruned/removed by truncated-REPO all apply" "$AR6/bin/b"

# The apply-loop half, on the path the `all` presence check does not gate: a
# truncated GITDIR under --tier git must fail closed and count NO gitdir — never
# exit 0 with gitdirs=1 for a prune that had no target.
TRUNCPLAN="$TEST_TMPDIR/trunc-gitdir.plan"
printf 'GITDIR\t\t\n' >"$TRUNCPLAN"
rc=0
out="$(bash "$BATCH" --tier git --apply --batch-plan "$TRUNCPLAN" 2>&1)" || rc=$?
assert_exit "truncated GITDIR fails closed under --tier git (exit 1)" 1 "$rc"
assert_contains "truncated GITDIR reported malformed" "$out" "malformed plan record"
assert_contains "truncated GITDIR counted as a failure, not a gitdir" "$out" "failed=1 bytes=0 gitdirs=0"

# Not over-strict: one valid GITDIR satisfies presence even alongside a malformed
# sibling — the valid store is still pruned, the malformed record still fails closed.
AR7="$(mkrepo allrepo7)"
out="$(bash "$BATCH" --tier all --repo "$AR7")"
APLAN7="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
printf 'GITDIR\t\t\n' >>"$APLAN7"
rc=0
out="$(bash "$BATCH" --tier all --apply --batch-plan "$APLAN7" 2>&1)" || rc=$?
assert_exit "valid GITDIR + malformed sibling applies then fails closed (exit 1)" 1 "$rc"
assert_contains "presence satisfied by the valid record (apply ran)" "$out" "Fleet Clean (apply)"
assert_contains "valid store still pruned" "$out" "Outcome: pruned"
assert_contains "malformed sibling reported" "$out" "malformed plan record"
assert_contains "only the valid GITDIR counted" "$out" "failed=1"
assert_contains "malformed sibling adds no gitdir" "$out" "gitdirs=1"
assert_file_absent "valid REPO record still applied" "$AR7/bin/b"

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

# --- 6b. git tier dry-run counts only what apply acts on; all tier splits bytes per tier ---
# `git gc --auto` does nothing below gc.auto or gc.autoPackLimit, so loose objects
# under those limits are not planned work; above one they are.
git_totals() { sed -n 's/.*planned=\([0-9]*\) bytes=\([0-9]*\).*/\1 \2/p' <<<"$1" | tail -1; }
LR="$(mkrepo looserepo)"
for n in 1 2 3; do echo "blob $n" | git -C "$LR" hash-object -w --stdin >/dev/null; done
loose_before="$(git -C "$LR" count-objects -v)"
git -C "$LR" gc --auto --quiet
if [[ "$(git -C "$LR" count-objects -v)" == "$loose_before" ]]; then pass "git gc --auto removes nothing below its limits"; else fail "git gc --auto removes nothing below its limits" "$loose_before" "$(git -C "$LR" count-objects -v)"; fi
out="$(bash "$BATCH" --tier git --repo "$LR")"
if [[ "$(git_totals "$out")" == "0 0" ]]; then pass "--tier git dry-run plans no loose objects below gc.auto"; else fail "--tier git plans no loose objects below gc.auto" "0 0" "$(git_totals "$out")"; fi
git -C "$LR" config gc.auto 2
out="$(bash "$BATCH" --tier git --repo "$LR")"
read -r gp gb <<<"$(git_totals "$out")"
if [[ "${gp:-0}" -gt 0 && "${gb:-0}" -gt 0 ]]; then pass "--tier git dry-run plans loose objects above gc.auto"; else fail "--tier git plans loose objects above gc.auto" ">0" "planned=$gp bytes=$gb"; fi
assert_contains "git_bytes equals the git tier bytes" "$out" "bytes=$gb skipped=0 blocked=0 gitdirs=1 git_bytes=$gb"
git -C "$LR" config gc.auto 0
out="$(bash "$BATCH" --tier git --repo "$LR")"
if [[ "$(git_totals "$out")" == "0 0" ]]; then pass "gc.auto 0 turns auto gc off, so nothing is planned"; else fail "gc.auto 0 plans nothing" "0 0" "$(git_totals "$out")"; fi
git -C "$LR" config --unset gc.auto
git -C "$LR" repack -q -d
git -C "$LR" commit --allow-empty -qm second
git -C "$LR" repack -q -d
out="$(bash "$BATCH" --tier git --repo "$LR")"
if [[ "$(git_totals "$out")" == "0 0" ]]; then pass "two packs are below the default gc.autoPackLimit"; else fail "two packs are below gc.autoPackLimit" "0 0" "$(git_totals "$out")"; fi
git -C "$LR" config gc.autoPackLimit 1
out="$(bash "$BATCH" --tier git --repo "$LR")"
read -r gp gb <<<"$(git_totals "$out")"
if [[ "${gp:-0}" -gt 0 && "${gb:-0}" -gt 0 ]]; then pass "--tier git dry-run plans loose objects above gc.autoPackLimit"; else fail "--tier git plans loose objects above gc.autoPackLimit" ">0" "planned=$gp bytes=$gb"; fi
out="$(bash "$BATCH" --tier all --repo "$LR")"
assert_contains "--tier all prints caches_bytes" "$out" "caches_bytes="
assert_contains "--tier all prints build_bytes" "$out" "build_bytes="
assert_contains "--tier all prints git_bytes" "$out" "git_bytes="

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

# --- 8b. scan tier: read-only inventory, no plan, no apply ---
SC1="$(mkrepo scan1)"
SC2="$(mkrepo scan2)"
SC3="$(mkrepo scan3)"
t1="$(cd "$SC1" && bash "$SCRIPT_DIR/scan.sh" | sed -n 's/^Total reclaimable: //p')"
t2="$(cd "$SC2" && bash "$SCRIPT_DIR/scan.sh" | sed -n 's/^Total reclaimable: //p')"
out="$(bash "$BATCH" --tier scan --repo "$SC1" "$SC2" --skip scan3 --skip nosuchrepo)"
rc=$?
assert_exit "scan tier exits 0" 0 "$rc"
assert_contains "scan announces fleet scan" "$out" "Fleet Clean (scan)"
assert_contains "scan per-repo outcome" "$out" "Outcome: scanned"
assert_contains "scan sums the per-repo totals" "$out" "Summary: repos=2 planned=0 bytes=$((t1 + t2)) skipped=0 blocked=0"
assert_not_contains "scan writes no batch plan" "$out" "BatchPlan:"
assert_contains "scan reports an unmatched skip" "$out" "UnmatchedSkip: nosuchrepo"
assert_file_exists "scan leaves the cache" "$SC1/.pytest_cache/x"
assert_file_exists "scan leaves the build dir" "$SC1/bin/b"
out="$(bash "$BATCH" --tier scan --repo "$SC1" "$SC3" --skip scan3 --repo "$TEST_TMPDIR/not-a-dir")"
assert_contains "scan honors the skip list" "$out" "skip-list (scan3)"
assert_contains "scan reports a non-repo input as blocked" "$out" "Reason: not-a-directory"
assert_contains "scan counts skipped and blocked" "$out" "skipped=1 blocked=1"
rc=0
out="$(bash "$BATCH" --tier scan --apply --repo "$SC1" 2>&1)" || rc=$?
assert_exit "scan with --apply exits 2" 2 "$rc"
assert_contains "scan --apply refusal names the tier" "$out" "--tier scan is read-only"
rc=0
bash "$BATCH" --tier scan --repo "$SC1" --batch-plan "$TEST_TMPDIR/scan.plan" >/dev/null 2>&1 || rc=$?
assert_exit "scan with --batch-plan exits 2" 2 "$rc"
assert_file_absent "scan --batch-plan wrote nothing" "$TEST_TMPDIR/scan.plan"
rc=0
bash "$BATCH" --tier scan >/dev/null 2>&1 || rc=$?
assert_exit "scan with no repos exits 2" 2 "$rc"
out="$(bash "$BATCH" --tier bogus --repo "$SC1" 2>&1)" || true
assert_contains "unknown-tier message lists scan" "$out" "use scan|caches|build|git|all"

# --- 9. --repos-from / --skip-from source-open contract (#3482) ---
# A trailing blank is ordinary EOF success; only a missing/unopenable named
# source is "file not found". Empty input is success at the helper and surfaces
# as "no repos given", never as a missing file.
RF="$(mkrepo rf)"
printf '%s\n\n' "$RF" >"$TEST_TMPDIR/repos-trail.txt"
rc=0
out="$(bash "$BATCH" --tier caches --repos-from "$TEST_TMPDIR/repos-trail.txt" 2>&1)" || rc=$?
assert_exit "trailing-blank --repos-from is accepted (exit 0)" 0 "$rc"
assert_not_contains "trailing blank is not reported as file-not-found" "$out" "file not found"
assert_contains "trailing-blank list enumerates the repo" "$out" "Repos: 1"

: >"$TEST_TMPDIR/repos-empty.txt"
rc=0
out="$(bash "$BATCH" --tier caches --repos-from "$TEST_TMPDIR/repos-empty.txt" 2>&1)" || rc=$?
assert_exit "empty --repos-from is a usage error (exit 2)" 2 "$rc"
assert_not_contains "empty file is not reported missing" "$out" "file not found"
assert_contains "empty file reaches no-repos usage" "$out" "no repos given"

printf '%s' "$RF" >"$TEST_TMPDIR/repos-noeol.txt"
rc=0
out="$(bash "$BATCH" --tier caches --repos-from "$TEST_TMPDIR/repos-noeol.txt" 2>&1)" || rc=$?
assert_exit "unterminated --repos-from is accepted (exit 0)" 0 "$rc"
assert_contains "unterminated list enumerates the repo" "$out" "Repos: 1"

printf '%s\r\n' "$RF" >"$TEST_TMPDIR/repos-cr.txt"
rc=0
out="$(bash "$BATCH" --tier caches --repos-from "$TEST_TMPDIR/repos-cr.txt" 2>&1)" || rc=$?
assert_exit "CR-terminated --repos-from is accepted (exit 0)" 0 "$rc"
assert_contains "CR-stripped list enumerates the repo" "$out" "Repos: 1"

rc=0
out="$(bash "$BATCH" --tier caches --repos-from "$TEST_TMPDIR/no-such-repos.txt" 2>&1)" || rc=$?
assert_exit "missing --repos-from exits 2" 2 "$rc"
assert_contains "missing file reported not found" "$out" "file not found:"

SKIP_TRAIL="$TEST_TMPDIR/skips-trail.txt"
printf 'rf\n\n' >"$SKIP_TRAIL"
rc=0
out="$(bash "$BATCH" --tier caches --repo "$RF" --skip-from "$SKIP_TRAIL" 2>&1)" || rc=$?
assert_exit "trailing-blank --skip-from is accepted (exit 0)" 0 "$rc"
assert_not_contains "trailing-blank skip-from is not file-not-found" "$out" "file not found"
assert_contains "trailing-blank skip-from still skips" "$out" "skip-list"

rc=0
out="$(bash "$BATCH" --tier caches --repo "$RF" --skip-from "$TEST_TMPDIR/no-such-skips.txt" 2>&1)" || rc=$?
assert_exit "missing --skip-from exits 2" 2 "$rc"
assert_contains "missing skip-from reported not found" "$out" "file not found:"

UNREAD_LIST="$TEST_TMPDIR/unreadable-repos.txt"
printf '%s\n' "$RF" >"$UNREAD_LIST"
chmod 000 "$UNREAD_LIST" 2>/dev/null || true
if [[ -r "$UNREAD_LIST" ]]; then
  skip_case "unopenable --repos-from: chmod 000 not enforced on this filesystem (CAP_DAC_OVERRIDE)"
else
  rc=0
  out="$(bash "$BATCH" --tier caches --repos-from "$UNREAD_LIST" 2>&1)" || rc=$?
  assert_exit "unopenable --repos-from exits 2" 2 "$rc"
  assert_contains "unopenable file reported not found" "$out" "file not found:"
fi
chmod 644 "$UNREAD_LIST" 2>/dev/null || true

# --- preflight once, and a progress line on stderr ---
PROG_REPO="$(mkrepo prog)"
# A fresh build inside the target repo must reach RECENT_BUILD even when the
# batch runs from outside every target (the ghq fleet case).
mkdir -p "$PROG_REPO/obj"
: >"$PROG_REPO/obj/project.assets.json"
rc=0
out="$(cd / && bash "$BATCH" --tier caches --repo "$PROG_REPO" 2>/dev/null)" || rc=$?
err="$(bash "$BATCH" --tier caches --repo "$PROG_REPO" 2>&1 >/dev/null)" || true
assert_exit "caches dry-run still exits 0 with preflight" 0 "$rc"
assert_contains "caches dry-run prints preflight scope once" "$out" "PreflightScope: batch-repositories"
assert_contains "preflight scans the target repo, not the cwd" "$out" "RECENT_BUILD: $PROG_REPO/obj/project.assets.json"
assert_contains "caches dry-run prints preflight facts" "$out" "RUNTIME_PROCS:"
preflight_hits="$(grep -c 'PreflightScope:' <<<"$out" || true)"
assert_exit "preflight runs once, not per repo" 1 "$preflight_hits"
assert_contains "dry-run progress names the repo" "$err" "Progress: 1/1 $PROG_REPO"

rc=0
git_out="$(bash "$BATCH" --tier git --repo "$PROG_REPO" 2>/dev/null)" || rc=$?
assert_exit "git dry-run exits 0" 0 "$rc"
assert_not_contains "git tier does not pay preflight" "$git_out" "PreflightScope:"

# --- fleet discovery (--fleet) and clone dedupe, with ghq / chezmoi shimmed on PATH ---
SHIM="$TEST_TMPDIR/shim"
mkdir -p "$SHIM"
FL_A="$(mkrepo fleet-a)"
FL_B="$(mkrepo fleet-b)"
FL_CLONE="$(mkrepo fleet-clone)"
FL_CZ="$(mkrepo fleet-chezmoi)"
git -C "$FL_A" remote add origin git@GitHub.com:owner/repo.git
git -C "$FL_CLONE" remote add origin https://user@github.com/owner/repo
git -C "$FL_B" remote add origin https://github.com/owner/other.git
git -C "$FL_CZ" remote add origin https://github.com/owner/dotfiles.git
printf '#!/bin/sh\nprintf "%%s\\n" "%s" "%s" "%s"\n' "$FL_A" "$FL_B" "$FL_CLONE" >"$SHIM/ghq"
printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$FL_CZ" >"$SHIM/chezmoi"
chmod +x "$SHIM/ghq" "$SHIM/chezmoi"

rc=0
out="$(PATH="$SHIM:$PATH" bash "$BATCH" --tier caches --fleet 2>/dev/null)" || rc=$?
assert_exit "--fleet dry-run exits 0" 0 "$rc"
assert_contains "fleet includes the chezmoi source repo" "$out" "Repo: $FL_CZ"
assert_contains "fleet includes a ghq repo" "$out" "Repo: $FL_B"
assert_contains "two clones of one remote: the first is kept" "$out" "Repo: $FL_A"$'\n'"Outcome: would-clean"
assert_contains "the other clone is reported as a duplicate" "$out" "skipped duplicate of $FL_A"
assert_contains "repos counts the unique repos, the duplicate is skipped" "$out" "repos=3 "
assert_contains "duplicate counted in skipped" "$out" "skipped=1 blocked=0"
dup_hits="$(grep -c 'skipped duplicate of' <<<"$out" || true)"
assert_exit "duplicate reported exactly once" 1 "$dup_hits"

assert_contains "the duplicate clone gets a table row" "$out" "$FL_CLONE | skipped | 0 | "

# --fleet dedupes the scan tier too.
rc=0
out="$(PATH="$SHIM:$PATH" bash "$BATCH" --tier scan --fleet 2>/dev/null)" || rc=$?
assert_exit "scan --fleet exits 0" 0 "$rc"
assert_contains "scan --fleet reports the second clone as a duplicate" "$out" "skipped duplicate of $FL_A"

# --repo and --repos-from are an explicit selection: two clones of one origin are
# both planned, in the caches tier and in the scan tier, with no duplicate record.
rc=0
out="$(bash "$BATCH" --tier caches --repo "$FL_A" "$FL_CLONE" 2>/dev/null)" || rc=$?
assert_exit "--repo with two clones exits 0" 0 "$rc"
assert_contains "--repo plans the first clone" "$out" "Repo: $FL_A"$'\n'"Outcome: would-clean"
assert_contains "--repo plans the second clone" "$out" "Repo: $FL_CLONE"$'\n'"Outcome: would-clean"
assert_contains "--repo counts both clones" "$out" "Summary: repos=2 planned=2 "
assert_contains "--repo skips nothing" "$out" "skipped=0 blocked=0"
assert_not_contains "--repo reports no duplicate" "$out" "skipped duplicate of"
out="$(printf '%s\n' "$FL_A" "$FL_CLONE" | bash "$BATCH" --tier caches --repos-from - 2>/dev/null)"
assert_contains "--repos-from plans both clones" "$out" "Summary: repos=2 planned=2 "
assert_not_contains "--repos-from reports no duplicate" "$out" "skipped duplicate of"
out="$(bash "$BATCH" --tier scan --repo "$FL_CLONE" "$FL_A" 2>/dev/null)"
assert_contains "scan --repo scans the first clone" "$out" "Repo: $FL_CLONE"$'\n'"Outcome: scanned"
assert_contains "scan --repo scans the second clone" "$out" "Repo: $FL_A"$'\n'"Outcome: scanned"
assert_not_contains "scan --repo reports no duplicate" "$out" "skipped duplicate of"
out="$(bash "$BATCH" --tier git --repo "$FL_A" "$FL_CLONE" 2>/dev/null)"
assert_contains "git --repo plans both clones' object stores" "$out" "gitdirs=2 "
assert_not_contains "git --repo reports no duplicate" "$out" "skipped duplicate of"

# A skip-listed clone never shadows its sibling under --fleet: the skipped one is
# reported skipped, the other still runs and is not a duplicate of it.
out="$(PATH="$SHIM:$PATH" bash "$BATCH" --tier caches --fleet --skip "$FL_A" 2>/dev/null)"
assert_contains "skipped clone is reported skipped" "$out" "Repo: $FL_A"$'\n'"Outcome: skipped"$'\n'"Reason: skip-list"
assert_contains "the sibling of a skipped clone is still planned" "$out" "Repo: $FL_CLONE"$'\n'"Outcome: would-clean"
assert_not_contains "the sibling of a skipped clone is not a duplicate" "$out" "skipped duplicate of"
assert_contains "three repos planned, one skipped" "$out" "Summary: repos=4 planned=3 "
out="$(PATH="$SHIM:$PATH" bash "$BATCH" --tier scan --fleet --skip "$FL_A" 2>/dev/null)"
assert_contains "scan: the sibling of a skipped clone is still scanned" "$out" "Repo: $FL_CLONE"$'\n'"Outcome: scanned"
assert_not_contains "scan: the sibling of a skipped clone is not a duplicate" "$out" "skipped duplicate of"
# Skipping the ghq clone by path leaves the chezmoi source of the same origin to run.
git -C "$FL_CZ" remote set-url origin git@github.com:owner/repo.git
out="$(PATH="$SHIM:$PATH" bash "$BATCH" --tier caches --fleet --skip "$FL_A" --skip "$FL_CLONE" 2>/dev/null)"
assert_contains "--fleet: the chezmoi source runs when its ghq clones are skipped" "$out" "Repo: $FL_CZ"$'\n'"Outcome: would-clean"
git -C "$FL_CZ" remote set-url origin https://github.com/owner/dotfiles.git

# A missing ghq/chezmoi contributes nothing; an empty fleet is the no-repos error.
NOTOOLS="$TEST_TMPDIR/notools"
mkdir -p "$NOTOOLS"
for t in git bash sed awk grep tr head dirname mktemp mkdir cat rm find sort date uname basename wc du cut; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$NOTOOLS/$t"
done
rc=0
PATH="$NOTOOLS" bash "$BATCH" --tier caches --fleet >/dev/null 2>&1 || rc=$?
assert_exit "--fleet with no ghq/chezmoi and no repos exits 2" 2 "$rc"

# A chezmoi source that is not a git repo is ignored.
NOGIT="$TEST_TMPDIR/cz-plain"
mkdir -p "$NOGIT"
printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$NOGIT" >"$SHIM/chezmoi"
out="$(PATH="$SHIM:$PATH" bash "$BATCH" --tier caches --fleet 2>/dev/null)"
assert_not_contains "non-git chezmoi source is not a fleet entry" "$out" "$NOGIT"

# --- nothing-to-do outcome, summary table, --batch-plan on dry-run ---
mkclean() {
  git init "$1" >/dev/null 2>&1
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name Test
  git -C "$1" commit --allow-empty -m init >/dev/null 2>&1
}
CLEAN="$TEST_TMPDIR/cleanrepo"
mkclean "$CLEAN"
out="$(bash "$BATCH" --tier caches --repo "$CLEAN" 2>/dev/null)"
assert_contains "clean repo reports nothing-to-do" "$out" "Outcome: nothing-to-do"
assert_not_contains "clean repo is not would-clean" "$out" "Outcome: would-clean"
assert_contains "clean repo summary keeps counting" "$out" "Summary: repos=1 planned=0"

DIRTY="$(mkrepo mixdirty)"
CLEAN2="$TEST_TMPDIR/cleanrepo2"
mkclean "$CLEAN2"
out="$(bash "$BATCH" --tier caches --repo "$DIRTY" "$CLEAN2" 2>/dev/null)"
assert_contains "mixed fleet has would-clean" "$out" "Outcome: would-clean"
assert_contains "mixed fleet has nothing-to-do" "$out" "Outcome: nothing-to-do"
assert_contains "summary table header" "$out" "Repo | Outcome | Paths | Bytes"
assert_contains "table row for the dirty repo" "$out" "$DIRTY | would-clean | "
assert_contains "table row for the clean repo" "$out" "$CLEAN2 | nothing-to-do | 0 | "

GT="$(mkrepo gitnew)"
git -C "$GT" worktree add "$TEST_TMPDIR/gitnew-wt" -b wt2 >/dev/null 2>&1
out="$(bash "$BATCH" --tier git --repo "$GT" "$TEST_TMPDIR/gitnew-wt" 2>/dev/null)"
assert_contains "git tier new store is would-clean" "$out" "$GT | would-clean | "
assert_contains "git tier sibling worktree is deduped" "$out" "deduped with a sibling worktree"
assert_not_contains "git tier never nothing-to-do for a new store" "$out" "$GT | nothing-to-do"
assert_contains "git tier deduped worktree is nothing-to-do" "$out" "$TEST_TMPDIR/gitnew-wt | nothing-to-do | "
assert_contains "git tier row counts nothing apply would not act on" "$out" "$GT | would-clean | 0 | 0 B"
assert_contains "git tier reason says the remote prune is not measured" "$out" "0 item(s) counted, 0 B; remote prune not measured"
# A worktree whose directory is gone is what `git worktree prune` removes: counted.
GW="$(mkrepo gitprune)"
git -C "$GW" worktree add "$TEST_TMPDIR/gitprune-gone" -b gone >/dev/null 2>&1
rm -rf "$TEST_TMPDIR/gitprune-gone"
out="$(bash "$BATCH" --tier git --repo "$GW" 2>/dev/null)"
assert_contains "git tier counts a prunable worktree" "$out" "$GW | would-clean | 1 | "

# A clean apply removes a default-location plan and its directory; an explicit
# --batch-plan is the caller's and stays.
out="$(bash "$BATCH" --tier caches --repo "$(mkrepo applyclean)" 2>/dev/null)"
DP="$(sed -n 's/^BatchPlan: //p' <<<"$out")"
assert_file_exists "default plan is written by the dry-run" "$DP"
out="$(bash "$BATCH" --tier caches --apply --batch-plan "$DP" 2>&1)"
assert_contains "the apply the default plan feeds succeeds" "$out" "Summary: removed=1 failed=0"
assert_file_absent "a clean apply removes the default plan" "$DP"
if [[ ! -d "$(dirname "$DP")" ]]; then
  pass "a clean apply removes the default plan directory"
else
  fail "a clean apply removes the default plan directory" "absent" "$(ls -A "$(dirname "$DP")")"
fi
KEEP="$TEST_TMPDIR/keep/plan"
bash "$BATCH" --tier caches --repo "$(mkrepo applykeep)" --batch-plan "$KEEP" >/dev/null 2>&1
bash "$BATCH" --tier caches --apply --batch-plan "$KEEP" >/dev/null 2>&1
assert_file_exists "an explicit --batch-plan survives a clean apply" "$KEEP"
# An explicit path whose directory looks like a generated one is still the caller's.
LOOKALIKE="$TEST_TMPDIR/state/repo-hygiene/clean-batch.manual/plan"
bash "$BATCH" --tier caches --repo "$(mkrepo applylook)" --batch-plan "$LOOKALIKE" >/dev/null 2>&1
bash "$BATCH" --tier caches --apply --batch-plan "$LOOKALIKE" >/dev/null 2>&1
assert_file_exists "an explicit plan in a generated-looking directory survives a clean apply" "$LOOKALIKE"
LOOK_MANIFESTS=("$(dirname "$LOOKALIKE")"/*.manifest)
assert_file_exists "its manifests survive too" "${LOOK_MANIFESTS[0]}"
# A marker copied outside the state directory (a backed-up plan directory) does not make the plan removable.
STRAY="$TEST_TMPDIR/stray/plan"
bash "$BATCH" --tier caches --repo "$(mkrepo applystray)" --batch-plan "$STRAY" >/dev/null 2>&1
: >"$(dirname "$STRAY")/.default-location"
bash "$BATCH" --tier caches --apply --batch-plan "$STRAY" >/dev/null 2>&1
assert_file_exists "a stray marker outside the state directory leaves the plan" "$STRAY"

help_out="$(bash "$BATCH" --help)"
assert_contains "--help says --batch-plan works with --dry-run" "$help_out" "--batch-plan FILE  with --dry-run"

[[ $FAILED -eq 0 ]] || exit 1
echo "clean-batch.test.sh: all passed"
