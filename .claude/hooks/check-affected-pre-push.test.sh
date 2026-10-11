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
# and dry-run pushes, and a repository with no check-affected.sh, stay quiet too.
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
git_test_config "$fixture" add -A
git_test_config "$fixture" commit -q -m stub
git_test_config "$fixture" worktree add -q -b wt "$tmp/wt"
run_hook "$tmp/wt" 'git push origin wt'
expect "another worktree of the project's clone stays quiet" 0 0

test_harness::report
