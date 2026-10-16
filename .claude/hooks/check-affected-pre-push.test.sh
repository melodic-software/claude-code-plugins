#!/usr/bin/env bash
# Contract test for .claude/hooks/check-affected-pre-push.sh.
#
#   bash .claude/hooks/check-affected-pre-push.test.sh
#
# MUST-fire: a real `git push` that sends a branch runs scripts/check-affected.sh
# and blocks (exit 2, its summary on stderr) when it exits 1.
# MUST-stay-quiet: the `if: "Bash(git push *)"` filter also fires on any command
# holding $(), backticks or $VAR, so a commit whose message mentions "git push"
# reaches this hook; it must not spend a check run on it. Delete-only, tag-only
# and dry-run pushes, a repository with no check-affected.sh, and a tree with no
# origin/main stay quiet too. A branch that changes check tooling runs the
# merge-base copy of it, never its own. Once lefthook's pre-push shim is
# installed the hook stays quiet; the --git-hook mode lefthook.yml runs, and a
# real push through lefthook when it is on PATH, never run a branch's own check.
#
# The fixture repository's scripts/check-affected.sh is a stub that records that
# it ran and exits with $STUB_RC, so these cases test the hook, not the checks.
# The cases hold shell source as literal data on purpose.
# shellcheck disable=SC2016
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
repo_root="$(cd "$here/../.." && pwd)" || exit 2
hook="$here/check-affected-pre-push.sh"

# shellcheck source=../../scripts/lib/test-harness.sh
. "$repo_root/scripts/lib/test-harness.sh" || exit 2
# shellcheck source=../../scripts/test-git-helpers.sh
. "$repo_root/scripts/test-git-helpers.sh" || exit 2

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/repo"
bare="$tmp/no-script"
mkdir -p "$fixture/scripts" "$bare"
git_init_test_repo "$fixture" || exit 2
git_init_test_repo "$bare" || exit 2
marker="$tmp/ran"
cat >"$fixture/scripts/check-affected.sh" <<EOF
#!/usr/bin/env bash
touch "$marker"
echo "check-affected: FAIL markdown (stub)" >&2
exit "\${STUB_RC:-1}"
EOF
chmod +x "$fixture/scripts/check-affected.sh"
cp "$fixture/scripts/check-affected.sh" "$tmp/stub"
# origin/main holds the stub, so a branch that leaves the tooling alone runs it.
git_test_config "$fixture" add -A
git_test_config "$fixture" commit -q -m stub
git_test_config "$fixture" update-ref refs/remotes/origin/main HEAD
other="$tmp/other"
mkdir -p "$other/scripts"
git_init_test_repo "$other" || exit 2
cp "$fixture/scripts/check-affected.sh" "$other/scripts/"

# run_hook <cwd> <command> [STUB_RC]: sets RC, ERR and RAN (1 when the stub ran).
run_hook() {
  local payload
  rm -f "$marker"
  payload="$(jq -cn --arg c "$2" --arg d "$1" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}')"
  RC=0
  ERR="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$fixture" STUB_RC="${3:-1}" bash "$hook" 2>&1 >/dev/null)" || RC=$?
  RAN=0
  [[ -e "$marker" ]] && RAN=1
}

expect() {
  local name="$1" rc="$2" ran="$3"
  if [[ "$RC" == "$rc" && "$RAN" == "$ran" ]]; then
    ok "$name"
  else
    bad "$name" "expected exit $rc ran=$ran, got exit $RC ran=$RAN; stderr: $ERR"
  fi
}

# --- MUST fire ---------------------------------------------------------------
run_hook "$fixture" 'git push -u origin feat/x'
expect "blocks a branch push when a check fails" 2 1
if [[ "$ERR" == *"Push blocked"* && "$ERR" == *"FAIL markdown"* ]]; then
  ok "the block carries the check summary"
else
  bad "the block carries the check summary" "$ERR"
fi

run_hook "$fixture" 'git push'
expect "blocks a bare push" 2 1
run_hook "$fixture" 'npm test && git push origin HEAD'
expect "blocks a push after another subcommand" 2 1
run_hook "$tmp" "git -C '$fixture' push origin feat/x"
expect "runs in the -C repository" 2 1
run_hook "$fixture" 'FOO=1 git push --force-with-lease origin feat/x'
expect "blocks a push behind an assignment" 2 1
run_hook "$fixture" 'git push origin feat/x' 0
expect "passes when every check passes" 0 1
run_hook "$fixture" 'git push origin feat/x' 2
expect "passes when the checks could not run" 0 1

# --- MUST stay quiet ---------------------------------------------------------
run_hook "$fixture" "$(printf '%s\n' 'git commit -m "$(cat <<'"'"'EOF'"'"'' 'fix: x' '' 'Then git push origin main.' 'EOF' ')"')"
expect "a commit message mentioning git push is not a push" 0 0
run_hook "$fixture" "$(printf '%s\n' 'cat >notes.txt <<EOF' 'git push origin main' 'EOF')"
expect "a heredoc body is data" 0 0
run_hook "$fixture" 'echo "remember to git push"'
expect "a quoted mention is data" 0 0
run_hook "$fixture" 'git log --oneline $(git rev-parse HEAD) | grep push'
expect "a non-push git command with \$() stays quiet" 0 0
run_hook "$fixture" 'git push origin --delete feat/x'
expect "a delete-only push stays quiet" 0 0
run_hook "$fixture" 'git push origin :feat/x'
expect "a delete refspec stays quiet" 0 0
run_hook "$fixture" 'git push --tags'
expect "a tags-only push stays quiet" 0 0
run_hook "$fixture" 'git push origin tag v1.2.3'
expect "a tag refspec stays quiet" 0 0
run_hook "$fixture" 'git push --dry-run origin feat/x'
expect "a dry run stays quiet" 0 0
run_hook "$bare" 'git push origin feat/x'
expect "a repository without check-affected.sh stays quiet" 0 0
run_hook "$fixture" 'git push -nf origin feat/x'
expect "a dry run in a short-flag cluster stays quiet" 0 0
run_hook "$fixture" "cd '$other' && git push origin feat/x"
expect "a push after cd stays quiet" 0 0
run_hook "$tmp" "git -C '$other' push origin feat/x"
expect "another repository's check-affected.sh never runs" 0 0
run_hook "$other" 'git push origin feat/x'
expect "a session cwd in another repository stays quiet" 0 0
git_test_config "$fixture" worktree add -q -b wt "$tmp/wt"
run_hook "$tmp/wt" 'git push origin wt'
expect "another worktree of the project's clone stays quiet" 0 0

# A branch checked out in the project tree that changes check tooling gets the
# merge-base copy run, never its own; one that leaves the tooling alone runs in
# place.
git_test_config "$fixture" checkout -q -b docs-only
mkdir -p "$fixture/docs"
echo x >"$fixture/docs/a.md"
git_test_config "$fixture" add docs/a.md
git_test_config "$fixture" commit -q -m docs
run_hook "$fixture" 'git push origin docs-only'
expect "a branch that leaves the tooling alone still runs" 2 1

git_test_config "$fixture" checkout -q -b edits-check origin/main
{
  head -n 1 "$tmp/stub"
  printf 'touch "%s"\n' "$tmp/payload"
  tail -n +2 "$tmp/stub"
} >"$fixture/scripts/check-affected.sh"
git_test_config "$fixture" commit -q -am payload
run_hook "$fixture" 'git push origin edits-check'
expect "a branch that edits scripts/check-affected.sh runs the merge-base copy" 2 1
if [[ ! -e "$tmp/payload" ]]; then
  ok "the branch's own check-affected.sh does not run"
else
  bad "the branch's own check-affected.sh does not run" "$ERR"
fi
run_hook "$fixture" 'git push origin edits-check' 0
if [[ "$RC" == 0 && "$ERR" == *"changes check tooling (scripts/check-affected.sh)"*"merge-base copy"* ]]; then
  ok "the notice names the changed tooling path"
else
  bad "the notice names the changed tooling path" "exit $RC; stderr: $ERR"
fi

# A committed tooling edit the working tree reverts is still the branch's code:
# the HEAD checkout the dirty run uses would carry it.
git_test_config "$fixture" show refs/remotes/origin/main:scripts/check-affected.sh >"$fixture/scripts/check-affected.sh"
run_hook "$fixture" 'git push origin edits-check'
expect "a committed tooling edit the working tree reverts runs the merge-base copy" 2 1
if [[ ! -e "$tmp/payload" ]]; then
  ok "the reverted branch script does not run from the HEAD checkout"
else
  bad "the reverted branch script does not run from the HEAD checkout" "$ERR"
fi
git_test_config "$fixture" checkout -q -- scripts/check-affected.sh

git_test_config "$fixture" checkout -q -b nested-md origin/main
mkdir -p "$fixture/docs"
echo 'module.exports = {};' >"$fixture/docs/.markdownlint-cli2.cjs"
echo x >"$fixture/docs/b.md"
git_test_config "$fixture" add docs
git_test_config "$fixture" commit -q -m nested
run_hook "$fixture" 'git push origin nested-md' 0
if [[ "$RC" == 0 && "$ERR" == *"changes check tooling (docs/.markdownlint-cli2.cjs)"* ]]; then
  ok "a nested markdownlint config is check tooling"
else
  bad "a nested markdownlint config is check tooling" "exit $RC; stderr: $ERR"
fi

git_test_config "$fixture" checkout -q docs-only
mkdir -p "$fixture/scripts/lib"
echo 'touch /dev/null' >"$fixture/scripts/lib/helper.sh"
run_hook "$fixture" 'git push origin docs-only'
expect "an untracked script moves the run to the merge-base copy" 2 1
rm -rf "$fixture/scripts/lib"

git_test_config "$fixture" update-ref -d refs/remotes/origin/main
run_hook "$fixture" 'git push origin docs-only'
expect "no origin/main to compare against is not run" 0 0

# The real check-affected.sh at the merge-base lints a branch that edits check
# tooling, and lints the committed version of a file with uncommitted edits.
if command -v shellcheck >/dev/null 2>&1; then
  real="$tmp/real"
  mkdir -p "$real/scripts" "$real/tools"
  git_init_test_repo "$real" || exit 2
  cp "$repo_root/scripts/check-affected.sh" "$real/scripts/"
  cp "$repo_root/.shellcheckrc" "$real/"
  git_test_config "$real" add -A
  git_test_config "$real" commit -q -m tooling
  git_test_config "$real" update-ref refs/remotes/origin/main HEAD
  run_real() {
    local payload
    payload="$(jq -cn --arg d "$real" \
      '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:"git push origin x"}}')"
    RC=0
    ERR="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$real" bash "$hook" 2>&1 >/dev/null)" || RC=$?
  }
  bad_sh=$'#!/usr/bin/env bash\nif true; then\n  echo hi\n'
  good_sh=$'#!/usr/bin/env bash\necho hi\n'

  git_test_config "$real" checkout -q -b edits-scripts
  printf '%s' "$bad_sh" >"$real/scripts/foo.sh"
  chmod +x "$real/scripts/foo.sh"
  {
    head -n 1 "$repo_root/scripts/check-affected.sh"
    printf "touch '%s'\n" "$tmp/real-payload"
    tail -n +2 "$repo_root/scripts/check-affected.sh"
  } >"$real/scripts/check-affected.sh"
  git_test_config "$real" add -A
  git_test_config "$real" commit -q -m scripts
  run_real
  if [[ "$RC" == 2 && "$ERR" == *"FAIL shellcheck"* && "$ERR" == *"scripts/foo.sh"* ]]; then
    ok "a shellcheck error in a changed scripts/ file blocks the push"
  else
    bad "a shellcheck error in a changed scripts/ file blocks the push" "exit $RC; stderr: $ERR"
  fi
  if [[ ! -e "$tmp/real-payload" ]]; then
    ok "the branch's modified check-affected.sh does not execute"
  else
    bad "the branch's modified check-affected.sh does not execute" "payload created"
  fi

  git_test_config "$real" checkout -q -b dirty origin/main
  printf '%s' "$bad_sh" >"$real/tools/bad.sh"
  chmod +x "$real/tools/bad.sh"
  git_test_config "$real" add -A
  git_test_config "$real" commit -q -m bad
  printf '%s' "$good_sh" >"$real/tools/bad.sh"
  run_real
  if [[ "$RC" == 2 && "$ERR" == *"FAIL shellcheck"* && "$ERR" == *"tools/bad.sh"* ]]; then
    ok "a file with uncommitted edits is linted as committed"
  else
    bad "a file with uncommitted edits is linted as committed" "exit $RC; stderr: $ERR"
  fi
  if [[ "$(git_test_config "$real" worktree list | wc -l)" -eq 1 && "$(cat "$real/tools/bad.sh")" == "${good_sh%$'\n'}" ]]; then
    ok "the HEAD checkout is removed and the working tree is untouched"
  else
    bad "the HEAD checkout is removed and the working tree is untouched" "$(git_test_config "$real" worktree list)"
  fi
else
  ok "SKIP real check-affected cases (shellcheck not installed)"
fi

# The .claude/settings.json command runs the hook only when the hook script and
# lib/hook-utils.sh match the merge-base with origin/main.
gated="$tmp/gated"
mkdir -p "$gated/.claude/hooks" "$gated/lib" "$gated/scripts"
git_init_test_repo "$gated" || exit 2
cp "$hook" "$gated/.claude/hooks/"
cp "$repo_root/lib/hook-utils.sh" "$gated/lib/"
cp "$fixture/scripts/check-affected.sh" "$gated/scripts/"
git_test_config "$gated" add -A
git_test_config "$gated" commit -q -m gated
git_test_config "$gated" update-ref refs/remotes/origin/main HEAD
gate_cmd="$(jq -r '.hooks.PreToolUse[] | .hooks[] | select(.if == "Bash(git push *)") | .command' \
  "$repo_root/.claude/settings.json")"
run_gate() {
  local payload
  rm -f "$marker"
  payload="$(jq -cn --arg d "$gated" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:"git push origin feat/x"}}')"
  RC=0
  ERR="$(printf '%s' "$payload" | (cd "$gated" && CLAUDE_PROJECT_DIR="$gated" bash -c "$gate_cmd") 2>&1 >/dev/null)" || RC=$?
  RAN=0
  [[ -e "$marker" ]] && RAN=1
}
run_gate
expect "the settings.json command runs an unchanged hook" 2 1
git_test_config "$gated" checkout -q -b edits-hook
printf 'touch "%s"\n' "$tmp/hook-payload" >>"$gated/.claude/hooks/check-affected-pre-push.sh"
git_test_config "$gated" commit -q -am payload
run_gate
if [[ "$RC" == 0 && "$RAN" == 0 && ! -e "$tmp/hook-payload" ]]; then
  ok "the settings.json command does not run a hook the branch changed"
else
  bad "the settings.json command does not run a hook the branch changed" "exit $RC ran=$RAN; stderr: $ERR"
fi

# --- lefthook ----------------------------------------------------------------
# Once lefthook's pre-push shim is installed, git runs the check on the push
# itself, so the Claude Code hook stays quiet; until then it runs and says to
# install. lefthook.yml runs the merge-base copy of this hook with --git-hook.
lh="$tmp/lh"
mkdir -p "$lh/scripts" "$lh/.claude/hooks" "$lh/lib"
git_init_test_repo "$lh" || exit 2
cp "$tmp/stub" "$lh/scripts/check-affected.sh"
cp "$hook" "$lh/.claude/hooks/"
cp "$repo_root/lib/hook-utils.sh" "$lh/lib/"
cp "$repo_root/lefthook.yml" "$lh/"
git_test_config "$lh" add -A
git_test_config "$lh" commit -q -m base
git_test_config "$lh" update-ref refs/remotes/origin/main HEAD
lh_hooks="$(git -C "$lh" rev-parse --path-format=absolute --git-path hooks)"
shim=$'#!/bin/sh\ncall_lefthook()\n{\n  lefthook "$@"\n}\ncall_lefthook run "pre-push" "$@"\n'

# run_claude <repo> [STUB_RC]: the Claude Code hook on a push from <repo>, the
# session's project directory.
run_claude() {
  local payload
  rm -f "$marker"
  payload="$(jq -cn --arg d "$1" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:"git push origin x"}}')"
  RC=0
  ERR="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$1" STUB_RC="${2:-1}" bash "$hook" 2>&1 >/dev/null)" || RC=$?
  RAN=0
  [[ -e "$marker" ]] && RAN=1
}
# run_git_hook <repo> [STUB_RC]: the --git-hook mode lefthook.yml runs.
run_git_hook() {
  rm -f "$marker"
  RC=0
  ERR="$(cd "$1" && STUB_RC="${2:-1}" bash "$hook" --git-hook </dev/null 2>&1 >/dev/null)" || RC=$?
  RAN=0
  [[ -e "$marker" ]] && RAN=1
}

run_claude "$lh"
expect "without lefthook's shim the Claude Code hook runs the check" 2 1
if [[ "$ERR" == *"run lefthook install"* ]]; then
  ok "without lefthook's shim the hook says to run lefthook install"
else
  bad "without lefthook's shim the hook says to run lefthook install" "$ERR"
fi
printf '#!/bin/sh\ngit lfs pre-push "$@"\n' >"$lh_hooks/pre-push"
run_claude "$lh"
expect "another tool's pre-push hook is not lefthook's" 2 1
printf '%s' "$shim" >"$lh_hooks/pre-push"
run_claude "$lh"
expect "with lefthook's shim installed the Claude Code hook stays quiet" 0 0
rm -f "$lh_hooks/pre-push"
mkdir -p "$tmp/hookspath"
printf '%s' "$shim" >"$tmp/hookspath/pre-push"
git_test_config "$lh" config core.hooksPath "$tmp/hookspath"
run_claude "$lh"
expect "a lefthook shim under core.hooksPath counts" 0 0
git_test_config "$lh" config --unset core.hooksPath

run_git_hook "$lh"
expect "--git-hook blocks with exit 1 when a check fails" 1 1
if [[ "$ERR" == *"Push blocked"* && "$ERR" != *"lefthook install"* ]]; then
  ok "--git-hook carries the summary and no install notice"
else
  bad "--git-hook carries the summary and no install notice" "$ERR"
fi
run_git_hook "$lh" 0
expect "--git-hook passes when every check passes" 0 1
run_git_hook "$lh" 2
expect "--git-hook passes when the checks could not run" 0 1

# A branch whose check-affected.sh and hook always pass does not get past the
# merge-base copies.
git_test_config "$lh" checkout -q -b bypass
printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "$tmp/bypass-ran" >"$lh/scripts/check-affected.sh"
printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "$tmp/bypass-ran" >"$lh/.claude/hooks/check-affected-pre-push.sh"
git_test_config "$lh" commit -q -am bypass
run_git_hook "$lh"
if [[ "$RC" == 1 && ! -e "$tmp/bypass-ran" ]]; then
  ok "--git-hook runs the merge-base check-affected.sh, not the branch's"
else
  bad "--git-hook runs the merge-base check-affected.sh, not the branch's" "exit $RC; stderr: $ERR"
fi

if command -v lefthook >/dev/null 2>&1; then
  git init -q --bare "$tmp/remote.git"
  git_test_config "$lh" remote add origin "$tmp/remote.git"
  lh_install="$(cd "$lh" && lefthook install 2>&1)" || bad "lefthook install in the fixture" "$lh_install"
  # lefthook_push <branch> [STUB_RC]: a real git push through lefthook.
  lefthook_push() {
    rm -f "$marker" "$tmp/bypass-ran"
    RC=0
    ERR="$(cd "$lh" && STUB_RC="${2:-1}" git_test_config "$lh" push -q origin "$1" 2>&1)" || RC=$?
    RAN=0
    [[ -e "$marker" ]] && RAN=1
  }
  lefthook_push bypass
  if [[ "$RC" != 0 && "$RAN" == 1 && ! -e "$tmp/bypass-ran" && "$ERR" == *"Push blocked"* ]]; then
    ok "lefthook blocks a branch that edits check-affected.sh and the hook to always pass"
  else
    bad "lefthook blocks a branch that edits check-affected.sh and the hook to always pass" "exit $RC ran=$RAN; output: $ERR"
  fi
  lefthook_push bypass 0
  if [[ "$RC" == 0 && "$RAN" == 1 && ! -e "$tmp/bypass-ran" ]]; then
    ok "lefthook lets the push through when the merge-base checks pass"
  else
    bad "lefthook lets the push through when the merge-base checks pass" "exit $RC ran=$RAN; output: $ERR"
  fi
  run_claude "$lh"
  expect "after lefthook install the Claude Code hook stays quiet" 0 0
else
  ok "SKIP lefthook end-to-end cases (lefthook not installed)"
fi

test_harness::report
