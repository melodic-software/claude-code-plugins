#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/worktree-create.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

export GIT_ALLOW_PROTOCOL=file

if command -v cygpath >/dev/null 2>&1; then
  TEST_TMPDIR_NATIVE="$(cygpath -m "$TEST_TMPDIR")"
else
  TEST_TMPDIR_NATIVE="$TEST_TMPDIR"
fi
native_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m -l "$1"; else printf '%s' "$1"; fi; }

DATA_DIR_POSIX="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then
  DATA_DIR="$(cygpath -m "$DATA_DIR_POSIX")"
else
  DATA_DIR="$DATA_DIR_POSIX"
fi
trap 'rm -rf "$TEST_TMPDIR" "$DATA_DIR_POSIX"' EXIT
DATA_ROOT_FILE="$TEST_TMPDIR/data-root"
printf '%s' "$DATA_DIR" >"$DATA_ROOT_FILE"

mkrepo() {
  local origin_url="" seed_head=1 remote_name="origin"
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --origin)
      origin_url="$2"
      shift 2
      ;;
    --remote-name)
      remote_name="$2"
      shift 2
      ;;
    --no-head)
      seed_head=0
      shift
      ;;
    *) shift ;;
    esac
  done
  local repo
  repo="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  {
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email t@t.t
    git -C "$repo" config user.name t
    git -C "$repo" config commit.gpgsign false
    printf 'seed\n' >"$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -qm init
    if [[ -n "$origin_url" ]]; then
      git -C "$repo" remote add -- "$remote_name" "$origin_url"
      if [[ "$seed_head" == 1 ]]; then
        git -C "$repo" update-ref "refs/remotes/$remote_name/main" "$(git -C "$repo" rev-parse HEAD)"
        git -C "$repo" symbolic-ref "refs/remotes/$remote_name/HEAD" "refs/remotes/$remote_name/main"
      fi
    fi
  } >/dev/null 2>&1
  printf '%s' "$repo"
}

addremote() {
  local repo="$1" name="$2" url="$3"
  {
    git -C "$repo" remote add -- "$name" "$url"
    git -C "$repo" update-ref "refs/remotes/$name/main" "$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" symbolic-ref "refs/remotes/$name/HEAD" "refs/remotes/$name/main"
  } >/dev/null 2>&1
}

commitfile() {
  local repo="$1" rel="$2"
  printf 'x\n' >"$repo/$rel"
  {
    git -C "$repo" add "$rel"
    git -C "$repo" commit -qm "add $rel"
  } >/dev/null 2>&1
}

help_out=$(bash "$HELPER" --help 2>&1)
assert_exit "--help exit 0" 0 "$?"
assert_contains "--help documents refuse (exit 3)" "$help_out" "refuse"
assert_contains "--help documents --session-id" "$help_out" "--session-id"
assert_contains "--help documents an omitted session id as no claim" "$help_out" "no session token"

bash "$HELPER" --root "$TEST_TMPDIR/wt" >/dev/null 2>&1
assert_exit "missing --name exit 2" 2 "$?"

repo=$(mkrepo)
bash "$HELPER" --name feat/x --root 'C:foo' --repo-dir "$repo" >/dev/null 2>&1
assert_exit "drive-relative --root exit 2" 2 "$?"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
expected_root="$DATA_DIR/worktrees"
err=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/fallback --data-root-file "$DATA_ROOT_FILE" --repo-dir "$repo" 2>&1 >/dev/null)
rc=$?
out=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/fallback2 --data-root-file "$DATA_ROOT_FILE" --repo-dir "$repo" 2>/dev/null)
assert_exit "unset root creates against the default (exit 0)" 0 "$rc"
assert_contains "fallback announces the default root on stderr" "$err" "worktrees"
assert_contains "fallback names the worktree_root key in its guidance" "$err" "worktree_root"
assert_eq "fallback places the worktree under the plugin data dir" \
  "$expected_root/acme-widget-feat-fallback2" "$out"
assert_file_exists "fallback worktree materialized" "$out/README.md"

case "$out" in
"$repo"/*) fail "default is outside the repository" "not under $repo" "$out" ;;
*) pass "default is outside the repository" ;;
esac

discovery_root=$(mktemp -d "$TEST_TMPDIR/ghqrootXXXXXX")
mkdir -p "$discovery_root/github.com/acme"
disc_repo="$discovery_root/github.com/acme/widget"
{
  git init -q -b main "$disc_repo"
  git -C "$disc_repo" config user.email t@t.t
  git -C "$disc_repo" config user.name t
  git -C "$disc_repo" config commit.gpgsign false
  printf 'seed\n' >"$disc_repo/README.md"
  git -C "$disc_repo" add README.md
  git -C "$disc_repo" commit -qm init
  git -C "$disc_repo" remote add origin "git@github.com:acme/widget.git"
  git -C "$disc_repo" update-ref refs/remotes/origin/main "$(git -C "$disc_repo" rev-parse HEAD)"
  git -C "$disc_repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
} >/dev/null 2>&1
disc_root_native="$(git -C "$disc_repo" rev-parse --show-toplevel)"
disc_root_native="${disc_root_native%/github.com/acme/widget}"
out=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/nodiscovery --data-root-file "$DATA_ROOT_FILE" --repo-dir "$disc_repo" 2>/dev/null)
assert_exit "discovery-layout repo creates against the default (exit 0)" 0 "$?"
case "$out" in
"$disc_root_native"/*) fail "default escapes the repository-discovery root" "not under $disc_root_native" "$out" ;;
*) pass "default escapes the repository-discovery root" ;;
esac

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
expected_root="$DATA_DIR/worktrees"
out=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/tokenfallback --data-root-file "$DATA_ROOT_FILE" --root '${user_config.worktree_root}' --repo-dir "$repo" 2>/dev/null)
assert_exit "unexpanded token creates against the default (exit 0)" 0 "$?"
assert_eq "token fallback places the worktree under the plugin data dir" \
  "$expected_root/acme-widget-feat-tokenfallback" "$out"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
expected_root="$DATA_DIR/worktrees"
foreign="$TEST_TMPDIR_NATIVE/some-other-plugin-data"
out=$(CLAUDE_PLUGIN_DATA="$foreign" bash "$HELPER" --name feat/noenv --data-root-file "$DATA_ROOT_FILE" --repo-dir "$repo" 2>/dev/null)
assert_eq "a foreign CLAUDE_PLUGIN_DATA does not steer the default" \
  "$expected_root/acme-widget-feat-noenv" "$out"
assert_file_absent "nothing created under the foreign plugin data dir" "$foreign/worktrees"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
err=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/noroot --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "no root and no data dir refuses exit 3" 3 "$?"
assert_contains "refuse message names worktree_root key" "$err" "worktree_root"
assert_contains "refuse message rejects the in-repo fallback" "$err" ".claude/worktrees/"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
token_data_file="$TEST_TMPDIR/data-root-token"
# shellcheck disable=SC2016
printf '%s' '${CLAUDE_PLUGIN_DATA}' >"$token_data_file"
err=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/datatoken --data-root-file "$token_data_file" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "unsubstituted data-root-file token refuses exit 3" 3 "$?"
assert_contains "token refusal names worktree_root key" "$err" "worktree_root"
assert_file_absent "no literally-named token directory created in the repo" "$repo/\${CLAUDE_PLUGIN_DATA}"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
chosen="$TEST_TMPDIR_NATIVE/chosen-root"
out=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/precedence --root "$chosen" --data-root-file "$DATA_ROOT_FILE" --repo-dir "$repo" 2>/dev/null)
assert_exit "configured root plus data-root-file creates (exit 0)" 0 "$?"
assert_eq "the configured root wins over the data dir" \
  "$chosen/acme-widget-feat-precedence" "$out"
assert_file_absent "nothing created under the data dir when a root is configured" \
  "$DATA_DIR/worktrees/acme-widget-feat-precedence"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
config_root="$TEST_TMPDIR_NATIVE/config-root"
fallback="$TEST_TMPDIR_NATIVE/fallback-root"
git -C "$repo" config --local worktreeroot.path "$config_root"
out=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/gitconfig --fallback-root "$fallback" --data-root-file "$DATA_ROOT_FILE" --repo-dir "$repo" 2>/dev/null)
assert_exit "worktreeroot.path plus --fallback-root creates (exit 0)" 0 "$?"
assert_eq "worktreeroot.path wins over --fallback-root" \
  "$config_root/acme-widget-feat-gitconfig" "$out"
assert_file_absent "nothing under the fallback root when git config supplies one" \
  "$fallback/acme-widget-feat-gitconfig"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
legacy_root="$TEST_TMPDIR_NATIVE/legacy-root"
fallback="$TEST_TMPDIR_NATIVE/fallback-legacy"
legacy_out="$TEST_TMPDIR/legacy-stdout"
git -C "$repo" config --local melodic.worktreeroot "$legacy_root"
err=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/legacykey --fallback-root "$fallback" --data-root-file "$DATA_ROOT_FILE" --repo-dir "$repo" 2>&1 >"$legacy_out")
rc=$?
out=$(cat "$legacy_out")
assert_exit "a retired alias plus --fallback-root creates (exit 0)" 0 "$rc"
assert_eq "a retired alias still wins over --fallback-root" \
  "$legacy_root/acme-widget-feat-legacykey" "$out"
rewritten=$(git -C "$repo" config --local --get --type=path worktreeroot.path)
assert_eq "create rewrote worktreeroot.path from the retired alias" \
  "$legacy_root" "$rewritten"
old_rc=0
git -C "$repo" config --local --get melodic.worktreeroot >/dev/null 2>&1 || old_rc=$?
assert_exit "create unset the retired alias" 1 "$old_rc"
assert_not_contains "create stderr does not name the retired alias" "$err" \
  "melodic.worktreeroot"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
new_root="$TEST_TMPDIR_NATIVE/new-wins-root"
old_root="$TEST_TMPDIR_NATIVE/old-loses-root"
git -C "$repo" config --local worktreeroot.path "$new_root"
git -C "$repo" config --local melodic.worktreeroot "$old_root"
out=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/newwins --data-root-file "$DATA_ROOT_FILE" --repo-dir "$repo" 2>/dev/null)
assert_exit "both keys set creates (exit 0)" 0 "$?"
assert_eq "worktreeroot.path wins when both keys are set" \
  "$new_root/acme-widget-feat-newwins" "$out"
assert_file_absent "nothing under the outranked retired key" \
  "$old_root/acme-widget-feat-newwins/README.md"
both_left_rc=0
git -C "$repo" config --local --get melodic.worktreeroot >/dev/null 2>&1 || both_left_rc=$?
assert_exit "create drops the leftover retired alias when the current key already answers" 1 "$both_left_rc"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
explicit_root="$TEST_TMPDIR_NATIVE/explicit-root"
git -C "$repo" config --local worktreeroot.path "$TEST_TMPDIR_NATIVE/keyed-root"
out=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/explicit --root "$explicit_root" --repo-dir "$repo" 2>/dev/null)
assert_exit "--root plus worktreeroot.path creates (exit 0)" 0 "$?"
assert_eq "explicit --root wins over worktreeroot.path" \
  "$explicit_root/acme-widget-feat-explicit" "$out"
assert_file_absent "nothing under the keyed root when --root is explicit" \
  "$TEST_TMPDIR/keyed-root/acme-widget-feat-explicit/README.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
git -C "$repo" config --local --add worktreeroot.path "$TEST_TMPDIR_NATIVE/first-root"
git -C "$repo" config --local --add worktreeroot.path "$TEST_TMPDIR_NATIVE/last-root"
out=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/lastwins --data-root-file "$DATA_ROOT_FILE" --repo-dir "$repo" 2>/dev/null)
assert_exit "a multi-valued key creates (exit 0)" 0 "$?"
assert_eq "the LAST worktreeroot.path value wins" \
  "$TEST_TMPDIR_NATIVE/last-root/acme-widget-feat-lastwins" "$out"
assert_file_absent "nothing under the earlier value" \
  "$TEST_TMPDIR/first-root/acme-widget-feat-lastwins/README.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
git -C "$repo" config --local worktreeroot.path "$repo/.claude/worktrees"
err=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/keynested --data-root-file "$DATA_ROOT_FILE" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "an in-repo worktreeroot.path refuses exit 3" 3 "$?"
assert_contains "the in-repo key refusal names the repository" "$err" "inside the repository"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/nodatafile --data-root-file "$TEST_TMPDIR/absent-data-root" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "--data-root-file missing file exit 2" 2 "$?"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
multi_data_file="$TEST_TMPDIR/data-root-multiline"
printf '%s\n%s\n' "$TEST_TMPDIR_NATIVE/one" "touch $TEST_TMPDIR/pwned-data" >"$multi_data_file"
err=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/datanewline --data-root-file "$multi_data_file" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "--data-root-file embedded newline is a usage error (exit 2)" 2 "$?"
assert_contains "--data-root-file newline error names the newline" "$err" "newline"
assert_file_absent "--data-root-file newline payload never executed" "$TEST_TMPDIR/pwned-data"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
err=$(bash "$HELPER" --name feat/x --root "$repo/.claude/worktrees" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "in-repo root refuses exit 3" 3 "$?"
assert_contains "in-repo refuse names the repository" "$err" "inside the repository"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
bash "$HELPER" --name feat/x --root "worktrees" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "relative in-repo root refuses exit 3" 3 "$?"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
other=$(mkrepo --origin "git@github.com:acme/other.git")
err=$(bash "$HELPER" --name feat/x --root "$other/nested" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "root inside another checkout refuses exit 3" 3 "$?"
assert_contains "foreign-checkout refuse names another working tree" "$err" "another git working tree"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
err=$(bash "$HELPER" --name feat/x --root "$repo/.git/external" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "root under .git refuses exit 3" 3 "$?"
assert_contains "git-dir refuse names a git directory" "$err" "inside a git directory"
assert_file_absent "no worktree created inside .git" "$repo/.git/external/acme-widget-feat-x/README.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
bare="$(mktemp -d "$TEST_TMPDIR/bareXXXXXX")/other.git"
git init -q --bare "$bare" >/dev/null 2>&1
err=$(bash "$HELPER" --name feat/x --root "$bare/worktrees" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "root inside a bare clone refuses exit 3" 3 "$?"
assert_contains "bare-clone refuse names a git directory" "$err" "inside a git directory"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/nonexistent-leading/../${repo##*/}/.claude/worktrees"
err=$(bash "$HELPER" --name feat/x --root "$root" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "'..'-after-nonexistent in-repo root refuses exit 3" 3 "$?"
assert_contains "normalized in-repo refuse names the repository" "$err" "inside the repository"
assert_file_absent "no worktree materialized inside repo via '..' bypass" \
  "$repo/.claude/worktrees/acme-widget-feat-x/README.md"

if [[ "$OSTYPE" == msys || "$OSTYPE" == cygwin ]] && command -v cygpath >/dev/null 2>&1; then
  repo=$(mkrepo --origin "git@github.com:acme/widget.git")
  err=$(bash "$HELPER" --name feat/bs --root "$(cygpath -w "$repo")\\.claude\\worktrees" --repo-dir "$repo" 2>&1 >/dev/null) # portability-ok: Windows path string in a test fixture, not a regex/sed construct
  assert_exit "backslash root inside repo refuses exit 3" 3 "$?"
  assert_contains "backslash in-repo refuse names the repository" "$err" "inside the repository"
  assert_file_absent "no worktree via backslash-into-repo" "$repo/.claude/worktrees/acme-widget-feat-bs/README.md"

  repo=$(mkrepo --origin "git@github.com:acme/widget.git")
  err=$(bash "$HELPER" --name feat/bg --root "$(cygpath -w "$repo")\\.git\\ext" --repo-dir "$repo" 2>&1 >/dev/null)
  assert_exit "backslash root inside .git refuses exit 3" 3 "$?"
  assert_contains "backslash-into-.git names a git directory" "$err" "inside a git directory"

  repo=$(mkrepo --origin "git@github.com:acme/widget.git")
  bs_dd="$(cygpath -w "$repo")\\..\\missing\\..\\${repo##*/}\\.claude\\worktrees" # portability-ok: Windows path string in a test fixture, not a regex/sed construct
  bash "$HELPER" --name feat/bd --root "$bs_dd" --repo-dir "$repo" >/dev/null 2>&1
  assert_exit "backslash + '..' resolving inside repo refuses exit 3" 3 "$?"

  repo=$(mkrepo --origin "git@github.com:acme/widget.git")
  out=$(bash "$HELPER" --name feat/be --root "$(cygpath -w "$TEST_TMPDIR/ext-backslash")" --repo-dir "$repo" 2>/dev/null)
  assert_exit "external backslash root still creates (exit 0)" 0 "$?"
  assert_file_exists "external backslash worktree materialized" "$out/README.md"
else
  skip_case "backslash-root canonicalization is Windows-only"
fi

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/adjacent-external"
out=$(bash "$HELPER" --name feat/adj --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_exit "external root adjacent to a repo still creates (exit 0)" 0 "$?"
assert_file_exists "external adjacent worktree materialized" "$out/README.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/wtroot1"
out=$(bash "$HELPER" --name "feat/my-feature" --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_exit "create exit 0" 0 "$?"
assert_eq "computed path is <root>/<owner>-<repo>-<slug>" \
  "$root/acme-widget-feat-my-feature" "$out"
assert_file_exists "worktree checkout materialized" "$out/README.md"
assert_eq "branch keeps original name" "feat/my-feature" \
  "$(git -C "$out" rev-parse --abbrev-ref HEAD)"

repo=$(mkrepo --origin "https://github.com/acme/widget.git")
root="$TEST_TMPDIR/wtroot2"
out=$(bash "$HELPER" --name fix/bug --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "https origin -> same owner-repo" "$root/acme-widget-fix-bug" "$out"

repo=$(mkrepo)
root="$TEST_TMPDIR/wtroot3"
out=$(bash "$HELPER" --name chore/tidy --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "no origin -> <repo>-<slug>, owner omitted" \
  "$root/${repo##*/}-chore-tidy" "$out"

bash "$HELPER" --name chore/tidy --root "$root" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "duplicate path exit 4" 4 "$?"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
printf 'local-only\n' >"$repo/UNPUSHED.md"
git -C "$repo" add UNPUSHED.md
git -C "$repo" commit -qm "unpushed local commit"
root="$TEST_TMPDIR/wtroot4"
out=$(bash "$HELPER" --name feat/head-base --root "$root" --base-ref head --repo-dir "$repo" 2>/dev/null)
assert_file_exists "base-ref head carries the unpushed commit" "$out/UNPUSHED.md"

root="$TEST_TMPDIR/wtroot5"
out=$(bash "$HELPER" --name feat/fresh-base --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_file_exists "base-ref fresh materializes the worktree" "$out/README.md"
assert_file_absent "base-ref fresh excludes the unpushed commit" "$out/UNPUSHED.md"
assert_eq "base-ref fresh leaves branch.<name>.merge unset" "" \
  "$(git -C "$repo" config --get branch.feat/fresh-base.merge)"
assert_eq "base-ref fresh leaves branch.<name>.remote unset" "" \
  "$(git -C "$repo" config --get branch.feat/fresh-base.remote)"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
printf '.work/\n*.env\n' >"$repo/.gitignore"
printf '.work/keep.md\n.work/*/EXPLORE.md\n*.env\n' >"$repo/.worktreeinclude"
git -C "$repo" add .gitignore .worktreeinclude
git -C "$repo" commit -qm "ignore + include"
mkdir -p "$repo/.work/task1"
printf 'x\n' >"$repo/.work/keep.md"          # matched + gitignored -> copy
printf 'x\n' >"$repo/.work/task1/EXPLORE.md" # matched (nested) + gitignored -> copy
printf 'x\n' >"$repo/.work/task1/OTHER.md"   # gitignored, NOT matched  -> skip
printf 'x\n' >"$repo/secrets.env"            # matched + gitignored -> copy
printf 'x\n' >"$repo/loose.txt"              # neither -> skip
root="$TEST_TMPDIR/wtroot6"
out=$(bash "$HELPER" --name feat/inc --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_file_exists "worktreeinclude: matched+ignored top-level copied" "$out/.work/keep.md"
assert_file_exists "worktreeinclude: matched+ignored nested copied (mkdir -p)" "$out/.work/task1/EXPLORE.md"
assert_file_exists "worktreeinclude: matched+ignored env copied" "$out/secrets.env"
assert_file_absent "worktreeinclude: gitignored-but-unmatched skipped" "$out/.work/task1/OTHER.md"
assert_file_absent "worktreeinclude: unignored file never copied" "$out/loose.txt"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
printf '.work/\n' >"$repo/.gitignore"
printf '.work/.gitignore\n.work/**/INDEX.md\n.work/**/EXPLORE.md\n.work/**/INTENT.md\n.work/**/*-checklist.md\n' \
  >"$repo/.worktreeinclude"
git -C "$repo" add .gitignore .worktreeinclude
git -C "$repo" commit -qm "recursive include"
mkdir -p "$repo/.work/epic/slice" "$repo/.work/slice"
printf 'x\n' >"$repo/.work/.gitignore"                     # self-ignore rides along
printf 'x\n' >"$repo/.work/INDEX.md"                       # depth 1 (zero-dir `**`)
printf 'x\n' >"$repo/.work/slice/INTENT.md"                # depth 2
printf 'x\n' >"$repo/.work/epic/slice/EXPLORE.md"          # depth 3
printf 'x\n' >"$repo/.work/epic/slice/review-checklist.md" # depth 3 ledger
printf 'x\n' >"$repo/.work/slice/scratch-foo"              # gitignored, NOT matched
root="$TEST_TMPDIR/wtroot-recursive"
out=$(bash "$HELPER" --name feat/deep --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_file_exists "worktreeinclude **: self-ignore carried" "$out/.work/.gitignore"
assert_file_exists "worktreeinclude **: depth-1 INDEX.md carried" "$out/.work/INDEX.md"
assert_file_exists "worktreeinclude **: depth-2 INTENT.md carried" "$out/.work/slice/INTENT.md"
assert_file_exists "worktreeinclude **: depth-3 EXPLORE.md carried" "$out/.work/epic/slice/EXPLORE.md"
assert_file_exists "worktreeinclude **: depth-3 checklist carried" "$out/.work/epic/slice/review-checklist.md"
assert_file_absent "worktreeinclude **: non-reserved name skipped" "$out/.work/slice/scratch-foo"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
mkdir -p "$repo/.claude"
printf '{"env":{"DISK_HYGIENE_GUARD_WATCHDOG_SECONDS":"50"}}\n' >"$repo/.claude/settings.local.json"
root="$TEST_TMPDIR/wtroot-settings"
out=$(bash "$HELPER" --name feat/settings --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_file_exists "settings.local.json copied into the worktree" "$out/.claude/settings.local.json"

for flag in --name --root --base-ref --repo-dir --session-id; do
  code=0
  bash "$HELPER" "$flag" >/dev/null 2>&1 || code=$?
  assert_exit "trailing valueless $flag errors (no hang)" 2 "$code"
done

repo=$(mkrepo --origin "git@github.com:acme/widget.git" --no-head)
root="$TEST_TMPDIR/wtroot7"
err=$(bash "$HELPER" --name feat/nohead --root "$root" --base-ref fresh --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "fresh w/o origin/HEAD still succeeds" 0 "$?"
assert_contains "fresh w/o origin/HEAD warns about fallback" "$err" "could not resolve the remote default branch"
assert_contains "fresh w/o origin/HEAD names the resolved remote" "$err" "origin/HEAD not set"
assert_file_exists "fresh fallback still creates the worktree" "$root/acme-widget-feat-nohead/README.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git" --remote-name upstream)
commitfile "$repo" UNPUSHED.md
root="$TEST_TMPDIR/wtroot-upstream"
out=$(bash "$HELPER" --name feat/upstream-fresh --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_exit "fresh with sole non-origin remote succeeds" 0 "$?"
assert_file_absent "fresh bases on upstream/HEAD, not local HEAD" "$out/UNPUSHED.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git" --remote-name upstream --no-head)
root="$TEST_TMPDIR/wtroot-upstream-nohead"
errfile="$TEST_TMPDIR/err-upstream-nohead.txt"
out=$(bash "$HELPER" --name feat/upnohead --root "$root" --base-ref fresh --repo-dir "$repo" 2>"$errfile")
assert_exit "uncached non-origin HEAD still succeeds" 0 "$?"
assert_contains "warning names the resolved remote's symref" "$(cat "$errfile")" "upstream/HEAD not set"
assert_contains "warning offers set-head for that remote" "$(cat "$errfile")" "set-head upstream --auto"
assert_file_exists "uncached non-origin fallback still creates the worktree" "$out/README.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
commitfile "$repo" UPSTREAM_ONLY.md
addremote "$repo" upstream "git@github.com:acme/widget-fork.git"
commitfile "$repo" UNPUSHED.md
git -C "$repo" config branch.main.remote upstream
root="$TEST_TMPDIR/wtroot-branchcfg"
out=$(bash "$HELPER" --name feat/branchcfg --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_file_exists "branch-configured remote wins over origin" "$out/UPSTREAM_ONLY.md"
assert_file_absent "branch-configured remote is not local HEAD" "$out/UNPUSHED.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
commitfile "$repo" DASHED_ONLY.md
addremote "$repo" -foo "git@github.com:acme/widget-fork.git"
commitfile "$repo" UNPUSHED.md
git -C "$repo" config -- branch.main.remote -foo
root="$TEST_TMPDIR/wtroot-dashedremote"
out=$(bash "$HELPER" --name feat/dashedremote --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_exit "option-shaped branch remote still succeeds" 0 "$?"
assert_file_exists "option-shaped branch remote wins over origin" "$out/DASHED_ONLY.md"
assert_file_absent "option-shaped branch remote is not local HEAD" "$out/UNPUSHED.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
commitfile "$repo" UNPUSHED.md
git -C "$repo" config branch.main.remote ghost
root="$TEST_TMPDIR/wtroot-ghost"
out=$(bash "$HELPER" --name feat/ghost --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_exit "stale branch remote still succeeds" 0 "$?"
assert_file_exists "stale branch remote materializes the worktree" "$out/README.md"
assert_file_absent "stale branch remote falls through to origin" "$out/UNPUSHED.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
commitfile "$repo" UNPUSHED.md
git -C "$repo" config branch.main.remote .
root="$TEST_TMPDIR/wtroot-dotremote"
out=$(bash "$HELPER" --name feat/dotremote --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_exit "'.' branch remote still succeeds" 0 "$?"
assert_file_exists "'.' branch remote materializes the worktree" "$out/README.md"
assert_file_absent "'.' branch remote falls through to origin" "$out/UNPUSHED.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
commitfile "$repo" UNPUSHED.md
git -C "$repo" checkout -q --detach HEAD
root="$TEST_TMPDIR/wtroot-detached"
out=$(bash "$HELPER" --name feat/detached --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_exit "fresh on a detached HEAD succeeds" 0 "$?"
assert_file_absent "detached HEAD still bases on origin/HEAD" "$out/UNPUSHED.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git" --remote-name upstream)
addremote "$repo" fork "git@github.com:someone/widget.git"
root="$TEST_TMPDIR/wtroot-ambiguous"
errfile="$TEST_TMPDIR/err-ambiguous.txt"
out=$(bash "$HELPER" --name feat/ambiguous --root "$root" --base-ref fresh --repo-dir "$repo" 2>"$errfile")
assert_exit "ambiguous remotes still succeed" 0 "$?"
assert_contains "ambiguous remotes warn about fallback" "$(cat "$errfile")" "could not resolve the remote default branch"
assert_contains "ambiguous remotes name the no-default-remote cause" "$(cat "$errfile")" "no default remote"
assert_file_exists "ambiguous fallback still creates the worktree" "$out/README.md"

repo=$(mkrepo)
root="$TEST_TMPDIR/wtroot-noremote"
errfile="$TEST_TMPDIR/err-noremote.txt"
out=$(bash "$HELPER" --name feat/noremote --root "$root" --base-ref fresh --repo-dir "$repo" 2>"$errfile")
assert_exit "remoteless fresh still succeeds" 0 "$?"
assert_contains "remoteless fresh warns about fallback" "$(cat "$errfile")" "could not resolve the remote default branch"
assert_file_exists "remoteless fallback still creates the worktree" "$out/README.md"

stalerepo() {
  local remote="$1" seed pusher clone
  seed="$(mkrepo)"
  pusher="$(mktemp -d "$TEST_TMPDIR/pusherXXXXXX")"
  clone="$(mktemp -d "$TEST_TMPDIR/staleXXXXXX")"
  {
    git init -q --bare -b main "$remote"
    git -C "$seed" push -q "$remote" main
    git clone -q "$remote" "$clone"
    git -C "$clone" config user.email t@t.t
    git -C "$clone" config user.name t
    git -C "$clone" config commit.gpgsign false
    git clone -q "$remote" "$pusher"
    git -C "$pusher" config user.email t@t.t
    git -C "$pusher" config user.name t
    git -C "$pusher" config commit.gpgsign false
  } >/dev/null 2>&1
  commitfile "$pusher" REMOTE_ONLY.md
  git -C "$pusher" push -q origin main >/dev/null 2>&1
  printf '%s' "$clone"
}

repo=$(stalerepo "$TEST_TMPDIR/stale-remote.git")
root="$TEST_TMPDIR/wtroot-stale"
errfile="$TEST_TMPDIR/err-stale.txt"
out=$(bash "$HELPER" --name feat/stale --root "$root" --base-ref fresh --repo-dir "$repo" 2>"$errfile")
assert_exit "stale cached origin/HEAD still succeeds" 0 "$?"
assert_file_exists "fresh fetched the commit the cache lacked" "$out/REMOTE_ONLY.md"
assert_eq "worktree is 0 behind origin/main right after creation" "0" \
  "$(git -C "$out" rev-list --count HEAD..origin/main 2>/dev/null)"
assert_eq "worktree HEAD is the remote's actual tip" \
  "$(git -C "$TEST_TMPDIR/stale-remote.git" rev-parse main 2>/dev/null)" \
  "$(git -C "$out" rev-parse HEAD 2>/dev/null)"
assert_not_contains "a successful refresh prints no warning" "$(cat "$errfile")" "warning"

repo=$(stalerepo "$TEST_TMPDIR/stale-remote-nofh.git")
rm -f "$repo/.git/FETCH_HEAD"
root="$TEST_TMPDIR/wtroot-stale-nofh"
out=$(bash "$HELPER" --name feat/stale-nofh --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_file_exists "a clone with no FETCH_HEAD fetches" "$out/REMOTE_ONLY.md"

repo=$(stalerepo "$TEST_TMPDIR/stale-remote-recent.git")
: >"$repo/.git/FETCH_HEAD"
root="$TEST_TMPDIR/wtroot-stale-recent"
errfile="$TEST_TMPDIR/err-stale-recent.txt"
out=$(bash "$HELPER" --name feat/stale-recent --root "$root" --base-ref fresh --repo-dir "$repo" 2>"$errfile")
assert_file_exists "a recent FETCH_HEAD still fetches" "$out/REMOTE_ONLY.md"
assert_contains "a refreshed base reports fresh" "$(cat "$errfile")" "(base fresh)"

repo=$(stalerepo "$TEST_TMPDIR/stale-remote-gone.git")
git -C "$repo" remote set-url origin "$TEST_TMPDIR/no-such-remote.git"
rm -f "$repo/.git/FETCH_HEAD"
root="$TEST_TMPDIR/wtroot-stale-gone"
errfile="$TEST_TMPDIR/err-stale-gone.txt"
out=$(bash "$HELPER" --name feat/stale-gone --root "$root" --base-ref fresh --repo-dir "$repo" 2>"$errfile")
assert_exit "failed refresh still succeeds" 0 "$?"
assert_file_exists "failed refresh bases on the cached ref" "$out/README.md"
assert_file_absent "failed refresh cannot carry the remote-only commit" "$out/REMOTE_ONLY.md"
assert_contains "failed refresh warns it could not refresh" "$(cat "$errfile")" "could not refresh origin/main"
assert_contains "failed refresh reports the cached base commit, not fresh" "$(cat "$errfile")" \
  "(base origin/main@$(git -C "$repo" rev-parse --short origin/main 2>/dev/null), not refreshed)"

repo=$(stalerepo "$TEST_TMPDIR/stale-remote-hang.git")
git -C "$repo" remote set-url origin "ssh://example.invalid/widget.git"
rm -f "$repo/.git/FETCH_HEAD"
root="$TEST_TMPDIR/wtroot-stale-hang"
errfile="$TEST_TMPDIR/err-stale-hang.txt"
started=$SECONDS
out=$(GIT_ALLOW_PROTOCOL=ssh GIT_SSH_COMMAND='sleep 30; :' \
  bash "$HELPER" --name feat/stale-hang --root "$root" --base-ref fresh --repo-dir "$repo" 2>"$errfile")
code=$?
elapsed=$((SECONDS - started))
assert_exit "hung refresh still succeeds" 0 "$code"
assert_file_exists "hung refresh bases on the cached ref" "$out/README.md"
assert_contains "hung refresh warns it could not refresh" "$(cat "$errfile")" "could not refresh origin/main"
assert_eq "hung refresh returns near the cap, not after the 30s hang (took ${elapsed}s)" \
  "1" "$((elapsed < 20))"

repo=$(mkrepo --origin "https://dev.azure.com/myorg/myproject/_git/widget")
root="$TEST_TMPDIR/wtroot8"
out=$(bash "$HELPER" --name feat/az --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "Azure _git URL -> project as owner, repo last" "$root/myproject-widget-feat-az" "$out"

repo=$(mkrepo --origin "https://gitlab.com/group/subgroup/widget.git")
root="$TEST_TMPDIR/wtroot9"
out=$(bash "$HELPER" --name feat/gl --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "GitLab subgroup URL -> subgroup as owner" "$root/subgroup-widget-feat-gl" "$out"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
err=$(bash "$HELPER" --name 'feat/weird @name#v2' --root "$TEST_TMPDIR/wtroot10" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "unsafe-char name refused (exit 2)" 2 "$?"
assert_contains "unsafe-char refusal explains the rule" "$err" "not a valid worktree/branch name"
bash "$HELPER" --name "feat/$(printf 'a%.0s' {1..70})" --root "$TEST_TMPDIR/wtroot10" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "over-64-char name refused (exit 2)" 2 "$?"
for badref in 'feat/foo..bar' 'feat/.' 'foo.lock' 'feat/x.lock' '.foo' 'foo.' 'HEAD' '-lead'; do
  code=0
  err=$(bash "$HELPER" --name "$badref" --root "$TEST_TMPDIR/wtroot10c" --repo-dir "$repo" 2>&1 >/dev/null) || code=$?
  assert_exit "git-invalid ref name $badref refused (exit 2, not 4)" 2 "$code"
  assert_contains "git-invalid $badref refusal names the branch grammar" "$err" "not a valid git branch name"
done
root="$TEST_TMPDIR/wtroot10d"
out=$(bash "$HELPER" --name "feat/refok" --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_exit "ref-valid name still creates (exit 0)" 0 "$?"
assert_eq "ref check leaves stdout as the sole path line" "$root/acme-widget-feat-refok" "$out"
stale="$(mktemp -d "$TEST_TMPDIR/staleXXXXXX")"
printf 'gitdir: %s/definitely-not-here\n' "$TEST_TMPDIR" >"$stale/.git"
root="$TEST_TMPDIR/wtroot10e"
out=$(cd "$stale" && bash "$HELPER" --name "feat/cwdok" --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_exit "valid name unaffected by a stale .git in the CWD (exit 0)" 0 "$?"
assert_eq "stale-CWD run still prints the worktree path" "$root/acme-widget-feat-cwdok" "$out"
code=0
(cd "$stale" && bash "$HELPER" --name 'feat/foo..bar' --root "$TEST_TMPDIR/wtroot10f" --repo-dir "$repo") >/dev/null 2>&1 || code=$?
assert_exit "stale CWD still rejects a git-invalid name (exit 2)" 2 "$code"
root="$TEST_TMPDIR/wtroot10b"
out=$(bash "$HELPER" --name "feat/scope.v2_final-1" --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "valid name: '/' -> '-' in the dir slug" "$root/acme-widget-feat-scope.v2_final-1" "$out"
assert_eq "valid name: branch kept verbatim" "feat/scope.v2_final-1" \
  "$(git -C "$out" rev-parse --abbrev-ref HEAD)"

nonrepo="$(mktemp -d "$TEST_TMPDIR/plainXXXXXX")"
bash "$HELPER" --name feat/x --root "$TEST_TMPDIR/wtroot11" --repo-dir "$nonrepo" >/dev/null 2>&1
assert_exit "--repo-dir outside a git repo exits 4" 4 "$?"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/wtroot12"
out=$(bash "$HELPER" --name feat/trail --root "$root/" --repo-dir "$repo" 2>/dev/null)
assert_eq "trailing-slash root yields a single separator" \
  "$root/acme-widget-feat-trail" "$out"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-both"
printf '%s' "$TEST_TMPDIR/wtroot-both" >"$root_file"
bash "$HELPER" --name feat/both --root "$TEST_TMPDIR/wtroot-both" --root-file "$root_file" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "--root and --root-file together exit 2" 2 "$?"

bash "$HELPER" --name feat/both2 --root "" --root-file "$root_file" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "--root '' with --root-file still exits 2" 2 "$?"
bash "$HELPER" --name feat/both3 --root "$TEST_TMPDIR/wtroot-both" --root-file "" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "--root with --root-file '' still exits 2" 2 "$?"

bash "$HELPER" --name feat/missingfile --root-file "$TEST_TMPDIR/does-not-exist" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "--root-file missing file exit 2" 2 "$?"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR_NATIVE/wtroot13-O'Connor \$weird \`root\`"
root_file="$TEST_TMPDIR/rootfile-special"
printf '%s' "$root" >"$root_file"
out=$(bash "$HELPER" --name feat/special --root-file "$root_file" --repo-dir "$repo" 2>/dev/null)
assert_exit "--root-file special-char root creates (exit 0)" 0 "$?"
assert_eq "--root-file special-char root computes the exact path" \
  "$root/acme-widget-feat-special" "$out"
assert_file_exists "--root-file special-char worktree materialized" "$out/README.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-empty"
: >"$root_file"
expected_root="$DATA_DIR/worktrees"
err=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/emptyfallback --data-root-file "$DATA_ROOT_FILE" --root-file "$root_file" --repo-dir "$repo" 2>&1 >/dev/null)
rc=$?
assert_exit "--root-file empty content creates against the default (exit 0)" 0 "$rc"
assert_contains "--root-file empty content names worktree_root key" "$err" "worktree_root"
out=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/emptyfallback2 --data-root-file "$DATA_ROOT_FILE" --root-file "$root_file" --repo-dir "$repo" 2>/dev/null)
assert_eq "--root-file empty content places the worktree under the plugin data dir" \
  "$expected_root/acme-widget-feat-emptyfallback2" "$out"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-token"
# shellcheck disable=SC2016
printf '%s' '${user_config.worktree_root}' >"$root_file"
expected_root="$DATA_DIR/worktrees"
out=$(CLAUDE_PLUGIN_DATA='' bash "$HELPER" --name feat/token --data-root-file "$DATA_ROOT_FILE" --root-file "$root_file" --repo-dir "$repo" 2>/dev/null)
assert_exit "--root-file unexpanded token creates against the default (exit 0)" 0 "$?"
assert_eq "--root-file token fallback places the worktree under the plugin data dir" \
  "$expected_root/acme-widget-feat-token" "$out"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR_NATIVE/wtroot14-noeol.d"
root_file="$TEST_TMPDIR/rootfile-noeol"
printf '%s' "$root" >"$root_file"
out=$(bash "$HELPER" --name feat/noeol --root-file "$root_file" --repo-dir "$repo" 2>/dev/null)
assert_exit "--root-file unterminated value creates (exit 0)" 0 "$?"
assert_eq "--root-file unterminated value keeps every byte" "$root/acme-widget-feat-noeol" "$out"
assert_file_exists "--root-file unterminated value materialized" "$out/README.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-multiline"
printf '%s\n%s\n' "$TEST_TMPDIR/wtroot15-multi" "touch $TEST_TMPDIR/pwned" >"$root_file"
err=$(bash "$HELPER" --name feat/multi --root-file "$root_file" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "--root-file embedded newline is a usage error (exit 2)" 2 "$?"
assert_contains "--root-file newline error names the newline" "$err" "newline"
assert_file_absent "--root-file newline payload never executed" "$TEST_TMPDIR/pwned"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-trailing-eol"
printf '%s\n' "$TEST_TMPDIR/wtroot16-trailing" >"$root_file"
err=$(bash "$HELPER" --name feat/trailing --root-file "$root_file" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "--root-file trailing newline is a usage error (exit 2)" 2 "$?"
assert_contains "--root-file trailing-newline error names the newline" "$err" "newline"
assert_file_absent "--root-file trailing-newline root never materialized" \
  "$TEST_TMPDIR/wtroot16-trailing/acme-widget-feat-trailing/README.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-nul"
printf '%s\000%s' "$TEST_TMPDIR/wtroot17-nul" "suffix" >"$root_file"
err=$(bash "$HELPER" --name feat/nul --root-file "$root_file" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "--root-file NUL byte is a usage error (exit 2)" 2 "$?"
assert_contains "--root-file NUL error names the NUL byte" "$err" "NUL"
assert_file_absent "--root-file NUL-collapsed path never materialized" \
  "$TEST_TMPDIR/wtroot17-nulsuffix/acme-widget-feat-nul/README.md"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-lock"
printf '%s' "$TEST_TMPDIR/wtroot18-lock" >"$root_file"
out=$(bash "$HELPER" --name feat/liveness --root-file "$root_file" --repo-dir "$repo" 2>/dev/null)
assert_exit "lock case: creation succeeds (exit 0)" 0 "$?"
stanza=$(git -C "$repo" worktree list --porcelain | awk -v RS= -v p="acme-widget-feat-liveness" 'index($0, p)')
assert_contains "the new worktree is locked at creation" "$stanza" "locked"
assert_contains "the lock reason names the arming helper" "$stanza" "worktree-create.sh"
err=$(git -C "$repo" worktree remove "$out" 2>&1 >/dev/null)
rc=$?
assert_contains "plain removal refuses and names the lock" "$err" "locked"
if [[ "$rc" -ne 0 ]]; then
  pass "plain removal exits non-zero while the lock is armed"
else
  fail "plain removal exits non-zero while the lock is armed" "non-zero" "0"
fi
assert_file_exists "the locked worktree survives the removal attempt" "$out/README.md"

CLAIM="$SCRIPT_DIR/worktree-claim.sh"
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/wtroot-session"
out=$(bash "$HELPER" --name feat/sessown --root "$root" --session-id sess-owner --repo-dir "$repo" 2>/dev/null)
assert_exit "create with --session-id succeeds (exit 0)" 0 "$?"
lock_file="$(git -C "$out" rev-parse --absolute-git-dir)/locked"
reason="$(tr -d '\r\n' <"$lock_file")"
assert_contains "session lock reason uses the claim token" "$reason" "session sess-owner since"
assert_contains "session lock reason still names the helper" "$reason" "worktree-create.sh:"
case "$reason" in
"worktree-create.sh: lane active on "*" session sess-owner since "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z"; unlock when the owning lane is done")
  pass "session lock reason has the claim_reason shape"
  ;;
*)
  fail "session lock reason has the claim_reason shape" \
    "worktree-create.sh: lane active on <host> session sess-owner since <utc>; unlock when the owning lane is done" \
    "$reason"
  ;;
esac

bash "$CLAIM" check-enter "$out" --repo-dir "$repo" --session-id sess-owner >/dev/null 2>&1
assert_exit "check-enter with the creating session id exits 0" 0 "$?"

code=0
err=$(bash "$CLAIM" check-enter "$out" --repo-dir "$repo" --session-id sess-other 2>&1 >/dev/null) || code=$?
assert_exit "check-enter with a different session id exits 4" 4 "$code"
assert_contains "different session id is a foreign claim" "$err" "FOREIGN CLAIM:"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/wtroot-s10"
out=$(bash "$HELPER" --name feat/s10 --root "$root" --session-id s10 --repo-dir "$repo" 2>/dev/null)
assert_exit "create with session id s10 succeeds" 0 "$?"
bash "$CLAIM" check-enter "$out" --repo-dir "$repo" --session-id s1 >/dev/null 2>&1
assert_exit "session s1 does not own a helper lock stamped s10" 4 "$?"
bash "$CLAIM" check-enter "$out" --repo-dir "$repo" --session-id s10 >/dev/null 2>&1
assert_exit "session s10 owns the helper lock it stamped" 0 "$?"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/wtroot-nosess"
out=$(CLAUDE_SESSION_ID=env-sess bash "$HELPER" --name feat/nosess --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_exit "create without --session-id succeeds (exit 0)" 0 "$?"
lock_file="$(git -C "$out" rev-parse --absolute-git-dir)/locked"
reason="$(tr -d '\r\n' <"$lock_file")"
if [[ "$reason" == *"session "*" since"* ]]; then
  fail "omitted session id writes no ownable session token" "no session <id> since" "$reason"
else
  pass "omitted session id writes no ownable session token"
fi
case "$reason" in
"worktree-create.sh: lane active on "*" since "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z"; unlock when the owning lane is done")
  pass "omitted session id keeps the host-and-time reason"
  ;;
*)
  fail "omitted session id keeps the host-and-time reason" \
    "worktree-create.sh: lane active on <host> since <utc>; unlock when the owning lane is done" \
    "$reason"
  ;;
esac
bash "$CLAIM" check-enter "$out" --repo-dir "$repo" --session-id arbitrary-sid >/dev/null 2>&1
assert_exit "omitted session id does not satisfy check-enter for an arbitrary id" 4 "$?"
bash "$CLAIM" check-enter "$out" --repo-dir "$repo" --session-id env-sess >/dev/null 2>&1
assert_exit "omitted session id is not reported as CLAUDE_SESSION_ID's claim" 4 "$?"

root="$TEST_TMPDIR/wtroot-emptysid"
out=$(bash "$HELPER" --name feat/emptysid --root "$root" --session-id "" --repo-dir "$repo" 2>/dev/null)
assert_exit "empty --session-id still creates (exit 0)" 0 "$?"
lock_file="$(git -C "$out" rev-parse --absolute-git-dir)/locked"
reason="$(tr -d '\r\n' <"$lock_file")"
if [[ "$reason" == *"session "*" since"* ]]; then
  fail "empty --session-id writes no ownable session token" "no session <id> since" "$reason"
else
  pass "empty --session-id writes no ownable session token"
fi
bash "$CLAIM" check-enter "$out" --repo-dir "$repo" --session-id arbitrary-sid >/dev/null 2>&1
assert_exit "empty --session-id does not satisfy check-enter" 4 "$?"

code=0
err=$(bash "$HELPER" --name feat/badsess --root "$TEST_TMPDIR/wtroot-badsess" --session-id 'bad id' --repo-dir "$repo" 2>&1 >/dev/null) || code=$?
assert_exit "invalid --session-id is usage (exit 2)" 2 "$code"
assert_contains "invalid --session-id names the grammar" "$err" "--session-id must match"
assert_file_absent "invalid --session-id creates nothing" \
  "$TEST_TMPDIR/wtroot-badsess/acme-widget-feat-badsess/README.md"

eval "$(awk '/^windows_drive_letter\(\) \{/{p=1} p{print} p && /^}$/ && ++n == 2 {exit}' "$HELPER")"
# shellcheck disable=SC2034 # consumed by check_same_drive, eval'd in above from worktree-create.sh
PROG=worktree-create.sh

assert_eq "drive letter from C:/repos" "C" "$(windows_drive_letter 'C:/repos/foo')"
assert_eq "drive letter casefolds" "D" "$(windows_drive_letter 'd:/Worktrees')"
assert_eq "drive letter from /cygdrive/d" "D" "$(windows_drive_letter '/cygdrive/d/worktrees')"
windows_drive_letter '/tmp/foo' >/dev/null 2>&1
assert_exit "POSIX path has no drive letter" 1 "$?"
windows_drive_letter '//server/share/x' >/dev/null 2>&1
assert_exit "UNC path has no drive letter" 1 "$?"
case "$(uname -s 2>/dev/null || true)" in
MINGW* | MSYS* | CYGWIN*)
  assert_eq "MSYS /d/ form is drive D" "D" "$(windows_drive_letter '/d/worktrees')"
  err=$(check_same_drive 'C:/repos/acme' '/d/worktrees/acme-x' 1 2>&1 >/dev/null)
  assert_exit "MSYS root vs Windows repo refuses cross-drive" 3 "$?"
  ;;
*)
  windows_drive_letter '/d/worktrees' >/dev/null 2>&1
  assert_exit "POSIX /d/ path is not a drive letter" 1 "$?"
  ;;
esac

check_same_drive 'C:/repos/acme' 'C:/worktrees/acme-x' 1 >/dev/null 2>&1
assert_exit "same-drive explicit root proceeds" 0 "$?"
check_same_drive 'c:/repos/acme' 'C:/worktrees/acme-x' 2 >/dev/null 2>&1
assert_exit "same-drive casefold proceeds" 0 "$?"
check_same_drive 'C:/repos/acme' '/cygdrive/c/worktrees/acme-x' 1 >/dev/null 2>&1
assert_exit "same-drive Cygwin form proceeds" 0 "$?"

check_same_drive '/tmp/repo' 'D:/worktrees/x' 1 >/dev/null 2>&1
assert_exit "inert when repo has no drive letter" 0 "$?"
check_same_drive 'C:/repos/acme' '/var/worktrees/x' 1 >/dev/null 2>&1
assert_exit "inert when worktree has no drive letter" 0 "$?"
check_same_drive '/tmp/repo' '/var/worktrees/x' 1 >/dev/null 2>&1
assert_exit "inert on POSIX both sides" 0 "$?"

err=$(check_same_drive 'C:/repos/acme' 'D:/worktrees/acme-x' 1 2>&1 >/dev/null)
assert_exit "rung-1 cross-drive refuses exit 3" 3 "$?"
assert_contains "rung-1 refuse names both drives" "$err" "drive C:"
assert_contains "rung-1 refuse names the foreign drive" "$err" "drive D:"
assert_contains "rung-1 refuse is remedy-first (worktreeroot.path)" "$err" "worktreeroot.path"
assert_contains "rung-1 refuse names EXDEV" "$err" "EXDEV"

err=$(check_same_drive 'C:/repos/acme' 'D:/worktrees/acme-x' 2 2>&1 >/dev/null)
assert_exit "rung-2 (worktreeroot.path) cross-drive refuses exit 3" 3 "$?"

err=$(check_same_drive 'C:/repos/acme' 'D:/worktrees/acme-x' 3 2>&1 >/dev/null)
assert_exit "rung-3 (--fallback-root) cross-drive refuses exit 3" 3 "$?"

err=$(check_same_drive 'C:/repos/acme' '/cygdrive/d/worktrees/acme-x' 1 2>&1 >/dev/null)
assert_exit "rung-1 Cygwin foreign drive refuses exit 3" 3 "$?"

err=$(check_same_drive 'C:/repos/acme' 'D:/claude/plugins/cache/worktrees/acme-x' 4 2>&1 >/dev/null)
assert_exit "rung-4 cross-drive refuses exit 3" 3 "$?"
assert_contains "rung-4 refuse names both drives" "$err" "drive C:"
assert_contains "rung-4 refuse names the foreign drive" "$err" "drive D:"
assert_contains "rung-4 refuse is remedy-first (worktreeroot.path)" "$err" "worktreeroot.path"
assert_contains "rung-4 refuse names EXDEV" "$err" "EXDEV"
assert_contains "rung-4 refuse names Improper link" "$err" "Improper link"

assert_real_worktree_root_clean "$TEST_TMPDIR"

repo=$(mkrepo)
git -C "$repo" branch feature
root="$TEST_TMPDIR/wtroot-existing"
errfile="$TEST_TMPDIR/err-existing.txt"
out=$(bash "$HELPER" --name feature --existing-branch --root "$root" --repo-dir "$repo" 2>"$errfile")
assert_exit "existing branch worktree succeeds" 0 "$?"
assert_eq "existing branch worktree is on feature" "feature" \
  "$(git -C "$out" branch --show-current)"
assert_file_exists "existing branch worktree has the commit" "$out/README.md"
bash "$HELPER" --name missing-branch --existing-branch --root "$TEST_TMPDIR/wtroot-missing" --repo-dir "$repo" >/dev/null 2>"$errfile"
assert_exit "missing existing branch is a usage error" 2 "$?"

repo=$(mkrepo)
errfile="$TEST_TMPDIR/err-no-lfs.txt"
out=$(bash "$HELPER" --name feat/no-lfs --root "$TEST_TMPDIR/wtroot-no-lfs" --repo-dir "$repo" 2>"$errfile")
assert_exit "no-LFS create exit 0" 0 "$?"
assert_eq "no-LFS stdout is the worktree path alone" "$TEST_TMPDIR/wtroot-no-lfs/${repo##*/}-feat-no-lfs" "$out"
assert_not_contains "no-LFS create writes no LFS note" "$(cat "$errfile")" "LFS"

if ! git lfs version >/dev/null 2>&1; then
  skip_case "LFS pointer checkout: git lfs is not installed"
else
  repo=$(mkrepo)
  {
    git -C "$repo" lfs install --local
    printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' >"$repo/.gitattributes"
    printf 'large content\n' >"$repo/asset.bin"
    git -C "$repo" add .gitattributes asset.bin
    git -C "$repo" commit -qm "add an LFS asset"
  } >/dev/null 2>&1
  errfile="$TEST_TMPDIR/err-lfs.txt"
  root="$TEST_TMPDIR/wtroot-lfs"
  out=$(bash "$HELPER" --name feat/lfs --root "$root" --base-ref head --repo-dir "$repo" 2>"$errfile")
  assert_exit "LFS create exit 0" 0 "$?"
  assert_eq "LFS stdout is the worktree path alone" "$root/${repo##*/}-feat-lfs" "$out"
  assert_contains "LFS path is a pointer file" "$(head -n 1 "$out/asset.bin")" "version https://git-lfs.github.com/spec/v1"
  err=$(cat "$errfile")
  assert_contains "LFS note says the content was not checked out" "$err" "LFS content was not checked out"
  assert_contains "LFS note names git lfs pull --include <paths>" "$err" "git lfs pull --include <paths>"
  assert_eq "LFS note is one stderr line" 1 "$(grep -c 'LFS content was not checked out' "$errfile")"
fi

fake_bin="$TEST_TMPDIR/fake-npm-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_NPM_LOG"
# A lifecycle script stands in as a child process; its pid goes to FAKE_NPM_CHILD_PID.
[[ -n "${FAKE_NPM_CHILD_PID:-}" ]] && { sleep 60 & echo $! >"$FAKE_NPM_CHILD_PID"; }
sleep "${FAKE_NPM_SLEEP:-0}"
[[ -n "${FAKE_NPM_FAIL_IN_SEED:-}" && "$PWD" == *.tmp ]] && exit 9
mkdir -p node_modules/.bin && : >node_modules/.bin/markdownlint-cli2
exit "${FAKE_NPM_EXIT:-0}"
EOF
chmod +x "$fake_bin/npm"
declare_lockfile() {
  mkdir -p "$1/docs/conventions/ecosystems"
  printf '%s\n' 'globs: ["*.ts"]' 'requires:' '  check-cmd:' '    - name: root toolchain' \
    '      probe: "test -d node_modules"' '      install:' '        manager: npm' \
    '        lockfile: package-lock.json' >"$1/docs/conventions/ecosystems/typescript.yaml"
  git -C "$1" add docs/conventions/ecosystems/typescript.yaml
  git -C "$1" -c commit.gpgsign=false commit -qm record
}
undeclared_repo=$(mkrepo)
commitfile "$undeclared_repo" package-lock.json
deps_repo=$(mkrepo)
commitfile "$deps_repo" package-lock.json
declare_lockfile "$deps_repo"
NPM_CI_ARGS="ci --ignore-scripts --no-audit --no-fund"

npm_log="$TEST_TMPDIR/npm-ok.log"
errfile="$TEST_TMPDIR/err-deps-ok.txt"
out=$(PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" bash "$HELPER" --name feat/deps-ok --base-ref head \
  --root "$TEST_TMPDIR/wtroot-deps" --repo-dir "$deps_repo" 2>"$errfile")
assert_exit "lockfile: creation succeeds" 0 "$?"
assert_eq "lockfile: stdout is still only the worktree path" \
  "$TEST_TMPDIR/wtroot-deps/${deps_repo##*/}-feat-deps-ok" "$out"
assert_eq "lockfile: npm ci ran once" "$NPM_CI_ARGS" "$(cat "$npm_log" 2>/dev/null)"
assert_file_exists "lockfile: node_modules/.bin lands in the new worktree" "$out/node_modules/.bin/markdownlint-cli2"
assert_not_contains "lockfile: a clean install prints no warning" "$(cat "$errfile")" "warning"

npm_log="$TEST_TMPDIR/npm-none.log"
out=$(PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" bash "$HELPER" --name feat/deps-none --base-ref head \
  --root "$TEST_TMPDIR/wtroot-deps" --repo-dir "$(mkrepo)" 2>/dev/null)
assert_exit "no lockfile: creation succeeds" 0 "$?"
assert_file_absent "no lockfile: npm is not run" "$npm_log"

npm_log="$TEST_TMPDIR/npm-undeclared.log"
errfile="$TEST_TMPDIR/err-deps-undeclared.txt"
out=$(PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" bash "$HELPER" --name feat/deps-undeclared --base-ref head \
  --root "$TEST_TMPDIR/wtroot-deps-undeclared" --repo-dir "$undeclared_repo" 2>"$errfile")
assert_exit "undeclared lockfile: creation succeeds" 0 "$?"
assert_eq "undeclared lockfile: npm ci runs once, scripts off" "$NPM_CI_ARGS" "$(cat "$npm_log" 2>/dev/null)"
assert_file_exists "undeclared lockfile: node_modules lands in the new worktree" "$out/node_modules/.bin/markdownlint-cli2"
assert_contains "undeclared lockfile: a notice names the lockfile and the fix" "$(cat "$errfile")" \
  "package-lock.json is installed though no ecosystem record declares it; declare it under requires.<command>[].install"

npm_log="$TEST_TMPDIR/npm-fail.log"
errfile="$TEST_TMPDIR/err-deps-fail.txt"
out=$(PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" FAKE_NPM_EXIT=7 bash "$HELPER" --name feat/deps-fail \
  --base-ref head --root "$TEST_TMPDIR/wtroot-deps-fail" --repo-dir "$deps_repo" 2>"$errfile")
assert_exit "failed install: creation still exits 0" 0 "$?"
assert_file_exists "failed install: worktree exists" "$out/README.md"
assert_contains "failed install: warning names npm's exit code" "$(cat "$errfile")" "npm ci failed (exit 7)"
assert_contains "failed install: warning names the remedy" "$(cat "$errfile")" "run npm ci --ignore-scripts --no-audit --no-fund in $out"

npm_log="$TEST_TMPDIR/npm-slow.log"
errfile="$TEST_TMPDIR/err-deps-slow.txt"
child_pid_file="$TEST_TMPDIR/npm-slow-child.pid"
start=$SECONDS
out=$(PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" FAKE_NPM_SLEEP=30 FAKE_NPM_CHILD_PID="$child_pid_file" \
  WORKTREE_CREATE_DEPS_CAP_SECONDS=3 bash "$HELPER" --name feat/deps-slow --base-ref head \
  --root "$TEST_TMPDIR/wtroot-deps-slow" --repo-dir "$deps_repo" 2>"$errfile")
rc=$?
elapsed=$((SECONDS - start))
assert_exit "capped install: creation still exits 0" 0 "$rc"
assert_contains "capped install: warning names the cap" "$(cat "$errfile")" "did not finish within 3s"
assert_contains "capped install: warning names the remedy" "$(cat "$errfile")" "run npm ci --ignore-scripts --no-audit --no-fund in $out"
child_pid=$(cat "$child_pid_file" 2>/dev/null)
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -z "$child_pid" ]] || ! kill -0 "$child_pid" 2>/dev/null; then break; fi
  sleep 0.2
done
if [[ -n "$child_pid" ]] && ! kill -0 "$child_pid" 2>/dev/null; then
  pass "capped install: a child of npm does not outlive the cap"
else
  fail "capped install: a child of npm does not outlive the cap" "child stopped" "pid '${child_pid}' alive or unrecorded"
  [[ -n "$child_pid" ]] && kill "$child_pid" 2>/dev/null
fi
if ((elapsed < 15)); then
  pass "capped install: returns well before the 30s install would finish"
else
  fail "capped install: returns well before the 30s install would finish" "<15s" "${elapsed}s"
fi

npm_log="$TEST_TMPDIR/npm-octal.log"
errfile="$TEST_TMPDIR/err-deps-octal.txt"
out=$(PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" FAKE_NPM_SLEEP=0.5 \
  WORKTREE_CREATE_DEPS_CAP_SECONDS=08 bash "$HELPER" --name feat/deps-octal --base-ref head \
  --root "$TEST_TMPDIR/wtroot-deps-octal" --repo-dir "$deps_repo" 2>"$errfile")
assert_exit "cap 08: creation succeeds" 0 "$?"
assert_contains "cap 08: the cap is read as 8 seconds" "$(cat "$errfile")" "capped at 8s"
assert_not_contains "cap 08: no octal arithmetic error" "$(cat "$errfile")" "value too great for base"
assert_not_contains "cap 08: the install is not stopped" "$(cat "$errfile")" "warning"
assert_file_exists "cap 08: node_modules/.bin lands in the new worktree" "$out/node_modules/.bin/markdownlint-cli2"

npm_log="$TEST_TMPDIR/npm-noslash.log"
out=$(cd "$SCRIPT_DIR" && PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" WORKTREE_CREATE_NPM_SEED=0 \
  bash worktree-create.sh --name feat/deps-noslash --base-ref head \
  --root "$TEST_TMPDIR/wtroot-deps-noslash" --repo-dir "$deps_repo" 2>/dev/null)
assert_exit "no slash in the helper path: creation succeeds" 0 "$?"
assert_eq "no slash in the helper path: npm ci runs" "$NPM_CI_ARGS" "$(cat "$npm_log" 2>/dev/null)"
assert_file_exists "no slash in the helper path: node_modules lands in the worktree" "$out/node_modules/.bin/markdownlint-cli2"

if compgen -G "$TEST_TMPDIR/wtroot-deps-fail/.npm-seed/*/.complete" >/dev/null; then
  fail "failed install: no finished seed is kept" "no .complete" "a .complete exists"
else
  pass "failed install: no finished seed is kept"
fi

probe="$TEST_TMPDIR/cp-al-probe"
mkdir -p "$probe/a" && : >"$probe/a/f"
if command -v flock >/dev/null 2>&1 && command -v node >/dev/null 2>&1 && cp -al "$probe/a" "$probe/b" 2>/dev/null && [[ "$probe/a/f" -ef "$probe/b/f" ]]; then
  seed_root="$TEST_TMPDIR/wtroot-seed"
  npm_log="$TEST_TMPDIR/npm-seed.log"
  first=$(PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" bash "$HELPER" --name feat/seed-one --base-ref head \
    --root "$seed_root" --repo-dir "$deps_repo" 2>/dev/null)
  errfile="$TEST_TMPDIR/err-seed-two.txt"
  second=$(PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" bash "$HELPER" --name feat/seed-two --base-ref head \
    --root "$seed_root" --repo-dir "$deps_repo" 2>"$errfile")
  assert_exit "seed: second worktree on the same lockfile succeeds" 0 "$?"
  assert_eq "seed: npm ci ran once for two worktrees" "$NPM_CI_ARGS" "$(cat "$npm_log" 2>/dev/null)"
  if [[ "$first/node_modules/.bin/markdownlint-cli2" -ef "$second/node_modules/.bin/markdownlint-cli2" ]]; then
    pass "seed: both worktrees hard-link the same file"
  else
    fail "seed: both worktrees hard-link the same file" "same inode" "different files"
  fi
  assert_contains "seed: stderr names the shared seed" "$(cat "$errfile")" "linked node_modules from the shared seed"

  npm_log="$TEST_TMPDIR/npm-seed-off.log"
  off=$(PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" WORKTREE_CREATE_NPM_SEED=0 bash "$HELPER" --name feat/seed-off \
    --base-ref head --root "$seed_root" --repo-dir "$deps_repo" 2>/dev/null)
  assert_eq "seed off: npm ci runs in the worktree" "$NPM_CI_ARGS" "$(cat "$npm_log" 2>/dev/null)"
  if [[ "$off/node_modules/.bin/markdownlint-cli2" -ef "$first/node_modules/.bin/markdownlint-cli2" ]]; then
    fail "seed off: node_modules is the worktree's own" "own file" "linked to the seed"
  else
    pass "seed off: node_modules is the worktree's own"
  fi

  stale="$seed_root/.npm-seed/stale0000"
  mkdir -p "$stale/node_modules" && : >"$stale/.complete" && touch -d '30 days ago' "$stale/.complete"
  PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$TEST_TMPDIR/npm-seed-prune.log" bash "$HELPER" --name feat/seed-prune \
    --base-ref head --root "$seed_root" --repo-dir "$deps_repo" >/dev/null 2>&1
  if [[ -e "$stale" ]]; then
    fail "seed: a seed unused for 30 days is pruned" "removed" "still present"
  else
    pass "seed: a seed unused for 30 days is pruned"
  fi
  seed_dir=$(sed -n 's/.*linked node_modules from the shared seed //p' "$TEST_TMPDIR/err-seed-two.txt" | head -n 1)
  seed_file="$seed_dir/node_modules/.bin/markdownlint-cli2"
  if ((EUID == 0)); then
    skip_case "running as root, which writes read-only files"
  elif [[ -n "$seed_file" && ! -w "$seed_file" ]]; then
    pass "seed: the seed's files are read-only"
  else
    fail "seed: the seed's files are read-only" "not writable" "writable or missing"
  fi

  npm_log="$TEST_TMPDIR/npm-seed-env.log"
  PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" NODE_ENV=production bash "$HELPER" --name feat/seed-env \
    --base-ref head --root "$seed_root" --repo-dir "$deps_repo" >/dev/null 2>&1
  assert_eq "seed: a different NODE_ENV builds its own seed" "$NPM_CI_ARGS" "$(cat "$npm_log" 2>/dev/null)"

  flock "$seed_dir.lock" sleep 10 &
  holder=$!
  sleep 0.5
  errfile="$TEST_TMPDIR/err-seed-wait.txt"
  start=$SECONDS
  PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$TEST_TMPDIR/npm-seed-wait.log" WORKTREE_CREATE_DEPS_CAP_SECONDS=2 \
    bash "$HELPER" --name feat/seed-wait --base-ref head --root "$seed_root" --repo-dir "$deps_repo" >/dev/null 2>"$errfile"
  elapsed=$((SECONDS - start))
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
  if ((elapsed < 6)); then
    pass "seed: the lock wait and the install share one cap"
  else
    fail "seed: the lock wait and the install share one cap" "<6s" "${elapsed}s"
  fi
  assert_contains "seed: a spent cap warns with the remedy" "$(cat "$errfile")" "did not finish within 2s"

  npm_log="$TEST_TMPDIR/npm-seed-fallback.log"
  errfile="$TEST_TMPDIR/err-seed-fallback.txt"
  fb=$(PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" FAKE_NPM_FAIL_IN_SEED=1 bash "$HELPER" --name feat/seed-fallback \
    --base-ref head --root "$TEST_TMPDIR/wtroot-seed-fallback" --repo-dir "$deps_repo" 2>"$errfile")
  assert_eq "seed fallback: a failed seed install retries in the worktree" "2" "$(wc -l <"$npm_log" | tr -d ' ')"
  assert_file_exists "seed fallback: the worktree still gets node_modules" "$fb/node_modules/.bin/markdownlint-cli2"
  assert_not_contains "seed fallback: the retry prints no warning" "$(cat "$errfile")" "warning"

  script_repo=$(mkrepo)
  printf '{"scripts":{"prepare":"node setup.js"}}\n' >"$script_repo/package.json"
  git -C "$script_repo" add package.json
  git -C "$script_repo" -c commit.gpgsign=false commit -qm package
  commitfile "$script_repo" package-lock.json
  declare_lockfile "$script_repo"
  npm_log="$TEST_TMPDIR/npm-seed-script.log"
  PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$npm_log" bash "$HELPER" --name feat/seed-script --base-ref head \
    --root "$TEST_TMPDIR/wtroot-seed-script" --repo-dir "$script_repo" >/dev/null 2>&1
  assert_eq "seed: a package with a lifecycle script installs in the worktree" "$NPM_CI_ARGS" "$(cat "$npm_log" 2>/dev/null)"
  if compgen -G "$TEST_TMPDIR/wtroot-seed-script/.npm-seed/*/.complete" >/dev/null; then
    fail "seed: no seed is built for a package with a lifecycle script" "no seed" "a seed exists"
  else
    pass "seed: no seed is built for a package with a lifecycle script"
  fi

  if compgen -G "$seed_root/.npm-seed/*/node_modules/.bin/markdownlint-cli2" >/dev/null; then
    pass "seed: the seed in use is kept"
  else
    fail "seed: the seed in use is kept" "seed present" "no seed"
  fi
else
  skip_case "flock, node or a hard-linking cp -al is unavailable; the shared seed is not used here"
fi

no_npm_path=""
if command -v node >/dev/null 2>&1; then
  mkdir -p "$TEST_TMPDIR/node-only-bin"
  ln -sf "$(node -p process.execPath)" "$TEST_TMPDIR/node-only-bin/node"
  no_npm_path="$TEST_TMPDIR/node-only-bin"
fi
IFS=: read -r -a path_dirs <<<"$PATH"
for d in "${path_dirs[@]}"; do
  [[ -n "$d" && ! -x "$d/npm" ]] && no_npm_path="${no_npm_path:+$no_npm_path:}$d"
done
if PATH="$no_npm_path" command -v node >/dev/null 2>&1 && PATH="$no_npm_path" command -v git >/dev/null 2>&1 &&
  PATH="$no_npm_path" command -v bash >/dev/null 2>&1; then
  errfile="$TEST_TMPDIR/err-deps-nonpm.txt"
  bash_bin=$(command -v bash)
  out=$(PATH="$no_npm_path" "$bash_bin" "$HELPER" --name feat/deps-nonpm --base-ref head \
    --root "$TEST_TMPDIR/wtroot-deps" --repo-dir "$deps_repo" 2>"$errfile")
  assert_exit "no npm: creation still exits 0" 0 "$?"
  assert_file_exists "no npm: worktree exists" "$out/README.md"
  assert_contains "no npm: warning says npm is missing and names the entry" "$(cat "$errfile")" \
    "npm is not on PATH; root toolchain (package-lock.json) not provisioned"
  assert_contains "no npm: warning names the remedy" "$(cat "$errfile")" \
    "run npm $NPM_CI_ARGS in $out"
else
  skip_case "node is unavailable, or npm shares a PATH directory with git or bash; cannot hide it"
fi

libless="$TEST_TMPDIR/libless/scripts"
mkdir -p "$libless/lib"
cp "$HELPER" "$libless/worktree-create.sh"
cp "$SCRIPT_DIR/lib/worktree-facts.sh" "$libless/lib/"
code=0
err=$(bash "$libless/worktree-create.sh" --help 2>&1 >/dev/null) || code=$?
assert_exit "missing worktree-root-resolve.sh exits 4" 4 "$code"
assert_contains "missing worktree-root-resolve.sh names it" "$err" "cannot load worktree-root-resolve.sh"
cp "$SCRIPT_DIR/worktree-root-resolve.sh" "$SCRIPT_DIR/worktree-root-legacy.sh" "$libless/"
code=0
err=$(bash "$libless/worktree-create.sh" --help 2>&1 >/dev/null) || code=$?
assert_exit "missing hooks/worktree-path-lib.sh exits 4" 4 "$code"
assert_contains "missing hooks/worktree-path-lib.sh names it" "$err" "cannot load hooks/worktree-path-lib.sh"

mkinputs() {
  mkdir -p "$1"
  # shellcheck disable=SC2016 # the literal unexpanded token is the point
  printf '%s' '${user_config.worktree_root}' >"$1/worktree-root"
  printf '%s' "$DATA_DIR" >"$1/data-root"
}
dir_state() { [[ -e "$1" ]] && echo present || echo absent; }
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
inputs="$TEST_TMPDIR/inputs-ok"
mkinputs "$inputs"
out=$(bash "$HELPER" --name feat/rm-inputs --fallback-root-file "$inputs/worktree-root" \
  --data-root-file "$inputs/data-root" --repo-dir "$repo" --remove-input-files 2>/dev/null)
assert_exit "--remove-input-files: create exits 0" 0 "$?"
assert_file_exists "--remove-input-files: worktree created" "$out/README.md"
assert_eq "--remove-input-files: input dir removed after success" absent "$(dir_state "$inputs")"

inputs="$TEST_TMPDIR/inputs-refused"
mkinputs "$inputs"
code=0
bash "$HELPER" --name 'feat/foo..bar' --fallback-root-file "$inputs/worktree-root" \
  --data-root-file "$inputs/data-root" --repo-dir "$repo" --remove-input-files >/dev/null 2>&1 || code=$?
assert_exit "--remove-input-files: invalid name still exits 2" 2 "$code"
assert_eq "--remove-input-files: input dir removed after a refusal" absent "$(dir_state "$inputs")"

inputs="$TEST_TMPDIR/inputs-usage"
mkinputs "$inputs"
code=0
bash "$HELPER" --data-root-file "$inputs/data-root" --fallback-root-file "$inputs/worktree-root" \
  --remove-input-files --bogus >/dev/null 2>&1 || code=$?
assert_exit "--remove-input-files: unknown flag still exits 2" 2 "$code"
assert_eq "--remove-input-files: input dir removed after a later usage error" absent "$(dir_state "$inputs")"

inputs="$TEST_TMPDIR/inputs-shared"
mkinputs "$inputs"
printf 'x\n' >"$inputs/unrelated"
bash "$HELPER" --name feat/rm-shared --fallback-root-file "$inputs/worktree-root" \
  --data-root-file "$inputs/data-root" --repo-dir "$repo" --remove-input-files >/dev/null 2>&1
assert_file_absent "--remove-input-files: handed file removed from a shared dir" "$inputs/data-root"
assert_file_exists "--remove-input-files: an unrelated file is kept" "$inputs/unrelated"

inputs="$TEST_TMPDIR/inputs-kept"
mkinputs "$inputs"
bash "$HELPER" --name feat/keep-inputs --fallback-root-file "$inputs/worktree-root" \
  --data-root-file "$inputs/data-root" --repo-dir "$repo" >/dev/null 2>&1
assert_file_exists "without --remove-input-files the input files stay" "$inputs/data-root"

conventionrepo() {
  local repo
  repo=$(mkrepo --origin "git@github.com:acme/widget.git")
  mkdir -p "$repo/docs/conventions"
  printf '%s\n' "$1" >"$repo/docs/conventions/source-control.yaml"
  {
    git -C "$repo" add docs/conventions/source-control.yaml
    git -C "$repo" commit -qm "add the source-control convention"
  } >/dev/null 2>&1
  printf '%s' "$repo"
}

branch_for() {
  local out
  out=$(bash "$HELPER" --name "$2" --root "$(mktemp -d "$TEST_TMPDIR/wtbranchXXXXXX")/wt" --repo-dir "$1" 2>/dev/null) || return 0
  git -C "$out" rev-parse --abbrev-ref HEAD 2>/dev/null
}

CONVENTIONAL='worktree_branch_naming: conventional-commits'
AGENT_PREFIXES="$CONVENTIONAL
worktree_branch_extra_prefixes:
  - claude
  - codex
  - cursor
  - copilot
  - dependabot"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
assert_eq "no convention file: the branch is the raw name" "agent-abc123" "$(branch_for "$repo" agent-abc123)"
repo=$(conventionrepo 'pr_open_state: ready')
assert_eq "a convention file without the key: the branch is the raw name" "agent-abc123" "$(branch_for "$repo" agent-abc123)"
repo=$(conventionrepo 'worktree_branch_naming: verbatim')
assert_eq "verbatim: the branch is the raw name" "agent-abc123" "$(branch_for "$repo" agent-abc123)"
code=0
bash "$HELPER" --name 'feat/foo..bar' --root "$TEST_TMPDIR/wtbranch-verbatim-bad" --repo-dir "$repo" >/dev/null 2>&1 || code=$?
assert_exit "verbatim: a git-invalid name is still refused (exit 2)" 2 "$code"

repo=$(conventionrepo "$CONVENTIONAL")
assert_eq "a name without a slash takes the default type" "chore/agent-abc123" "$(branch_for "$repo" agent-abc123)"
assert_eq "a dash-delimited agent word is not a type" "chore/claude-code-updates" "$(branch_for "$repo" claude-code-updates)"
assert_eq "a known type passes through" "feat/login-form" "$(branch_for "$repo" feat/login-form)"
assert_eq "an unknown type falls back to the default type over the whole name" "chore/wip-spike" "$(branch_for "$repo" wip/spike)"
assert_eq "an agent prefix outside the extra list is not a type" "chore/codex-fix-thing" "$(branch_for "$repo" codex/fix-thing)"
assert_eq "a type matches in any case; the description keeps its case" "feat/Upper-Case" "$(branch_for "$repo" FEAT/Upper-Case)"
assert_eq "hotfix is a fix alias" "fix/urgent" "$(branch_for "$repo" hotfix/urgent)"
assert_eq "documentation is a docs alias" "docs/guide" "$(branch_for "$repo" documentation/guide)"
assert_eq "repeated dots in the description collapse" "feat/a.b" "$(branch_for "$repo" feat/a..b)"
assert_eq "a trailing .lock is stripped" "feat/x" "$(branch_for "$repo" feat/x.lock)"
out=$(bash "$HELPER" --name "feat/-" --root "$TEST_TMPDIR/wtbranch-nodesc" --repo-dir "$repo" 2>"$TEST_TMPDIR/nodesc.err")
assert_eq "a known type with no description falls back to the default type" "chore/feat" \
  "$(git -C "$out" rev-parse --abbrev-ref HEAD 2>/dev/null)"
assert_contains "a dropped known type is named on stderr" "$(cat "$TEST_TMPDIR/nodesc.err")" "no description"
code=0
out=$(bash "$HELPER" --name "_" --root "$TEST_TMPDIR/wtbranch-empty" --repo-dir "$repo" 2>"$TEST_TMPDIR/empty.err") || code=$?
assert_exit "a name that sanitizes to nothing still creates (exit 0)" 0 "$code"
assert_eq "a name that sanitizes to nothing keeps the raw name" "_" \
  "$(git -C "$out" rev-parse --abbrev-ref HEAD 2>/dev/null)"
assert_contains "the verbatim fallback is named on stderr" "$(cat "$TEST_TMPDIR/empty.err")" "empty description"
bash "$HELPER" --name "wip/quiet" --root "$TEST_TMPDIR/wtbranch-quiet" --repo-dir "$repo" >/dev/null 2>"$TEST_TMPDIR/quiet.err"
assert_not_contains "an unknown type falls back without that note" "$(cat "$TEST_TMPDIR/quiet.err")" "no description"
assert_contains "the derived branch is named on stderr" "$(cat "$TEST_TMPDIR/quiet.err")" "chore/wip-quiet"

repo=$(conventionrepo "$CONVENTIONAL")
root="$TEST_TMPDIR/wtbranch-slug"
out=$(bash "$HELPER" --name feature/login-form --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "the directory slug comes from the raw name" "$root/acme-widget-feature-login-form" "$out"
assert_eq "feature is a feat alias" "feat/login-form" "$(git -C "$out" rev-parse --abbrev-ref HEAD 2>/dev/null)"

repo=$(conventionrepo "$AGENT_PREFIXES")
assert_eq "an extra prefix passes through" "codex/fix-thing" "$(branch_for "$repo" codex/fix-thing)"
assert_eq "an extra prefix matches in any case and is written as listed" "claude/task" "$(branch_for "$repo" Claude/task)"
assert_eq "later slashes in the description become dashes" "dependabot/nuget-Foo.Bar" \
  "$(branch_for "$repo" dependabot/nuget/Foo.Bar)"
assert_eq "an extra prefix list leaves the no-slash default alone" "chore/claude-code-updates" \
  "$(branch_for "$repo" claude-code-updates)"

repo=$(conventionrepo "$CONVENTIONAL
worktree_branch_default_type: build")
assert_eq "worktree_branch_default_type replaces chore" "build/agent-abc123" "$(branch_for "$repo" agent-abc123)"
repo=$(conventionrepo "$CONVENTIONAL
worktree_branch_default_type: 'Not/A Type'")
bash "$HELPER" --name agent-def --root "$TEST_TMPDIR/wtbranch-badtype" --repo-dir "$repo" >/dev/null 2>"$TEST_TMPDIR/badtype.err"
assert_eq "an invalid default type falls back to chore" "chore/agent-def" \
  "$(git -C "$TEST_TMPDIR/wtbranch-badtype/acme-widget-agent-def" rev-parse --abbrev-ref HEAD 2>/dev/null)"
assert_contains "an invalid default type is named on stderr" "$(cat "$TEST_TMPDIR/badtype.err")" "worktree_branch_default_type"

repo=$(conventionrepo 'worktree_branch_naming: kebab')
bash "$HELPER" --name agent-ghi --root "$TEST_TMPDIR/wtbranch-unknown" --repo-dir "$repo" >/dev/null 2>"$TEST_TMPDIR/unknown.err"
assert_exit "an unknown worktree_branch_naming value still creates (exit 0)" 0 "$?"
assert_eq "an unknown worktree_branch_naming value keeps the raw name" "agent-ghi" \
  "$(git -C "$TEST_TMPDIR/wtbranch-unknown/acme-widget-agent-ghi" rev-parse --abbrev-ref HEAD 2>/dev/null)"
assert_contains "an unknown value is named on stderr" "$(cat "$TEST_TMPDIR/unknown.err")" "worktree_branch_naming"
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
mkdir -p "$repo/docs/conventions"
printf '%s\n' "$CONVENTIONAL" >"$repo/docs/conventions/source-control.yaml"
assert_eq "an untracked convention file is not read" "agent-abc123" "$(branch_for "$repo" agent-abc123)"
repo=$(conventionrepo "$CONVENTIONAL
$CONVENTIONAL")
bash "$HELPER" --name agent-jkl --root "$TEST_TMPDIR/wtbranch-rejected" --repo-dir "$repo" >/dev/null 2>"$TEST_TMPDIR/rejected.err"
assert_eq "a rejected YAML keeps the raw name" "agent-jkl" \
  "$(git -C "$TEST_TMPDIR/wtbranch-rejected/acme-widget-agent-jkl" rev-parse --abbrev-ref HEAD 2>/dev/null)"
assert_contains "a rejected YAML is named on stderr" "$(cat "$TEST_TMPDIR/rejected.err")" "source-control.yaml"

repo=$(conventionrepo "$CONVENTIONAL")
git -C "$repo" branch parked-work >/dev/null 2>&1
out=$(bash "$HELPER" --name parked-work --existing-branch --root "$TEST_TMPDIR/wtbranch-existing" --repo-dir "$repo" 2>/dev/null)
assert_eq "--existing-branch keeps the named branch" "parked-work" "$(git -C "$out" rev-parse --abbrev-ref HEAD 2>/dev/null)"

lock_reason_of() { tr -d '\r\n' <"$(git -C "$1" rev-parse --absolute-git-dir)/locked" 2>/dev/null; }
reuse_cfg="$TEST_TMPDIR/reuse-config"
mkdir -p "$reuse_cfg/projects/p" "$reuse_cfg/sessions"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
printf '*.env\n' >"$repo/.gitignore"
printf '*.env\n' >"$repo/.worktreeinclude"
git -C "$repo" add .gitignore .worktreeinclude >/dev/null 2>&1
git -C "$repo" commit -qm "ignore + include" >/dev/null 2>&1
printf 'from-main\n' >"$repo/local.env"
root="$TEST_TMPDIR/wtreuse-own"
first=$(CLAUDE_CONFIG_DIR="$reuse_cfg" bash "$HELPER" --name feat/again --root "$root" --session-id s-own --repo-dir "$repo" 2>/dev/null)
printf 'edited-in-tree\n' >"$first/local.env"
reason_before="$(lock_reason_of "$first")"
code=0
second=$(CLAUDE_CONFIG_DIR="$reuse_cfg" bash "$HELPER" --name feat/again --root "$root" --session-id s-own \
  --repo-dir "$repo" 2>"$TEST_TMPDIR/reuse-own.err") || code=$?
assert_exit "same session, same name: reuse exits 0" 0 "$code"
assert_eq "same session, same name: the same path on stdout" "$first" "$second"
assert_eq "reuse does not copy .worktreeinclude files over the tree's edits" "edited-in-tree" "$(cat "$first/local.env")"
assert_eq "reuse keeps the session's lock as it was" "$reason_before" "$(lock_reason_of "$first")"
assert_contains "reuse is named on stderr" "$(cat "$TEST_TMPDIR/reuse-own.err")" "reusing"

: >"$reuse_cfg/projects/p/s-live.jsonl"
root="$TEST_TMPDIR/wtreuse-live"
first=$(CLAUDE_CONFIG_DIR="$reuse_cfg" bash "$HELPER" --name feat/held --root "$root" --session-id s-live --repo-dir "$repo" 2>/dev/null)
code=0
err=$(CLAUDE_CONFIG_DIR="$reuse_cfg" bash "$HELPER" --name feat/held --root "$root" --session-id s-new \
  --repo-dir "$repo" 2>&1 >/dev/null) || code=$?
assert_exit "a live foreign session's worktree refuses (exit 4)" 4 "$code"
assert_contains "the refusal names the live session's claim" "$err" "session s-live since"
assert_contains "the live session's lock is kept" "$(lock_reason_of "$first")" "session s-live since"

root="$TEST_TMPDIR/wtreuse-stale"
first=$(CLAUDE_CONFIG_DIR="$reuse_cfg" bash "$HELPER" --name feat/relaunch --root "$root" --session-id s-gone --repo-dir "$repo" 2>/dev/null)
code=0
second=$(CLAUDE_CONFIG_DIR="$reuse_cfg" bash "$HELPER" --name feat/relaunch --root "$root" --session-id s-next \
  --repo-dir "$repo" 2>"$TEST_TMPDIR/reuse-stale.err") || code=$?
assert_exit "a stale foreign session's worktree is taken over (exit 0)" 0 "$code"
assert_eq "a stale takeover prints the same path" "$first" "$second"
bash "$CLAIM" check-enter "$first" --repo-dir "$repo" --session-id s-next >/dev/null 2>&1
assert_exit "after the takeover check-enter treats the tree as this session's" 0 "$?"
assert_contains "the takeover keeps the creating helper in the reason" "$(lock_reason_of "$first")" "worktree-create.sh:"

root="$TEST_TMPDIR/wtreuse-anon"
first=$(bash "$HELPER" --name feat/anon --root "$root" --repo-dir "$repo" 2>/dev/null)
code=0
err=$(CLAUDE_CONFIG_DIR="$reuse_cfg" bash "$HELPER" --name feat/anon --root "$root" --session-id s-any \
  --repo-dir "$repo" 2>&1 >/dev/null) || code=$?
assert_exit "a lock naming no session refuses (exit 4)" 4 "$code"
assert_contains "the refusal says the lock names no session" "$err" "names no session"
root="$TEST_TMPDIR/wtreuse-reasonless"
first=$(bash "$HELPER" --name feat/bare-lock --root "$root" --session-id s-hand --repo-dir "$repo" 2>/dev/null)
git -C "$repo" worktree unlock "$first" >/dev/null 2>&1
git -C "$repo" worktree lock "$first" >/dev/null 2>&1
code=0
bash "$HELPER" --name feat/bare-lock --root "$root" --session-id s-hand --repo-dir "$repo" >/dev/null 2>&1 || code=$?
assert_exit "a lock with no reason refuses (exit 4)" 4 "$code"
root="$TEST_TMPDIR/wtreuse-nosid"
first=$(bash "$HELPER" --name feat/nosid-again --root "$root" --session-id s-a --repo-dir "$repo" 2>/dev/null)
code=0
err=$(bash "$HELPER" --name feat/nosid-again --root "$root" --repo-dir "$repo" 2>&1 >/dev/null) || code=$?
assert_exit "reuse without --session-id refuses (exit 4)" 4 "$code"
assert_contains "the refusal names --session-id as the remedy" "$err" "--session-id"

root="$TEST_TMPDIR/wtreuse-unlocked"
mkdir -p "$root"
git -C "$repo" worktree add -q -b feat/plain "$root/acme-widget-feat-plain" >/dev/null 2>&1
code=0
bash "$HELPER" --name feat/plain --root "$root" --repo-dir "$repo" >/dev/null 2>&1 || code=$?
assert_exit "an unlocked worktree without --session-id refuses (exit 4)" 4 "$code"
code=0
out=$(bash "$HELPER" --name feat/plain --root "$root" --session-id s-adopt --repo-dir "$repo" 2>/dev/null) || code=$?
assert_exit "an unlocked worktree is claimed and reused (exit 0)" 0 "$code"
assert_eq "the claimed worktree's path is printed" "$root/acme-widget-feat-plain" "$out"
assert_contains "the claim names this session" "$(lock_reason_of "$out")" "session s-adopt since"

root="$TEST_TMPDIR/wtreuse-mismatch"
mkdir -p "$root"
git -C "$repo" worktree add -q -b other-branch "$root/acme-widget-feat-mismatch" >/dev/null 2>&1
code=0
err=$(bash "$HELPER" --name feat/mismatch --root "$root" --session-id s-m --repo-dir "$repo" 2>&1 >/dev/null) || code=$?
assert_exit "a worktree at the target on another branch refuses (exit 4)" 4 "$code"
assert_contains "the refusal names the branch it holds" "$err" "other-branch"
mkdir -p "$TEST_TMPDIR/wtreuse-dir/acme-widget-feat-dir"
code=0
err=$(bash "$HELPER" --name feat/dir --root "$TEST_TMPDIR/wtreuse-dir" --session-id s-d --repo-dir "$repo" 2>&1 >/dev/null) || code=$?
assert_exit "a plain directory at the target refuses (exit 4)" 4 "$code"
assert_contains "the refusal says the path is not a worktree" "$err" "not a worktree of this repository"

root="$TEST_TMPDIR/wtreuse-branch"
first=$(bash "$HELPER" --name feat/reentry --root "$root" --session-id s-1 --repo-dir "$repo" 2>/dev/null)
commitfile "$first" kept.txt
git -C "$repo" worktree unlock "$first" >/dev/null 2>&1
git -C "$repo" worktree remove --force "$first" >/dev/null 2>&1
code=0
second=$(bash "$HELPER" --name feat/reentry --root "$root" --session-id s-2 --repo-dir "$repo" 2>"$TEST_TMPDIR/reuse-branch.err") || code=$?
assert_exit "an existing branch with no worktree is checked out again (exit 0)" 0 "$code"
assert_eq "the re-entry lands at the same path" "$first" "$second"
assert_eq "the re-entry is on the existing branch" "feat/reentry" "$(git -C "$second" branch --show-current 2>/dev/null)"
assert_file_exists "the existing branch's commits are kept" "$second/kept.txt"
assert_contains "the re-entry's lock names this session" "$(lock_reason_of "$second")" "session s-2 since"
assert_contains "stderr says the existing branch was used" "$(cat "$TEST_TMPDIR/reuse-branch.err")" "existing branch"

repo=$(conventionrepo "$CONVENTIONAL")
root="$TEST_TMPDIR/wtreuse-derived"
first=$(bash "$HELPER" --name feat/x --root "$root" --session-id s-x --repo-dir "$repo" 2>/dev/null)
code=0
err=$(bash "$HELPER" --name feature/x --root "$root" --session-id s-x --repo-dir "$repo" 2>&1 >/dev/null) || code=$?
assert_exit "a derived branch held by another worktree refuses (exit 4)" 4 "$code"
assert_contains "the refusal names the worktree holding the branch" "$err" "$(native_path "$first")"
assert_file_absent "the second name's directory is not created" "$root/acme-widget-feature-x/README.md"
git -C "$repo" switch -q -c fix/main-held >/dev/null 2>&1
code=0
err=$(bash "$HELPER" --name fix/main-held --root "$root" --session-id s-x --repo-dir "$repo" 2>&1 >/dev/null) || code=$?
assert_exit "a branch checked out in the main worktree refuses (exit 4)" 4 "$code"
assert_contains "the refusal names the main worktree" "$err" "$(native_path "$repo")"
code=0
bash "$HELPER" --name fix/main-held --existing-branch --root "$root" --repo-dir "$repo" >/dev/null 2>&1 || code=$?
assert_exit "--existing-branch on a branch held elsewhere refuses (exit 4)" 4 "$code"

repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/wtreuse-prefix"
bash "$HELPER" --name feat-login-form --root "$root" --session-id s-p --repo-dir "$repo" >/dev/null 2>&1
code=0
out=$(bash "$HELPER" --name feat-login --root "$root" --session-id s-p --repo-dir "$repo" 2>/dev/null) || code=$?
assert_exit "a prefix of a registered worktree's name is created (exit 0)" 0 "$code"
assert_eq "the prefix name gets its own path" "$root/acme-widget-feat-login" "$out"
assert_eq "the prefix name gets its own branch" "feat-login" "$(git -C "$out" branch --show-current 2>/dev/null)"

[[ $FAILED -eq 0 ]] || exit 1
