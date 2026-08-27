#!/usr/bin/env bash
# Regression tests for worktree-claim.sh (#2882).
# Black-box: throwaway git fixtures, plain `git worktree add` (unlocked),
# helper-shaped lock reasons left untouched, and check-enter on a foreign
# claim. Invoked from an unrelated cwd so a repo-dir leak would surface.
# No network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAIM="$SCRIPT_DIR/worktree-claim.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

TEST_TMPDIR="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR" "$UNRELATED"' EXIT

mkrepo() {
  local repo
  repo="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  git -C "$repo" init -q -b main >/dev/null 2>&1
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  git -C "$repo" config commit.gpgsign false
  printf 'seed\n' >"$repo/README"
  git -C "$repo" add README
  git -C "$repo" commit -q -m seed
  printf '%s' "$repo"
}

# Helper-created reason string — byte-for-byte the format worktree-create.sh
# writes. Tests must not rewrite it (#2882 AC4).
HELPER_REASON='worktree-create.sh: lane active on testhost since 2026-08-15T08:46:04Z; unlock when the owning lane is done'

REPO="$(mkrepo)"
EXT="$TEST_TMPDIR/external"
mkdir -p "$EXT"

run_claim() {
  local rc
  OUT=""
  ERR=""
  OUT="$(cd "$UNRELATED" && bash "$CLAIM" "$@" 2>"$TEST_TMPDIR/err")"
  rc=$?
  ERR="$(cat "$TEST_TMPDIR/err")"
  return "$rc"
}

# --- AC1: plain git worktree add is reported unclaimed ------------------------

git -C "$REPO" worktree add -q "$EXT/wt-plain" -b feat/plain
assert_file_exists "plain git worktree add created the tree" "$EXT/wt-plain/README"

run_claim report --repo-dir "$REPO"
assert_exit "plain add is reported unclaimed (exit 1)" 1 "$?"
assert_contains "report names the unlocked tree UNCLAIMED" "$OUT" "UNCLAIMED"
assert_contains "report names the plain-add path" "$OUT" "$EXT/wt-plain"
assert_not_contains "the main checkout is not listed as unclaimed" "$OUT" "$REPO"$'\t'

# --- claim arms a session-distinct reason ------------------------------------

run_claim claim "$EXT/wt-plain" --repo-dir "$REPO" --session-id sess-aaa
assert_exit "claim of an unlocked tree succeeds" 0 "$?"
assert_contains "claim reason names this script" "$OUT" "worktree-claim.sh"
assert_contains "claim reason names session sess-aaa" "$OUT" "session sess-aaa since"

stanza=$(git -C "$REPO" worktree list --porcelain | awk -v RS= -v p="wt-plain" 'index($0, p)')
assert_contains "porcelain shows the tree locked after claim" "$stanza" "locked"
assert_contains "porcelain reason carries the session id" "$stanza" "sess-aaa"

run_claim report --repo-dir "$REPO"
assert_exit "after claim, report is clean (exit 0)" 0 "$?"
assert_contains "report now lists the tree CLAIMED" "$OUT" "CLAIMED"

# --- AC2: two sessions on one host produce different reasons -----------------

git -C "$REPO" worktree add -q "$EXT/wt-s1" -b feat/s1
git -C "$REPO" worktree add -q "$EXT/wt-s2" -b feat/s2
run_claim claim "$EXT/wt-s1" --repo-dir "$REPO" --session-id host-session-one
r1="$OUT"
run_claim claim "$EXT/wt-s2" --repo-dir "$REPO" --session-id host-session-two
r2="$OUT"
assert_contains "session one reason includes its id" "$r1" "session host-session-one since"
assert_contains "session two reason includes its id" "$r2" "session host-session-two since"
if [[ "$r1" != "$r2" ]]; then
  pass "two concurrent sessions on one host produce different reasons"
else
  fail "two concurrent sessions on one host produce different reasons" "distinct" "$r1"
fi

# --- AC3: check-enter surfaces a foreign live claim --------------------------

run_claim check-enter "$EXT/wt-s1" --repo-dir "$REPO" --session-id host-session-two
assert_exit "foreign check-enter stops (exit 4)" 4 "$?"
assert_contains "foreign claim text reaches the caller" "$ERR" "FOREIGN CLAIM:"
assert_contains "foreign claim names the owning session" "$ERR" "host-session-one"
assert_contains "foreign claim names the path" "$ERR" "$EXT/wt-s1"
assert_contains "foreign claim tells the caller to stop" "$ERR" "do not write here"

run_claim check-enter "$EXT/wt-s1" --repo-dir "$REPO" --session-id host-session-one
assert_exit "owning session check-enter allows (exit 0)" 0 "$?"
assert_contains "owning check-enter echoes the claim" "$OUT" "host-session-one"

# Relative / `.` paths must resolve to the same tree (review: silent allow).
OUT="$(cd "$EXT/wt-s1" && bash "$CLAIM" check-enter . --session-id host-session-two 2>"$TEST_TMPDIR/err")"
assert_exit "check-enter . from inside a foreign-claimed tree stops" 4 "$?"
ERR="$(cat "$TEST_TMPDIR/err")"
assert_contains "relative-dot foreign claim reaches the caller" "$ERR" "FOREIGN CLAIM:"
assert_contains "relative-dot names the owning session" "$ERR" "host-session-one"

OUT="$(cd "$EXT" && bash "$CLAIM" check-enter wt-s1 --repo-dir "$REPO" --session-id host-session-two 2>"$TEST_TMPDIR/err")"
assert_exit "check-enter relative child path against a foreign claim stops" 4 "$?"
ERR="$(cat "$TEST_TMPDIR/err")"
assert_contains "relative-child foreign claim reaches the caller" "$ERR" "FOREIGN CLAIM:"

OUT="$(cd "$EXT" && bash "$CLAIM" check-enter wt-s1 --repo-dir "$REPO" --session-id host-session-one 2>"$TEST_TMPDIR/err")"
assert_exit "relative child path still allows the owning session" 0 "$?"

# Unclaimed entry: create another plain tree and check-enter before claim.
git -C "$REPO" worktree add -q "$EXT/wt-empty" -b feat/empty
run_claim check-enter "$EXT/wt-empty" --repo-dir "$REPO" --session-id anyone
assert_exit "check-enter on an unclaimed tree exits 3" 3 "$?"
assert_contains "unclaimed entry names UNCLAIMED" "$ERR" "UNCLAIMED:"
assert_contains "unclaimed entry names the path" "$ERR" "$EXT/wt-empty"

# Main checkout / unrelated path: nothing to consult.
run_claim check-enter "$REPO" --repo-dir "$REPO" --session-id anyone
assert_exit "check-enter on the main checkout is a no-op" 0 "$?"
run_claim check-enter "$UNRELATED" --repo-dir "$REPO" --session-id anyone
assert_exit "check-enter on a non-worktree path is a no-op" 0 "$?"

# --- AC4: helper-created reason strings are not rewritten --------------------

git -C "$REPO" worktree add -q "$EXT/wt-helper" -b feat/helper
git -C "$REPO" worktree lock --reason "$HELPER_REASON" "$EXT/wt-helper"
run_claim claim "$EXT/wt-helper" --repo-dir "$REPO" --session-id later-session
assert_exit "claim refuses to rewrite a helper reason (exit 4)" 4 "$?"
assert_contains "refusal names the existing helper reason" "$ERR" "worktree-create.sh"

after=$(git -C "$REPO" worktree list --porcelain | awk -v RS= -v p="wt-helper" 'index($0, p)')
assert_contains "helper reason is still present after refused claim" "$after" "$HELPER_REASON"
assert_not_contains "helper reason was not replaced with worktree-claim.sh" "$after" "worktree-claim.sh"

run_claim check-enter "$EXT/wt-helper" --repo-dir "$REPO" --session-id later-session
assert_exit "helper lock is a foreign claim to another session" 4 "$?"
assert_contains "helper claim text reaches the caller" "$ERR" "$HELPER_REASON"

# --- --all-unclaimed locks only unlocked linked trees ------------------------

git -C "$REPO" worktree add -q "$EXT/wt-batch-a" -b feat/batch-a
git -C "$REPO" worktree add -q "$EXT/wt-batch-b" -b feat/batch-b
run_claim claim --all-unclaimed --repo-dir "$REPO" --session-id batch-sess
assert_exit "--all-unclaimed succeeds" 0 "$?"
st_a=$(git -C "$REPO" worktree list --porcelain | awk -v RS= -v p="wt-batch-a" 'index($0, p)')
st_b=$(git -C "$REPO" worktree list --porcelain | awk -v RS= -v p="wt-batch-b" 'index($0, p)')
assert_contains "batch a is locked" "$st_a" "batch-sess"
assert_contains "batch b is locked" "$st_b" "batch-sess"
after_helper=$(git -C "$REPO" worktree list --porcelain | awk -v RS= -v p="wt-helper" 'index($0, p)')
assert_contains "--all-unclaimed left the helper reason intact" "$after_helper" "$HELPER_REASON"

# Idempotent: nothing left to claim.
run_claim claim --all-unclaimed --repo-dir "$REPO" --session-id batch-sess
assert_exit "--all-unclaimed with nothing left is exit 0" 0 "$?"
assert_contains "no-op --all-unclaimed says so" "$ERR" "no unclaimed"

# A lock failure in the batch must not be reported as success (`if ! cmd;
# then rc=$?` used to store 0).
git -C "$REPO" worktree add -q "$EXT/wt-lockfail" -b feat/lockfail

# Root-proof arm (#3378). The chmod fixture below cannot make the admin
# directory unwritable for uid 0, and some filesystems ignore the write bits
# too, so on those platforms it proves nothing. A stub `git` that fails ONLY
# `worktree lock` reproduces the failure on every platform and every uid.
# worktree-claim.sh resolves git through PATH (`git_unlocated` invokes a plain
# `git`), so a stub earlier on PATH intercepts it; the real binary is resolved
# BEFORE the stub dir is prepended, and everything else is delegated to it.
STUB_BIN="$TEST_TMPDIR/stub-bin"
mkdir -p "$STUB_BIN"
REAL_GIT="$(command -v git)"
{
  printf '#!/usr/bin/env bash\n'
  # The invocation is `-C <dir> worktree lock --reason <text> <path>`, so match
  # positionally: the fixture path and the arbitrary reason text must not be
  # able to trip this by carrying the word "lock".
  # shellcheck disable=SC2016  # the $3/$4 belong to the generated stub, not here.
  printf 'if [[ "${3:-}" == worktree && "${4:-}" == lock ]]; then\n'
  printf '  echo "stub git: worktree lock refused" >&2\n'
  printf '  exit 1\n'
  printf 'fi\n'
  printf 'exec %q "$@"\n' "$REAL_GIT"
} >"$STUB_BIN/git"
chmod +x "$STUB_BIN/git"
PATH_SAVED="$PATH"
PATH="$STUB_BIN:$PATH"
run_claim claim --all-unclaimed --repo-dir "$REPO" --session-id batch-stubfail
stub_rc=$?
PATH="$PATH_SAVED"
if [[ "$stub_rc" -ne 0 ]]; then
  pass "--all-unclaimed propagates a lock failure through a stub git (exit $stub_rc)"
else
  fail "--all-unclaimed propagates a lock failure through a stub git" "non-zero" "0"
fi
assert_contains "the failing batch names the tree whose lock failed" "$ERR" "wt-lockfail"

admin="$REPO/.git/worktrees/wt-lockfail"
if [[ ! -d "$admin" ]]; then
  admin="$(git -C "$EXT/wt-lockfail" rev-parse --absolute-git-dir)"
fi
chmod a-w "$admin" 2>/dev/null || true
# Probe whether that chmod actually took. uid 0 writes through a cleared write
# bit, and some filesystems do not enforce it at all; asserting on a fixture
# that did not take reports a product defect which does not exist, which is how
# this case became red noise in root containers. Skip with the reason named
# instead — the posture the sibling suites already use (repo-fleet-hygiene
# audit-fleet, testing cant-fail-scan).
# discriminating-skip-ok: the stub-git arm directly above covers lock-failure
# exit-code propagation on every platform and uid, so this skip vacates no
# discriminating coverage — only the redundant permission-bits fixture.
if : >"$admin/.write-probe" 2>/dev/null; then
  rm -f "$admin/.write-probe"
  chmod u+w "$admin" 2>/dev/null || true
  skip_case "lock-failure permission fixture — chmod a-w left the worktree admin dir writable (uid $(id -u)); the stub-git arm above covers this contract here"
else
  run_claim claim --all-unclaimed --repo-dir "$REPO" --session-id batch-fail
  lockfail_rc=$?
  chmod u+w "$admin" 2>/dev/null || true
  if [[ "$lockfail_rc" -ne 0 ]]; then
    pass "--all-unclaimed preserves a lock failure (exit $lockfail_rc)"
  else
    fail "--all-unclaimed preserves a lock failure" "non-zero" "0"
  fi
fi

# --- usage / environment ------------------------------------------------------

run_claim
assert_exit "no verb is usage (exit 2)" 2 "$?"
run_claim claim --repo-dir "$REPO"
assert_exit "claim without path or --all-unclaimed is usage" 2 "$?"
run_claim check-enter --repo-dir "$REPO"
assert_exit "check-enter without a path is usage" 2 "$?"
run_claim claim "$EXT/wt-plain" --repo-dir "$REPO" --session-id 'bad id'
assert_exit "whitespace session id is usage" 2 "$?"
run_claim report --repo-dir "$UNRELATED"
assert_exit "report outside a git repo is environment (exit 5)" 5 "$?"

# s1 must not match s10
git -C "$REPO" worktree add -q "$EXT/wt-s10" -b feat/s10
run_claim claim "$EXT/wt-s10" --repo-dir "$REPO" --session-id s10
run_claim check-enter "$EXT/wt-s10" --repo-dir "$REPO" --session-id s1
assert_exit "session s1 does not own a session-s10 claim" 4 "$?"

[[ $FAILED -eq 0 ]] || exit 1
