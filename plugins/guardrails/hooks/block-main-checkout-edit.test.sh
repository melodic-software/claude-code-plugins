#!/usr/bin/env bash

# test-scope: plugins/guardrails/hooks/hooks.json plugins/guardrails/.claude-plugin/plugin.json
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_UNDER_TEST="$HOOK_DIR/block-main-checkout-edit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_MAIN_CHECKOUT_EDIT_ENABLED
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES

export HOME="$TEST_TMPDIR/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME"
g() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

T="$(cd -P "$TEST_TMPDIR" && pwd)"
g init -q --bare "$T/origin.git"
g init -q "$T/seed"
printf 'ignored.txt\nbuild/\n' >"$T/seed/.gitignore"
printf 'a\n' >"$T/seed/a.txt"
printf 'x\n' >"$T/seed/build-keep.txt"
printf '{}\n' >"$T/seed/nb.ipynb"
mkdir -p "$T/seed/build"
printf 'forced\n' >"$T/seed/build/forced.txt"
mkdir -p "$T/seed/src"
printf 'b\n' >"$T/seed/src/b.txt"
g -C "$T/seed" add .gitignore a.txt build-keep.txt nb.ipynb src/b.txt
g -C "$T/seed" add -f build/forced.txt
g -C "$T/seed" commit -q -m init
g -C "$T/seed" push -q "$T/origin.git" main
g clone -q "$T/origin.git" "$T/main"
assert_eq "fixture: clone records origin/HEAD" "refs/remotes/origin/main" \
  "$(git -C "$T/main" symbolic-ref -q refs/remotes/origin/HEAD)"

deny() {
  local label="$1" payload="$2" via
  shift 2
  for via in direct dispatched; do
    guard_invoke --via "$via" --payload "$payload" "$@"
    assert_exit "$label ($via)" 2 "$GUARD_RC"
    assert_contains "$label ($via): names the branch" "$GUARD_ERR" "on its default branch main"
    assert_contains "$label ($via): points at the convention" "$GUARD_ERR" "AGENTS.md"
    assert_contains "$label ($via): gives the headless route" "$GUARD_ERR" "worktree add"
  done
}
allow() {
  local label="$1" payload="$2"
  shift 2
  expect_both "$label" 0 --payload "$payload" "$@"
}

expect_both "unset option: off by default, an edit in a main checkout passes" 0 \
  --payload "$(edit_json "$T/main/a.txt" b)" -- -u CLAUDE_PLUGIN_OPTION_BLOCK_MAIN_CHECKOUT_EDIT_ENABLED
assert_eq "plugin.json default matches the script fallback" false \
  "$(jq -r '.userConfig.block_main_checkout_edit_enabled.default' "$HOOK_DIR/../.claude-plugin/plugin.json")"
export CLAUDE_PLUGIN_OPTION_BLOCK_MAIN_CHECKOUT_EDIT_ENABLED=true

deny "Edit of a tracked file" "$(edit_json "$T/main/a.txt" b)"
assert_contains "reason gives the path to repeat the edit at" "$GUARD_ERR" "<worktree>/a.txt"
deny "Write of a new file that is not ignored" "$(write_json "$T/main/new.txt" n)"
deny "Write into a directory that does not exist yet" "$(write_json "$T/main/new/dir/f.txt" n)"
deny "NotebookEdit of a tracked notebook" "$(notebook_json "$T/main/nb.ipynb" s)"
deny "tracked file under an ignored pattern" "$(edit_json "$T/main/build/forced.txt" y)"
deny "an inherited GIT_DIR does not redirect the check" "$(edit_json "$T/main/a.txt" b)" \
  -- "GIT_DIR=$T/origin.git"

g clone -q --separate-git-dir "$T/sep.git" "$T/origin.git" "$T/sep"
deny "main checkout with a gitdir file" "$(edit_json "$T/sep/a.txt" b)"

ln -s src "$T/main/alias"
deny "tracked file through a symlinked directory" "$(edit_json "$T/main/alias/b.txt" b)"
assert_contains "symlinked directory: the reason gives the real path" "$GUARD_ERR" "<worktree>/src/b.txt"
deny "new file through a symlinked directory" "$(write_json "$T/main/alias/new.txt" n)"
ln -s "$T/main" "$T/link-to-main"
deny "the main checkout reached through a symlink" "$(edit_json "$T/link-to-main/a.txt" b)"

g clone -q "$T/origin.git" "$T/fsm"
printf '#!/bin/sh\ntouch "%s"\n' "$T/fsm-ran" >"$T/fsm.sh"
chmod +x "$T/fsm.sh"
printf '[core]\n\tfsmonitor = %s\n' "$T/fsm.sh" >"$T/fsm-include"
g -C "$T/fsm" config core.fsmonitor "$T/fsm.sh"
g -C "$T/fsm" config include.path "$T/fsm-include"
deny "planted core.fsmonitor: still judged" "$(edit_json "$T/fsm/a.txt" b)"
assert_file_absent "planted core.fsmonitor never runs" "$T/fsm-ran"
git -C "$T/fsm" check-ignore -q -- a.txt >/dev/null 2>&1
if [[ -e "$T/fsm-ran" ]]; then ok "fixture: plain git check-ignore runs the planted fsmonitor"; else bad "fixture: the planted fsmonitor never fires, so the check above proves nothing"; fi

mkdir -p "$T/stub"
printf '#!/bin/sh\ntouch "%s"\necho "fatal: boom" >&2\nexit 128\n' "$T/git-ran" >"$T/stub/git"
chmod +x "$T/stub/git"
allow "git dir owned by someone else: allowed" "$(edit_json "$T/main/a.txt" b)" \
  -- "PATH=$T/stub:$PATH" "GUARDRAILS_TEST_UNOWNED_PATH=$T/main/.git"
assert_file_absent "git dir owned by someone else: git never runs" "$T/git-ran"
allow "work tree owned by someone else: allowed" "$(edit_json "$T/main/a.txt" b)" \
  -- "PATH=$T/stub:$PATH" "GUARDRAILS_TEST_UNOWNED_PATH=$T/main"
assert_file_absent "work tree owned by someone else: git never runs" "$T/git-ran"
deny "a git error in an owned repository is denied, not exempted" "$(edit_json "$T/main/a.txt" b)" \
  -- "PATH=$T/stub:$PATH"
assert_contains "a git error names itself in the reason" "$GUARD_ERR" "could not judge this path (exit 128: fatal: boom)"

allow "git-ignored file" "$(write_json "$T/main/ignored.txt" i)"
allow "file under an ignored directory" "$(write_json "$T/main/build/out.txt" o)"
mkdir -p "$T/outside"
allow "path outside any repository" "$(write_json "$T/outside/x.txt" x)"
ln -s "$T/outside" "$T/main/out"
allow "a symlinked directory that leaves the repository" "$(write_json "$T/main/out/x.txt" x)"
allow "path inside the .git directory" "$(edit_json "$T/main/.git/config" c)"
allow "relative path" "$(edit_json "a.txt" b)"
allow "a tool that is not a file edit" "$(other_tool_json Read "$T/main/a.txt")"

g init -q "$T/noremote"
printf 'a\n' >"$T/noremote/a.txt"
g -C "$T/noremote" add a.txt
g -C "$T/noremote" commit -q -m init
allow "repository with no remote" "$(edit_json "$T/noremote/a.txt" b)"
assert_silent "no remote: no notice" "$GUARD_ERR"

g clone -q "$T/origin.git" "$T/nohead"
g -C "$T/nohead" remote set-head origin -d
allow "origin without origin/HEAD" "$(edit_json "$T/nohead/a.txt" b)"
assert_contains "origin without origin/HEAD: names the fix" "$GUARD_ERR" "remote set-head origin --auto"

g -C "$T/main" worktree add -q -b feat/x "$T/linked" origin/main
allow "linked worktree" "$(edit_json "$T/linked/a.txt" b)"
g -C "$T/main" worktree add -q --detach "$T/linked-detached" origin/main
allow "detached linked worktree" "$(edit_json "$T/linked-detached/a.txt" b)"

g clone -q "$T/origin.git" "$T/detached"
g -C "$T/detached" checkout -q --detach
allow "detached head in the main checkout" "$(edit_json "$T/detached/a.txt" b)"

g clone -q "$T/origin.git" "$T/branch"
g -C "$T/branch" checkout -q -b feat/y
allow "non-default branch in the main checkout" "$(edit_json "$T/branch/a.txt" b)"

expect_both "kill switch off: allowed" 0 --payload "$(edit_json "$T/main/a.txt" b)" \
  -- CLAUDE_PLUGIN_OPTION_BLOCK_MAIN_CHECKOUT_EDIT_ENABLED=false

row=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Write|Edit|NotebookEdit") | .hooks[].args | map(tostring) | join(" ")' "$HOOK_DIR/hooks.json")
assert_contains "hooks.json runs the guard on the Write|Edit|NotebookEdit row" "$row" " block-main-checkout-edit.sh"
expect_both "an option value other than true: off" 0 --payload "$(edit_json "$T/main/a.txt" b)" \
  -- CLAUDE_PLUGIN_OPTION_BLOCK_MAIN_CHECKOUT_EDIT_ENABLED=yes

report
