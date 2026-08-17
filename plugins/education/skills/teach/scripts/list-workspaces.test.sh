#!/usr/bin/env bash
# Regression tests for list-workspaces.sh (self-contained — ships with the plugin).
set -uo pipefail

# Fixture isolation: an inherited absolute GIT_DIR outranks -C and would route
# fixture writes into the caller's real .git/config.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE GIT_COMMON_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/list-workspaces.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

# The slug the script must derive, computed here from the SKILL.md spec independently of
# the script, so a drifting implementation fails rather than agreeing with itself.
expected_slug() {
  local canonical basename_slug path_hash
  canonical="$(realpath "$1" 2>/dev/null || readlink -f "$1" 2>/dev/null || printf '%s' "$1")"
  basename_slug="$(basename "$canonical" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
  path_hash="$(printf '%s' "$canonical" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
  printf '%s-%s' "$basename_slug" "$path_hash"
}

# --- Case 1: --help exits 0 with usage ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: wrong argument count is a usage error ---

rc=0
OUT=$(bash "$SCRIPT" only-one 2>/dev/null) || rc=$?
assert_exit "one argument exits 2" 2 "$rc"

# --- Build a fixture project + plugin-data tree ---

PROJ="$TEST_TMPDIR/proj/My_Repo"
DATA="$TEST_TMPDIR/data"
mkdir -p "$PROJ" "$DATA"
SLUG="$(expected_slug "$PROJ")"

# --- Case 3: no workspaces yet => `none`, exit 0 ---

rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$DATA") || rc=$?
assert_exit "no-match exits 0" 0 "$rc"
assert_eq "no-match prints none" "none" "$OUT"

# --- Case 4: a plugin-data dir that does not exist at all => `none`, exit 0 ---

rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$TEST_TMPDIR/absent") || rc=$?
assert_exit "absent data dir exits 0" 0 "$rc"
assert_eq "absent data dir prints none" "none" "$OUT"

# --- Case 5: slug-hash dir listing ---
# Slug is basename-lowercased-slugified + `-` + 8 hex; `My_Repo` exercises both the
# case fold and the non-alphanumeric replacement.

mkdir -p "$DATA/$SLUG/topic/rust-ownership" "$DATA/$SLUG/codebase/auth-flow"
# A workspace belonging to a DIFFERENT project must not leak into this project's listing.
mkdir -p "$DATA/other-project-deadbeef/topic/unrelated"

rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$DATA") || rc=$?
assert_exit "listing exits 0" 0 "$rc"
assert_contains "slug is basename-slugified + hash" "$SLUG" "my-repo-"
assert_contains "lists the topic workspace" "$OUT" "$DATA/$SLUG/topic/rust-ownership/"
assert_contains "lists the codebase workspace" "$OUT" "$DATA/$SLUG/codebase/auth-flow/"
assert_eq "lists exactly the two workspaces" "2" "$(printf '%s\n' "$OUT" | grep -c .)"

# --- Case 6: symlinked project resolves to the same workspace as the real path ---
# Canonicalization happens BEFORE the slug is derived, so an alias basename cannot split
# the workspace. Skipped where the OS refuses real symlinks (Windows without developer
# mode: Git Bash silently copies instead of linking).

LINK="$TEST_TMPDIR/proj/aliased-name"
if ln -s "$PROJ" "$LINK" 2>/dev/null && [[ -L "$LINK" ]]; then
  rc=0
  OUT=$(bash "$SCRIPT" "$LINK" "$DATA") || rc=$?
  assert_exit "symlinked project exits 0" 0 "$rc"
  assert_eq "symlinked project resolves to the real path's slug" "$SLUG" "$(expected_slug "$LINK")"
  assert_contains "symlinked project lists the same workspaces" "$OUT" "$DATA/$SLUG/topic/rust-ownership/"
else
  printf 'SKIP: symlink cases (this OS/filesystem does not support real symlinks)\n'
fi

# --- Case 7: multi-root scan — workspaces under every supplied root are listed ---
# The root may carry spaces (a Documents path usually does); the array glob must survive it.

DOCS_ROOT="$TEST_TMPDIR/Documents dir/Claude Learning"
mkdir -p "$DOCS_ROOT/$SLUG/topic/music-theory"
rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$DOCS_ROOT" "$DATA") || rc=$?
assert_exit "multi-root exits 0" 0 "$rc"
assert_contains "multi-root lists the space-bearing documents root" "$OUT" "$DOCS_ROOT/$SLUG/topic/music-theory/"
assert_contains "multi-root still lists the plugin-data root" "$OUT" "$DATA/$SLUG/topic/rust-ownership/"

# --- Case 8: a surviving user_config placeholder root is skipped as unset ---
# The skill body passes body-resolved roots; a literal `${user_config...}` means unset and
# must be filtered, not globbed as a path.

rc=0
OUT=$(bash "$SCRIPT" "$PROJ" '${user_config.workspace_root}' "$DATA") || rc=$?
assert_exit "placeholder root exits 0" 0 "$rc"
assert_contains "placeholder root still scans the real roots" "$OUT" "$DATA/$SLUG/topic/rust-ownership/"

# --- Case 9: ALL roots unset/placeholder is a usage error (exit 2), not a quiet none ---
# Exit 2 tells the skill the probe is broken (glob manually); `none` means genuinely empty.

rc=0
OUT=$(bash "$SCRIPT" "$PROJ" '${user_config.workspace_root}' '' 2>/dev/null) || rc=$?
assert_exit "all-placeholder roots exit 2" 2 "$rc"

# --- Case 10: --default-root honors xdg-user-dir and the ≠ $HOME guard (Linux path) ---
# Stubbed xdg-user-dir + fake HOME; skipped on non-Linux platforms where the script takes
# the Darwin/Windows branch instead of consulting xdg-user-dir.

if [[ "$(uname -s)" == "Linux" ]]; then
  FAKE_HOME="$TEST_TMPDIR/home"
  FAKE_DOCS="$FAKE_HOME/My Documents"
  STUB_BIN="$TEST_TMPDIR/stub-bin"
  mkdir -p "$FAKE_HOME" "$FAKE_DOCS" "$STUB_BIN"
  cat >"$STUB_BIN/xdg-user-dir" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$XDG_STUB_ANSWER"
STUB
  chmod +x "$STUB_BIN/xdg-user-dir"

  rc=0
  OUT=$(HOME="$FAKE_HOME" XDG_STUB_ANSWER="$FAKE_DOCS" PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --default-root) || rc=$?
  assert_exit "default-root with configured Documents exits 0" 0 "$rc"
  assert_eq "default-root appends Claude Learning" "$FAKE_DOCS/Claude Learning" "$OUT"

  # Unconfigured xdg-user-dir echoes $HOME itself — the guard must refuse it.
  rc=0
  OUT=$(HOME="$FAKE_HOME" XDG_STUB_ANSWER="$FAKE_HOME" PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --default-root) || rc=$?
  assert_exit "default-root == HOME is refused (exit 1)" 1 "$rc"
  assert_eq "default-root == HOME prints nothing" "" "$OUT"

  # A Documents answer that does not exist on disk is refused — never silently created.
  rc=0
  OUT=$(HOME="$FAKE_HOME" XDG_STUB_ANSWER="$FAKE_HOME/absent-docs" PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --default-root) || rc=$?
  assert_exit "absent Documents dir is refused (exit 1)" 1 "$rc"
else
  printf 'SKIP: --default-root xdg cases (non-Linux platform)\n'
fi

# --- Case 11: a linked git worktree hoists to the main repo's slug; the old per-worktree
# slug is still scanned and labeled legacy. Skipped when git is unavailable. ---

if command -v git >/dev/null 2>&1; then
  MAIN_REPO="$TEST_TMPDIR/wt/main-repo"
  WORKTREE="$TEST_TMPDIR/wt/feature-copy"
  mkdir -p "$MAIN_REPO"
  git -C "$MAIN_REPO" init -q -b main 2>/dev/null || git -C "$MAIN_REPO" init -q
  git -C "$MAIN_REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  if git -C "$MAIN_REPO" worktree add -q "$WORKTREE" 2>/dev/null; then
    MAIN_SLUG="$(expected_slug "$MAIN_REPO")"
    LEGACY_SLUG="$(expected_slug "$WORKTREE")"
    mkdir -p "$DATA/$MAIN_SLUG/codebase/auth-flow" "$DATA/$LEGACY_SLUG/topic/old-notes"
    rc=0
    OUT=$(bash "$SCRIPT" "$WORKTREE" "$DATA") || rc=$?
    assert_exit "worktree invocation exits 0" 0 "$rc"
    assert_contains "worktree lists the MAIN repo's workspace" "$OUT" "$DATA/$MAIN_SLUG/codebase/auth-flow/"
    assert_contains "old per-worktree workspace is labeled legacy" "$OUT" "$DATA/$LEGACY_SLUG/topic/old-notes/ (legacy worktree slug)"
  else
    printf 'SKIP: worktree case (git worktree add failed here)\n'
  fi
else
  printf 'SKIP: worktree case (git unavailable)\n'
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
