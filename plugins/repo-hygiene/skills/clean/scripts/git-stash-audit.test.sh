#!/usr/bin/env bash
# Tests for git-stash-audit.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

AUDIT="$SCRIPT_DIR/git-stash-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

rc=0
bash "$AUDIT" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

# A no-op gh stub keeps the audit deterministic and offline.
STUB_BIN="$TEST_TMPDIR/stub-bin"
mkdir -p "$STUB_BIN"
printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB_BIN/gh"
chmod +x "$STUB_BIN/gh"

# Empty repo: no stashes → count 0, never an error, exit 0.
# `-b main` pins the initial branch so the assertions below hold on machines where
# `git init` still defaults to `master`.
git init -q -b main "$TEST_TMPDIR/empty"
git -C "$TEST_TMPDIR/empty" config user.email "t@example.com"
git -C "$TEST_TMPDIR/empty" config user.name "Test"
echo x >"$TEST_TMPDIR/empty/x"
git -C "$TEST_TMPDIR/empty" add x
git -C "$TEST_TMPDIR/empty" commit -qm init
empty_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$TEST_TMPDIR/empty' && bash '$AUDIT'")"
assert_contains "emits stash store key" "$empty_out" "StashStore:"
assert_contains "zero stash count" "$empty_out" "Stash count: 0"
assert_contains "summary line" "$empty_out" "Summary: stashes=0"

# Populated repo: a stash on the default branch is live WIP (never superseded),
# a stash whose source branch merged into origin/<default> is flagged possibly
# superseded — but only ever as advisory, never dropped.
REPO="$TEST_TMPDIR/repo"
git init -q --bare "$TEST_TMPDIR/origin.git"
git init -q -b main "$REPO"
git -C "$REPO" config user.email "t@example.com"
git -C "$REPO" config user.name "Test"
echo a >"$REPO/a"
git -C "$REPO" add a
git -C "$REPO" commit -qm init
git -C "$REPO" remote add origin "$TEST_TMPDIR/origin.git"
git -C "$REPO" push -q origin HEAD:main
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
echo change >"$REPO/a"
git -C "$REPO" stash push -q -m "live wip on main"
git -C "$REPO" checkout -q -b feat/done
echo b >"$REPO/b"
git -C "$REPO" add b
git -C "$REPO" commit -qm b
git -C "$REPO" checkout -q main
git -C "$REPO" merge -q feat/done
git -C "$REPO" push -q origin main
git -C "$REPO" checkout -q feat/done
echo edit >>"$REPO/b"
git -C "$REPO" stash push -q -m "pre-merge backup"
git -C "$REPO" checkout -q main
out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$REPO' && bash '$AUDIT'")"
assert_contains "counts both stashes" "$out" "Stash count: 2"
assert_contains "emits diffstat" "$out" "Diffstat:"
assert_contains "attributes source branch" "$out" "Source branch: feat/done"
assert_contains "merged source flagged superseded" "$out" "possibly superseded"
# A stash on the default branch is live WIP, never flagged superseded.
assert_contains "main stash stays review" "$out" "review — confirm with the user"
assert_contains "never auto-dropped disclaimer" "$out" "never auto-dropped"
# Each stash carries its stable commit id — the safe handle for multi-drop, since
# the stash@{n} selector renumbers after every drop.
sha0="$(git -C "$REPO" rev-parse "stash@{0}" 2>/dev/null)"
assert_contains "emits stable stash commit id" "$out" "Commit: $sha0"

# --- PR map status: the stash audit is the second call site of the same lookup ---
# It was capped and silenced identically to the branch audit, and fixing only one
# site would leave half the bug. The superseded advisory is derived from PR state,
# so a short or missing map silently withholds it.
assert_contains "failed lookup is announced, not swallowed" "$out" "PRDataUnavailable:"
assert_not_contains "failed lookup reports no count" "$out" "PRCount:"

if command -v jq >/dev/null 2>&1; then
  PR_BIN="$TEST_TMPDIR/pr-bin"
  mkdir -p "$PR_BIN"
  cat >"$PR_BIN/gh" <<'PRGH'
#!/usr/bin/env bash
case "$*" in
  *pr\ list*)
    printf '%s\n' '[{"headRefName":"feat/done","state":"MERGED","number":7}]'
    ;;
  *) exit 1 ;;
esac
PRGH
  chmod +x "$PR_BIN/gh"
  pr_out="$(PATH="$PR_BIN:$PATH" bash -c "cd '$REPO' && bash '$AUDIT'")"
  assert_contains "complete map reports its size" "$pr_out" "PRCount: 1"
  assert_not_contains "complete map is not flagged truncated" "$pr_out" "PRDataTruncated:"
  assert_contains "PR state still reaches the advisory" "$pr_out" "#7 MERGED"

  trunc_out="$(PATH="$PR_BIN:$PATH" CLEAN_PR_LIST_LIMIT=1 bash -c "cd '$REPO' && bash '$AUDIT'")"
  assert_contains "truncated map is announced here too" "$trunc_out" "PRDataTruncated:"

  EMPTY_BIN="$TEST_TMPDIR/empty-pr-bin"
  mkdir -p "$EMPTY_BIN"
  cat >"$EMPTY_BIN/gh" <<'EMPTYGH'
#!/usr/bin/env bash
case "$*" in
  *pr\ list*) printf '%s\n' '[]' ;;
  *) exit 1 ;;
esac
EMPTYGH
  chmod +x "$EMPTY_BIN/gh"
  empty_pr_out="$(PATH="$EMPTY_BIN:$PATH" bash -c "cd '$REPO' && bash '$AUDIT'")"
  assert_contains "a repo with no PRs reports a real count" "$empty_pr_out" "PRCount: 0"
  assert_not_contains "a repo with no PRs is not called unavailable" "$empty_pr_out" "PRDataUnavailable:"

  # --- PR map: cannot create the outfile is unavailable, not a count ----------
  # Same helper, second call site: a successful gh lookup must not report a
  # complete map when the file was never created (invalid TMPDIR / mktemp
  # fallback). Capture stderr so a missing-file redirect would show up.
  mapfail_out="$(
    PATH="$PR_BIN:$PATH" TMPDIR="$TEST_TMPDIR/no-such-tmpdir" \
      bash -c "cd '$REPO' && bash '$AUDIT'" 2>&1
  )"
  assert_contains "unwritable TMPDIR is unavailable here too" "$mapfail_out" "PRDataUnavailable:"
  assert_not_contains "unwritable TMPDIR reports no count here too" "$mapfail_out" "PRCount:"
fi

# --- fleet form: --repo / --repos-from / --skip / --skip-from -------------------
# Two repositories plus a linked worktree of the first; the first holds a stash.
FL="$TEST_TMPDIR/fleet"
mkdir -p "$FL"
for r in one two; do
  git init -q -b main "$FL/$r"
  git -C "$FL/$r" config user.email "t@example.com"
  git -C "$FL/$r" config user.name "Test"
  echo x >"$FL/$r/x"
  git -C "$FL/$r" add x
  git -C "$FL/$r" commit -qm init
done
echo y >"$FL/one/x"
git -C "$FL/one" stash -q
git -C "$FL/one" worktree add -q -b feat/linked "$FL/one-linked"
fleet_audit() { PATH="$STUB_BIN:$PATH" bash "$AUDIT" "$@" 2>/dev/null; }

plain_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$FL/one' && bash '$AUDIT'")"
assert_not_contains "no selection flag: no Repo block" "$plain_out" "Repo: "
assert_not_contains "no selection flag: no fleet summary" "$plain_out" "FleetSummary:"

fleet_out="$(fleet_audit --repo "$FL/one" "$FL/one-linked" "$FL/two")"
assert_contains "fleet: first repo is a block with its stash" "$fleet_out" "Repo: $FL/one
StashStore: $FL/one/.git"
assert_contains "fleet: second repo is a block" "$fleet_out" "Repo: $FL/two
StashStore: $FL/two/.git"
assert_contains "fleet: a linked worktree shares the stash store and is skipped" "$fleet_out" "Repo: $FL/one-linked
Outcome: skipped
Reason: shares a git common dir with an audited repo"
assert_contains "fleet: summary counts" "$fleet_out" "FleetSummary: repos=3 audited=2 skipped=0 duplicate=1 blocked=0 failed=0"
stash_lines="$(grep -c '^Stash: ' <<<"$fleet_out")"
if [[ "$stash_lines" == 1 ]]; then pass "fleet: the shared stash is listed once"; else fail "fleet: the shared stash is listed once" 1 "$stash_lines"; fi

block_one="$(awk -v r="Repo: $FL/one" '$0 == r { on = 1; next } on && $0 == "---" { exit } on' <<<"$fleet_out")"
if [[ "$block_one" == "$plain_out" ]]; then pass "fleet: a repo's block equals its single-repo output"; else fail "fleet: a repo's block equals its single-repo output" "$plain_out" "$block_one"; fi

printf '%s\r\n%s\n\n' "$FL/one" "$FL/two" >"$FL/list.txt"
assert_contains "repos-from FILE audits both" "$(fleet_audit --repos-from "$FL/list.txt")" "audited=2"
assert_contains "repos-from - audits stdin" "$(printf '%s\n' "$FL/two" | fleet_audit --repos-from -)" "audited=1"

skip_out="$(fleet_audit --repo "$FL/one" "$FL/two" --skip two --skip nowhere)"
assert_contains "skip list reports the skipped repo" "$skip_out" "Repo: $FL/two
Outcome: skipped
Reason: skip-list (two)"
assert_contains "an entry that matched nothing is reported" "$skip_out" "UnmatchedSkip: nowhere"
assert_contains "skip summary" "$skip_out" "audited=1 skipped=1"
printf '%s\n' "$FL/one" >"$FL/skips.txt"
assert_contains "skip-from FILE skips the listed repo" "$(fleet_audit --repo "$FL/one" "$FL/two" --skip-from "$FL/skips.txt")" "Reason: skip-list ($FL/one)"

mkdir -p "$FL/plain-dir"
bad_out="$(fleet_audit --repo "$FL/missing" "$FL/plain-dir" "$FL/two")"
assert_contains "missing path is blocked" "$bad_out" "Repo: $FL/missing
Outcome: blocked
Reason: not-a-directory"
assert_contains "the fleet continues past blocked repos" "$bad_out" "audited=1 skipped=0 duplicate=0 blocked=2 failed=0"

for bad in "--repo" "--repos-from" "--skip two" "--repos-from $FL/no-such-list.txt" "--capture-file x" "--bogus"; do
  rc=0
  # shellcheck disable=SC2086
  PATH="$STUB_BIN:$PATH" bash "$AUDIT" $bad >/dev/null 2>&1 || rc=$?
  assert_exit "usage error exits 2: $bad" 2 "$rc"
done
: >"$FL/empty.txt"
rc=0
PATH="$STUB_BIN:$PATH" bash "$AUDIT" --repos-from "$FL/empty.txt" >/dev/null 2>&1 || rc=$?
assert_exit "an empty repo list exits 2" 2 "$rc"
assert_contains "--help documents --repo" "$(bash "$AUDIT" --help)" "--repo DIR..."

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-stash-audit.sh tests passed"
