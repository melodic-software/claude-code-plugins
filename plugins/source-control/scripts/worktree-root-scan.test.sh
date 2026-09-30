#!/usr/bin/env bash
# Regression tests for worktree-root-scan.sh. Black-box: throwaway git
# fixtures (commit signing off, git environment cleared by test-helpers.sh) and
# assertions on the TSV rows and exit codes. The scan is report-only, so every
# case also proves the fixture survives it. No network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/worktree-root-scan.sh"

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

RC=0
OUT=""
ERR=""
# Invoked from an unrelated cwd so a cwd leak would surface.
run_scan() {
  OUT="$(cd "$UNRELATED" && bash "$SCAN" "$@" 2>"$TEST_TMPDIR/err")"
  RC=$?
  ERR="$(cat "$TEST_TMPDIR/err")"
}

# row_for <name> — the row whose path ends in /<name>, else empty.
row_for() {
  printf '%s\n' "$OUT" | awk -F'\t' -v n="/$1" 'substr($1, length($1) - length(n) + 1) == n'
}

REPO_A="$(mkrepo)"
REPO_B="$(mkrepo)"
ROOT="$TEST_TMPDIR/root"
mkdir -p "$ROOT"

git -C "$REPO_A" worktree add -q -b registered "$ROOT/registered" >/dev/null 2>&1
git -C "$REPO_B" worktree add -q -b other "$ROOT/other-live" >/dev/null 2>&1

mkdir "$ROOT/empty-dir"

# A husk is a worktree whose registration git dropped while its main clone is intact.
git -C "$REPO_A" worktree add -q -b husk "$ROOT/husk" >/dev/null 2>&1
rm -rf "$REPO_A/.git/worktrees/husk"
rm -f "$ROOT/husk/README"
git -C "$REPO_A" worktree add -q -b husk-content "$ROOT/husk-content" >/dev/null 2>&1
rm -rf "$REPO_A/.git/worktrees/husk-content"
printf 'x\n' >"$ROOT/husk-content/precious.txt"

# A live worktree whose main clone was moved or deleted still holds its work.
REPO_MOVED="$(mkrepo)"
git -C "$REPO_MOVED" worktree add -q -b moved "$ROOT/moved-main" >/dev/null 2>&1
printf 'x\n' >"$ROOT/moved-main/precious.txt"
mv "$REPO_MOVED" "$REPO_MOVED.away"
REPO_GONE="$(mkrepo)"
git -C "$REPO_GONE" worktree add -q -b gone "$ROOT/deleted-main" >/dev/null 2>&1
rm -rf "$REPO_GONE"
mkdir "$ROOT/module-pointer"
printf 'gitdir: %s\n' "$TEST_TMPDIR/nowhere/.git/modules/sub" >"$ROOT/module-pointer/.git"

mkdir "$ROOT/foreign"
printf 'x\n' >"$ROOT/foreign/notes.txt"
mkdir "$ROOT/hidden-only"
printf 'x\n' >"$ROOT/hidden-only/.env"
mkdir "$TEST_TMPDIR/link-target"
ln -s "$TEST_TMPDIR/link-target" "$ROOT/linked" 2>/dev/null || SKIP_LINK=1
mkdir "$TEST_TMPDIR/real-gitdir"
mkdir "$ROOT/broken-git"
printf 'gitdir: %s\n' "$TEST_TMPDIR/real-gitdir" >"$ROOT/broken-git/.git"
printf 'file\n' >"$ROOT/plain-file"

run_scan --root "$ROOT" --repo-dir "$REPO_A"
assert_exit "scan exits 0" 0 "$RC"
assert_eq "registered dir is skipped" "" "$(row_for registered)"
assert_eq "empty dir is proposed" $'empty-dir\tempty\tyes' \
  "$(row_for empty-dir | sed 's#^.*/##')"
assert_eq "husk holding only its .git file is proposed" $'husk\thusk\tyes' \
  "$(row_for husk | sed 's#^.*/##')"
assert_eq "husk with other content is reported, not proposed" $'husk-content\thusk\tno' \
  "$(row_for husk-content | sed 's#^.*/##')"
assert_eq "worktree whose main clone was moved is unknown, not proposed" $'moved-main\tunknown\tno' \
  "$(row_for moved-main | sed 's#^.*/##')"
assert_eq "worktree whose main clone was deleted is unknown, not proposed" $'deleted-main\tunknown\tno' \
  "$(row_for deleted-main | sed 's#^.*/##')"
assert_eq "a missing gitdir that is no worktree admin dir is unknown" $'module-pointer\tunknown\tno' \
  "$(row_for module-pointer | sed 's#^.*/##')"
assert_eq "foreign content is reported, not proposed" $'foreign\tforeign\tno' \
  "$(row_for foreign | sed 's#^.*/##')"
assert_eq "a dir holding only a hidden file is foreign" $'hidden-only\tforeign\tno' \
  "$(row_for hidden-only | sed 's#^.*/##')"
assert_eq "live worktree of an unlisted repo is live, not proposed" $'other-live\tlive\tno' \
  "$(row_for other-live | sed 's#^.*/##')"
assert_eq "gitdir that exists but is no repository is unknown, not proposed" \
  $'broken-git\tunknown\tno' "$(row_for broken-git | sed 's#^.*/##')"
assert_eq "a plain file is not a directory row" "" "$(row_for plain-file)"
if [[ -z "${SKIP_LINK:-}" ]]; then
  assert_eq "symlink is not proposed" $'linked\tsymlink\tno' \
    "$(row_for linked | sed 's#^.*/##')"
else
  skip_case "symlink not creatable on this host"
fi

run_scan --root "$ROOT" --repo-dir "$REPO_A" --repo-dir "$REPO_B"
assert_eq "second repo registers its worktree" "" "$(row_for other-live)"

assert_file_exists "husk survives the scan" "$ROOT/husk/.git"
assert_file_exists "husk content survives the scan" "$ROOT/husk-content/precious.txt"
assert_file_exists "moved-main worktree content survives the scan" "$ROOT/moved-main/precious.txt"
assert_file_exists "foreign content survives the scan" "$ROOT/foreign/notes.txt"
assert_eq "empty dir survives the scan" yes "$([[ -d "$ROOT/empty-dir" ]] && echo yes || echo no)"

# A directory that cannot be listed may hold work: unknown, never empty.
UNREADABLE_ROOT="$TEST_TMPDIR/unreadable-root"
mkdir -p "$UNREADABLE_ROOT/unreadable"
printf 'x\n' >"$UNREADABLE_ROOT/unreadable/precious.txt"
chmod 000 "$UNREADABLE_ROOT/unreadable"
if ls -A "$UNREADABLE_ROOT/unreadable" >/dev/null 2>&1; then
  skip_case "directory permissions are not enforced on this host"
else
  run_scan --root "$UNREADABLE_ROOT" --repo-dir "$REPO_A"
  assert_eq "a directory that cannot be listed is unknown, not proposed" $'unreadable\tunknown\tno' \
    "$(row_for unreadable | sed 's#^.*/##')"
fi
chmod 755 "$UNREADABLE_ROOT/unreadable"
assert_file_exists "unreadable directory content survives the scan" "$UNREADABLE_ROOT/unreadable/precious.txt"

# A root inside a repository must not turn a plain child into a live one.
NESTED_REPO="$(mkrepo)"
mkdir -p "$NESTED_REPO/wt-root/inner"
printf 'x\n' >"$NESTED_REPO/wt-root/inner/f"
run_scan --root "$NESTED_REPO/wt-root" --repo-dir "$NESTED_REPO"
assert_eq "root inside a repo: child without .git is foreign" $'inner\tforeign\tno' \
  "$(row_for inner | sed 's#^.*/##')"

# Root from worktreeroot.path when --root is omitted.
git -C "$REPO_A" config worktreeroot.path "$ROOT"
run_scan --repo-dir "$REPO_A"
assert_exit "default root resolves through worktreeroot.path" 0 "$RC"
assert_contains "default root scans the configured root" "$OUT" "$ROOT/husk"

# Missing, unresolved and unusable input: non-zero, no rows.
run_scan --root "$TEST_TMPDIR/not-mounted" --repo-dir "$REPO_A"
assert_exit "missing root exits 3" 3 "$RC"
assert_eq "missing root emits no rows" "" "$OUT"
assert_contains "missing root says so" "$ERR" "not a directory"

run_scan --repo-dir "$REPO_B"
assert_exit "unresolvable root exits 3" 3 "$RC"
assert_eq "unresolvable root emits no rows" "" "$OUT"
assert_contains "unresolvable root asks for --root" "$ERR" "pass --root"

run_scan --root "$ROOT" --repo-dir "$TEST_TMPDIR/not-a-repo"
assert_exit "a non-repository --repo-dir exits 5" 5 "$RC"
assert_eq "a non-repository --repo-dir emits no rows" "" "$OUT"

run_scan
assert_exit "no arguments is a usage error" 2 "$RC"
run_scan --bogus
assert_exit "unknown argument is a usage error" 2 "$RC"
run_scan --root
assert_exit "--root without a value is a usage error" 2 "$RC"

[[ $FAILED -eq 0 ]] || exit 1
