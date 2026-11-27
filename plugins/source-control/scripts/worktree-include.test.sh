#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INCLUDE="$SCRIPT_DIR/worktree-include.sh"

FAILED=0
# shellcheck disable=SC2034
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

mkfixture() {
  local repo
  repo="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  git init -q -b main "$repo" >/dev/null 2>&1
  git -C "$repo" config user.email t@t.t
  git -C "$repo" config user.name t
  git -C "$repo" config commit.gpgsign false
  printf 'seed\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm init
  printf '%s' "$repo"
}

run_inc() {
  local rc
  OUT=""
  ERR=""
  OUT="$(bash "$INCLUDE" "$@" 2>"$TEST_TMPDIR/err")"
  rc=$?
  ERR="$(cat "$TEST_TMPDIR/err")"
  return "$rc"
}

REPO="$(mkfixture)"
cat >"$REPO/.gitignore" <<'EOF'
.work/
*.env
dir with spaces/
sub/
EOF
printf '/root-only.env\n.work/**/NOTES.md\ndir with spaces/*.txt\ntracked.env\n*.env' >"$REPO/.worktreeinclude"
printf 'tracked-content\n' >"$REPO/tracked.env"
git -C "$REPO" add -f .gitignore .worktreeinclude tracked.env
git -C "$REPO" commit -qm "add gitignore, worktreeinclude, tracked.env"

mkdir -p "$REPO/.work/a/b" "$REPO/sub" "$REPO/dir with spaces"
printf 'root-val\n' >"$REPO/root-only.env"
printf 'nested-val\n' >"$REPO/sub/root-only.env"
printf 'deep-notes\n' >"$REPO/.work/a/b/NOTES.md"
printf 'ignored-unmatched\n' >"$REPO/.work/a/b/OTHER.md"
printf 'spaced-val\n' >"$REPO/dir with spaces/my file.txt"
printf 'unignored-loose\n' >"$REPO/loose.txt"
printf 'plain-env\n' >"$REPO/app.env"

WT="$TEST_TMPDIR/wt-1"
git -C "$REPO" worktree add -q -b feat/inc "$WT" main >/dev/null 2>&1

run_inc copy --from "$REPO" --to "$WT"
assert_exit "copy exits 0" 0 "$?"
assert_file_exists "copy: leading / pattern copied at root" "$WT/root-only.env"
assert_file_exists "copy: ** pattern copied at nested depth" "$WT/.work/a/b/NOTES.md"
assert_file_exists "copy: spaces in dir and filename copied" "$WT/dir with spaces/my file.txt"
assert_file_exists "copy: final line without trailing newline (*.env) copied" "$WT/app.env"
assert_file_exists "copy: nested .env matched by *.env copied" "$WT/sub/root-only.env"
assert_file_absent "copy: gitignored-but-unmatched file skipped" "$WT/.work/a/b/OTHER.md"
assert_file_absent "copy: unignored file never copied" "$WT/loose.txt"

REPO_LEAD="$(mkfixture)"
printf '*.env\n' >"$REPO_LEAD/.gitignore"
printf '/root-only.env' >"$REPO_LEAD/.worktreeinclude"
git -C "$REPO_LEAD" add .gitignore .worktreeinclude
git -C "$REPO_LEAD" commit -qm "leading slash only"
mkdir -p "$REPO_LEAD/sub"
printf 'root\n' >"$REPO_LEAD/root-only.env"
printf 'sub\n' >"$REPO_LEAD/sub/root-only.env"
WT_LEAD="$TEST_TMPDIR/wt-lead"
git -C "$REPO_LEAD" worktree add -q -b feat/lead "$WT_LEAD" main >/dev/null 2>&1
run_inc copy --from "$REPO_LEAD" --to "$WT_LEAD"
assert_exit "leading-slash copy exits 0" 0 "$?"
assert_file_exists "leading /: root file copied" "$WT_LEAD/root-only.env"
assert_file_absent "leading /: nested file with same name is NOT copied" "$WT_LEAD/sub/root-only.env"

run_inc diff "$WT" --main-root "$REPO"
assert_exit "diff right after copy exits 0 (clean)" 0 "$?"
assert_eq "diff right after copy prints nothing" "" "$OUT"

printf 'edited-tracked\n' >"$WT/tracked.env"
run_inc diff "$WT" --main-root "$REPO"
assert_exit "tracked file matching .worktreeinclude is excluded from diff (exit 0)" 0 "$?"
git -C "$WT" checkout -- tracked.env >/dev/null 2>&1

printf 'modified-notes\n' >"$WT/.work/a/b/NOTES.md"
printf 'brand-new-env\n' >"$WT/new-in-wt.env"
rm -f "$WT/app.env"

REPO_PHYS="$(physical_dir "$REPO")"
run_inc diff "$WT" --main-root "$REPO"
assert_exit "diff with MODIFIED/NEW/ABSENT exits 1" 1 "$?"
assert_contains "diff reports MODIFIED TSV row" "$OUT" $'MODIFIED\t.work/a/b/NOTES.md\t'"$REPO_PHYS/.work/a/b/NOTES.md"
assert_contains "diff reports NEW TSV row" "$OUT" $'NEW\tnew-in-wt.env\t'"$REPO_PHYS/new-in-wt.env"
assert_contains "diff reports ABSENT TSV row" "$OUT" $'ABSENT\tapp.env\t'"$REPO_PHYS/app.env"

run_inc diff "$WT" --main-root "$REPO" --worktree-only
assert_exit "diff --worktree-only exits 1 on MODIFIED/NEW" 1 "$?"
assert_contains "--worktree-only includes MODIFIED" "$OUT" $'MODIFIED\t.work/a/b/NOTES.md\t'
assert_contains "--worktree-only includes NEW" "$OUT" $'NEW\tnew-in-wt.env\t'
assert_not_contains "--worktree-only omits ABSENT" "$OUT" $'ABSENT\t'

cp -p "$REPO/.work/a/b/NOTES.md" "$WT/.work/a/b/NOTES.md"
rm -f "$WT/new-in-wt.env"
run_inc diff "$WT" --main-root "$REPO" --worktree-only
assert_exit "--worktree-only exits 0 when only ABSENT exists" 0 "$?"
run_inc diff "$WT" --main-root "$REPO"
assert_exit "full diff still exits 1 when ABSENT exists" 1 "$?"

printf 'modified-notes\n' >"$WT/.work/a/b/NOTES.md"
printf 'brand-new-env\n' >"$WT/new-in-wt.env"

run_inc diff "$WT" --main-root "$REPO" --unified
assert_exit "diff --unified exits 1 on diffs" 1 "$?"
assert_contains "diff --unified shows modified hunk" "$OUT" "+modified-notes"
assert_contains "diff --unified shows new file hunk" "$OUT" "+brand-new-env"
assert_contains "diff --unified shows absent file hunk" "$OUT" "-plain-env"

run_inc diff "$WT"
assert_exit "diff without --main-root derives main root and exits 1" 1 "$?"
assert_contains "diff without --main-root finds MODIFIED" "$OUT" $'MODIFIED\t.work/a/b/NOTES.md\t'

run_inc sync-back "$WT" --copy "../escape.env"
assert_exit "sync-back rejects .. traversal (exit 2)" 2 "$?"
assert_contains "sync-back traversal error names invalid path" "$ERR" "invalid path"
run_inc sync-back "$WT" --copy "/etc/passwd"
assert_exit "sync-back rejects absolute path (exit 2)" 2 "$?"
run_inc sync-back "$WT" --copy "tracked.env"
assert_exit "sync-back rejects tracked file (exit 2)" 2 "$?"
run_inc sync-back "$WT" --copy ".work/a/b/OTHER.md"
assert_exit "sync-back rejects gitignored-but-unmatched file (exit 2)" 2 "$?"
run_inc sync-back "$WT" --remove "README.md"
assert_exit "sync-back rejects --remove on tracked file (exit 2)" 2 "$?"
assert_file_exists "rejected --remove leaves tracked file intact" "$REPO/README.md"

run_inc sync-back "$WT" --copy "new-in-wt.env" --copy "../evil"
assert_exit "sync-back rejects batch with any invalid path (exit 2)" 2 "$?"
assert_file_absent "rejected batch does not partially copy valid file" "$REPO/new-in-wt.env"

run_inc sync-back "$WT" --copy ".work/a/b/NOTES.md" --copy "new-in-wt.env" --remove "app.env"
assert_exit "valid sync-back exits 0" 0 "$?"
assert_eq "sync-back updated modified file in main" "modified-notes" "$(cat "$REPO/.work/a/b/NOTES.md")"
assert_eq "sync-back copied new file to main" "brand-new-env" "$(cat "$REPO/new-in-wt.env")"
assert_file_absent "sync-back removed absent file from main" "$REPO/app.env"

run_inc diff "$WT" --main-root "$REPO"
assert_exit "diff after sync-back is clean (exit 0)" 0 "$?"

run_inc diff "$TEST_TMPDIR/does-not-exist"
assert_exit "diff on nonexistent worktree fails closed (exit 3)" 3 "$?"

REPO_NONE="$(mkfixture)"
WT_NONE="$TEST_TMPDIR/wt-none"
git -C "$REPO_NONE" worktree add -q -b feat/none "$WT_NONE" main >/dev/null 2>&1
run_inc copy --from "$REPO_NONE" --to "$WT_NONE"
assert_exit "copy without .worktreeinclude exits 0" 0 "$?"
assert_eq "copy without .worktreeinclude reports 0" "0" "$OUT"
run_inc diff "$WT_NONE"
assert_exit "diff without .worktreeinclude exits 0" 0 "$?"

OUTSIDE_DIR="$TEST_TMPDIR/outside-target"
mkdir -p "$OUTSIDE_DIR"
printf 'keep-outside\n' >"$OUTSIDE_DIR/secret.env"
REPO_SYM="$(mkfixture)"
printf '*.env\n.work/**\n' >"$REPO_SYM/.gitignore"
printf '*.env\n.work/**/*.md\n' >"$REPO_SYM/.worktreeinclude"
git -C "$REPO_SYM" add .gitignore .worktreeinclude
git -C "$REPO_SYM" commit -q -m "add include rules for symlink test"
ln -s "$OUTSIDE_DIR/secret.env" "$REPO_SYM/linked-src.env"
printf 'real\n' >"$REPO_SYM/real.env"
WT_SYM="$TEST_TMPDIR/wt-sym"
git -C "$REPO_SYM" worktree add -q -b feat/sym "$WT_SYM" main >/dev/null 2>&1

run_inc copy --from "$REPO_SYM" --to "$WT_SYM"
assert_exit "copy skips symlinked source cleanly" 0 "$?"
assert_eq "copy counts only regular non-symlink source" "1" "$OUT"
assert_file_absent "copy does not materialize symlinked source" "$WT_SYM/linked-src.env"

printf 'overwrite-attempt\n' >"$WT_SYM/dest-link.env"
ln -s "$OUTSIDE_DIR/secret.env" "$REPO_SYM/dest-link.env"
run_inc sync-back "$WT_SYM" --copy "dest-link.env"
assert_exit "sync-back rejects symlinked destination file (exit 2)" 2 "$?"
assert_eq "rejected symlink destination leaves outside file untouched" "keep-outside" "$(cat "$OUTSIDE_DIR/secret.env")"

mkdir -p "$WT_SYM/.work/sub"
printf 'escape-parent\n' >"$WT_SYM/.work/sub/escape.md"
mkdir -p "$REPO_SYM/.work"
ln -s "$OUTSIDE_DIR" "$REPO_SYM/.work/sub"
run_inc sync-back "$WT_SYM" --copy ".work/sub/escape.md"
assert_exit "sync-back rejects symlinked parent directory under main root (exit 2)" 2 "$?"
assert_file_absent "rejected symlinked parent writes nothing outside main root" "$OUTSIDE_DIR/escape.md"

REPO_BADINC="$(mkfixture)"
mkdir -p "$REPO_BADINC/.worktreeinclude"
WT_BADINC="$TEST_TMPDIR/wt-badinc"
git -C "$REPO_BADINC" worktree add -q -b feat/badinc "$WT_BADINC" main >/dev/null 2>&1
run_inc copy --from "$REPO_BADINC" --to "$WT_BADINC"
assert_exit "copy fails closed when .worktreeinclude is a directory (exit 3)" 3 "$?"
run_inc diff "$WT_BADINC"
assert_exit "diff fails closed when .worktreeinclude is a directory (exit 3)" 3 "$?"
run_inc sync-back "$WT_BADINC" --copy "app.env"
assert_exit "sync-back fails closed when .worktreeinclude is a directory (exit 3)" 3 "$?"

count_objects() {
  find "$1/.git/objects" -type f ! -name 'packs' 2>/dev/null | wc -l | tr -d ' '
}

REPO_CI="$(mkfixture)"
printf '*.env\n' >"$REPO_CI/.gitignore"
printf '*.env\n' >"$REPO_CI/.worktreeinclude"
git -C "$REPO_CI" add .gitignore .worktreeinclude
git -C "$REPO_CI" commit -qm "include env files"
printf 'main-notes-v1\n' >"$REPO_CI/notes.env"
printf 'same-size-a\n' >"$REPO_CI/keys.env"
printf 'doomed\n' >"$REPO_CI/gone.env"
WT_CI="$TEST_TMPDIR/wt-ci"
git -C "$REPO_CI" worktree add -q -b feat/ci "$WT_CI" main >/dev/null 2>&1
WT_CI_GITDIR="$(git -C "$WT_CI" rev-parse --absolute-git-dir)"

OBJECTS_BEFORE="$(count_objects "$REPO_CI")"
run_inc copy --from "$REPO_CI" --to "$WT_CI"
assert_exit "carried manifest: copy exits 0" 0 "$?"
assert_file_exists "carried manifest: copy writes carried.index in the worktree gitdir" "$WT_CI_GITDIR/carried.index"
assert_eq "carried-index: copy adds no object to the object store" "$OBJECTS_BEFORE" "$(count_objects "$REPO_CI")"

printf 'main-notes-v2-edited-after-copy\n' >"$REPO_CI/notes.env"
run_inc diff "$WT_CI" --main-root "$REPO_CI" --worktree-only
assert_exit "carried-index: untouched copy passes after main's copy changes" 0 "$?"

rm -f "$WT_CI/gone.env"
run_inc diff "$WT_CI" --main-root "$REPO_CI" --worktree-only
assert_exit "carried manifest: a carried file deleted in the worktree is no loss" 0 "$?"

printf 'worktree-edit\n' >"$WT_CI/notes.env"
run_inc diff "$WT_CI" --main-root "$REPO_CI" --worktree-only
assert_exit "carried manifest: edited copy exits 1" 1 "$?"
assert_contains "carried-index: edited copy is MODIFIED" "$OUT" $'MODIFIED\tnotes.env\t'

cp -p "$WT_CI/keys.env" "$TEST_TMPDIR/keys.ref"
sleep 1
printf 'same-size-b\n' >"$WT_CI/keys.env"
touch -r "$TEST_TMPDIR/keys.ref" "$WT_CI/keys.env"
run_inc diff "$WT_CI" --main-root "$REPO_CI" --worktree-only
assert_contains "carried-index: same-size edit with a preserved mtime is MODIFIED" "$OUT" $'MODIFIED\tkeys.env\t'

run_inc sync-back "$WT_CI" --main-root "$REPO_CI" --copy notes.env
assert_exit "carried-index: sync-back refuses when main's file changed since the copy" 2 "$?"
assert_eq "carried manifest: refused sync-back leaves main's newer edit" "main-notes-v2-edited-after-copy" "$(cat "$REPO_CI/notes.env")"

run_inc sync-back "$WT_CI" --main-root "$REPO_CI" --copy keys.env
assert_exit "carried manifest: sync-back copies a file main left unchanged" 0 "$?"
run_inc diff "$WT_CI" --main-root "$REPO_CI" --worktree-only
assert_not_contains "carried manifest: a synced-back file no longer reads MODIFIED" "$OUT" $'\tkeys.env\t'

printf 'fresh\n' >"$WT_CI/fresh.env"
run_inc diff "$WT_CI" --main-root "$REPO_CI" --worktree-only
assert_contains "carried manifest: an included file absent from the manifest is NEW" "$OUT" $'NEW\tfresh.env\t'

rm -f "$WT_CI_GITDIR/carried.index"
run_inc diff "$WT_CI" --main-root "$REPO_CI" --worktree-only
assert_exit "carried manifest: no manifest exits 1" 1 "$?"
assert_eq "carried-index: no manifest gives one NO-MANIFEST row" "NO-MANIFEST" "$(printf '%s\n' "$OUT" | cut -f1 | sort -u)"

REPO_CE="$(mkfixture)"
printf '*.env\n' >"$REPO_CE/.gitignore"
printf '*.env\n' >"$REPO_CE/.worktreeinclude"
git -C "$REPO_CE" add .gitignore .worktreeinclude
git -C "$REPO_CE" commit -qm "include env files"
WT_CE="$TEST_TMPDIR/wt-ce"
git -C "$REPO_CE" worktree add -q -b feat/ce "$WT_CE" main >/dev/null 2>&1
run_inc diff "$WT_CE" --main-root "$REPO_CE" --worktree-only
assert_exit "carried manifest: no manifest and no included file in the worktree is clean" 0 "$?"

printf 'same\n' >"$REPO_CE/app.env"
cp -p "$REPO_CE/app.env" "$WT_CE/app.env"
run_inc diff "$WT_CE" --main-root "$REPO_CE" --worktree-only
assert_exit "carried manifest: no manifest and copies matching main is clean" 0 "$?"
printf 'changed\n' >"$WT_CE/app.env"
run_inc diff "$WT_CE" --main-root "$REPO_CE" --worktree-only
assert_exit "carried manifest: no manifest and a copy differing from main exits 1" 1 "$?"
assert_eq "carried manifest: a differing copy without a manifest gives one NO-MANIFEST row" "NO-MANIFEST" "$(printf '%s\n' "$OUT" | cut -f1 | sort -u)"

[[ $FAILED -eq 0 ]] || exit 1
