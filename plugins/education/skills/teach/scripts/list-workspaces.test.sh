#!/usr/bin/env bash
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/list-workspaces.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

expected_slug() {
  local canonical basename_slug path_hash
  canonical="$(
    (cd "$1" 2>/dev/null && pwd -P) ||
      realpath "$1" 2>/dev/null ||
      readlink -f "$1" 2>/dev/null ||
      printf '%s' "$1"
  )"
  basename_slug="$(basename "$canonical" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
  path_hash="$(printf '%s' "$canonical" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
  printf '%s-%s' "$basename_slug" "$path_hash"
}


rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"


rc=0
OUT=$(bash "$SCRIPT" only-one 2>/dev/null) || rc=$?
assert_exit "one argument exits 2" 2 "$rc"


PROJ="$TEST_TMPDIR/proj/My_Repo"
DATA="$TEST_TMPDIR/data"
mkdir -p "$PROJ" "$DATA"
SLUG="$(expected_slug "$PROJ")"


rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$DATA") || rc=$?
assert_exit "no-match exits 0" 0 "$rc"
assert_eq "no-match prints none" "none" "$OUT"


rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$TEST_TMPDIR/absent") || rc=$?
assert_exit "absent data dir exits 0" 0 "$rc"
assert_eq "absent data dir prints none" "none" "$OUT"


mkdir -p "$DATA/$SLUG/topic/rust-ownership" "$DATA/$SLUG/codebase/auth-flow"
mkdir -p "$DATA/other-project-deadbeef/topic/unrelated"

rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$DATA") || rc=$?
assert_exit "listing exits 0" 0 "$rc"
assert_contains "slug is basename-slugified + hash" "$SLUG" "my-repo-"
assert_contains "lists the topic workspace" "$OUT" "$DATA/$SLUG/topic/rust-ownership/"
assert_contains "lists the codebase workspace" "$OUT" "$DATA/$SLUG/codebase/auth-flow/"
assert_eq "lists exactly the two workspaces" "2" "$(printf '%s\n' "$OUT" | grep -c .)"


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


DOCS_ROOT="$TEST_TMPDIR/Documents dir/Claude Learning"
mkdir -p "$DOCS_ROOT/$SLUG/topic/music-theory"
rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$DOCS_ROOT" "$DATA") || rc=$?
assert_exit "multi-root exits 0" 0 "$rc"
assert_contains "multi-root lists the space-bearing documents root" "$OUT" "$DOCS_ROOT/$SLUG/topic/music-theory/"
assert_contains "multi-root still lists the plugin-data root" "$OUT" "$DATA/$SLUG/topic/rust-ownership/"


rc=0
OUT=$(bash "$SCRIPT" "$PROJ" '${user_config.workspace_root}' "$DATA") || rc=$?
assert_exit "placeholder root exits 0" 0 "$rc"
assert_contains "placeholder root still scans the real roots" "$OUT" "$DATA/$SLUG/topic/rust-ownership/"


rc=0
OUT=$(bash "$SCRIPT" "$PROJ" '${user_config.workspace_root}' '' 2>/dev/null) || rc=$?
assert_exit "all-placeholder roots exit 2" 2 "$rc"


CLOSED_ROOT="$TEST_TMPDIR/closed-root"
mkdir -p "$CLOSED_ROOT/$SLUG/topic/sql-joins" "$CLOSED_ROOT/$SLUG/topic/sailing" \
  "$CLOSED_ROOT/$SLUG/topic/crlf" "$CLOSED_ROOT/$SLUG/topic/drafting" "$CLOSED_ROOT/$SLUG/codebase/no-mission"
printf '# Mission: SQL Joins\n\nStatus: closed\n\n## Result\n\nWrite the reports.\n' \
  >"$CLOSED_ROOT/$SLUG/topic/sql-joins/MISSION.md"
printf '# Mission: Sailing\n\n## Result\n\nThe mission is not closed yet.\n' \
  >"$CLOSED_ROOT/$SLUG/topic/sailing/MISSION.md"
printf '# Mission: CRLF\r\n\r\nStatus: closed\r\n' >"$CLOSED_ROOT/$SLUG/topic/crlf/MISSION.md"
printf '# Mission: Drafting\n\nStatus: closed later\n' >"$CLOSED_ROOT/$SLUG/topic/drafting/MISSION.md"
rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$CLOSED_ROOT") || rc=$?
assert_exit "closed-mission listing exits 0" 0 "$rc"
assert_contains "closed mission is marked" "$OUT" "$CLOSED_ROOT/$SLUG/topic/sql-joins/ (closed)"
assert_contains "CRLF closed mission is marked" "$OUT" "$CLOSED_ROOT/$SLUG/topic/crlf/ (closed)"
assert_eq "only the two closed missions are marked" "2" "$(printf '%s\n' "$OUT" | grep -c '(closed)$')"
assert_eq "active mission stays unmarked" "1" "$(printf '%s\n' "$OUT" | grep -cxF "$CLOSED_ROOT/$SLUG/topic/sailing/")"
assert_eq "a Status value that only starts with closed stays unmarked" "1" "$(printf '%s\n' "$OUT" | grep -cxF "$CLOSED_ROOT/$SLUG/topic/drafting/")"
assert_contains "workspace with no MISSION.md is still listed" "$OUT" "$CLOSED_ROOT/$SLUG/codebase/no-mission/"


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

  rc=0
  OUT=$(HOME="$FAKE_HOME" XDG_STUB_ANSWER="$FAKE_HOME" PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --default-root) || rc=$?
  assert_exit "default-root == HOME is refused (exit 1)" 1 "$rc"
  assert_eq "default-root == HOME prints nothing" "" "$OUT"

  rc=0
  OUT=$(HOME="$FAKE_HOME" XDG_STUB_ANSWER="$FAKE_HOME/absent-docs" PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --default-root) || rc=$?
  assert_exit "absent Documents dir is refused (exit 1)" 1 "$rc"
else
  printf 'SKIP: --default-root xdg cases (non-Linux platform)\n'
fi


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
    printf '# Mission: Old notes\n\nStatus: closed\n' >"$DATA/$LEGACY_SLUG/topic/old-notes/MISSION.md"
    OUT=$(bash "$SCRIPT" "$WORKTREE" "$DATA")
    assert_contains "closed legacy workspace carries both marks" "$OUT" "$DATA/$LEGACY_SLUG/topic/old-notes/ (closed) (legacy worktree slug)"
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
