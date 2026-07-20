#!/usr/bin/env bash
# Contract test for block-noncanonical-commit.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash JSON on
# stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained — no
# host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-noncanonical-commit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# run <label> <command> <expected-exit> [extra-env NAME=VAL ...]
run() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc
  env "$@" bash "$HOOK" <<<"$(command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# --- the anti-pattern this guard exists for -----------------------------------
run "git commit -m (blocked)" "git commit -m 'feat: x'" 2
run "git commit -am (bundled, blocked)" "git commit -am 'feat: x'" 2
run "git commit -m with --trailer (still blocked — trailer is not the mechanic)" \
  "git commit -m 'feat: x' --trailer 'Co-Authored-By: X <x@y.z>'" 2
run "bare git commit (opens EDITOR, blocked)" "git commit" 2
run "git commit -a (no message source, blocked)" "git commit -a" 2

# --- the canonical form -------------------------------------------------------
run "git commit -F - (allowed)" "git commit -F - --cleanup=verbatim" 0
run "git commit --file - (allowed)" "git commit --file - " 0
run "git commit --file=- (allowed)" "git commit --file=-" 0
run "git commit -F- (attached, allowed)" "git commit -F-" 0

# The trailer_policy `none` case: /commit's own output when the repo convention
# forbids a co-author trailer. Requiring --trailer here would deadlock the skill.
run "git commit -F - without --trailer (allowed — trailer_policy none)" \
  "git commit -F - --cleanup=verbatim" 0

# --- exempt operations (no message-on-stdin form exists) ----------------------
run "git commit --amend --no-edit (allowed)" "git commit --amend --no-edit" 0
run "git commit --amend (allowed)" "git commit --amend" 0
run "git commit -C HEAD (allowed)" "git commit -C HEAD" 0
run "git commit --reuse-message=HEAD (allowed)" "git commit --reuse-message=HEAD" 0
run "git commit --fixup HEAD (allowed)" "git commit --fixup HEAD" 0
run "git commit --squash=HEAD (allowed)" "git commit --squash=HEAD" 0
run "git commit -F msg.txt (path, allowed)" "git commit -F msg.txt" 0
run "git commit --file=msg.txt (path, allowed)" "git commit --file=msg.txt" 0

# --- top-level git options must not be confused with commit options ----------
# `-c` BEFORE the subcommand is config; only after `commit` is it --reedit.
run "git -c user.name=x commit -m (config, still blocked)" \
  "git -c user.name=x commit -m 'feat: x'" 2
run "git -c user.name=x commit -F - (config, allowed)" \
  "git -c user.name=x commit -F -" 0

# --- inline git aliases are expanded before the subcommand verdict -----------
# `git -c alias.c=commit c -m x` commits. Without expansion the subcommand reads
# as `c`, not `commit`, and the guard waves the whole thing through.
run "inline git alias to commit -m (blocked)" \
  "git -c alias.c=commit c -m bypass" 2
run "inline git alias carrying -m in the expansion (blocked)" \
  "git -c alias.ci='commit -m x' ci" 2
run "inline shell alias (leading !) to commit -m (blocked)" \
  "git -c alias.sh='!git commit -m x' sh" 2
run "inline git alias to a canonical commit (allowed)" \
  "git -c alias.c=commit c -F -" 0
run "inline alias to an unrelated subcommand (allowed)" \
  "git -c alias.st=status st" 0

# --- other subcommands are untouched -----------------------------------------
run "git log (allowed)" "git log --oneline -5" 0
run "git push (allowed)" "git push origin main" 0
run "non-git command (allowed)" "echo git commit -m nope" 0

# --- prose containing the anti-pattern is not a false positive ---------------
run "quoted mention in a heredoc body (allowed)" \
  "git commit -F - <<'EOF'
docs: explain why git commit -m 'x' is wrong
EOF" 0

# --- shell -c wrappers are re-parsed -----------------------------------------
run "bash -lc wrapped -m (blocked)" "bash -lc \"git commit -m 'feat: x'\"" 2
run "bash -lc wrapped -F - (allowed)" "bash -lc 'git commit -F -'" 0

# --- control operators: a later segment is still checked ---------------------
run "second segment carries -m (blocked)" "git add -A && git commit -m 'x'" 2

# --- kill switch and allow-list ----------------------------------------------
run "kill switch disables the guard" "git commit -m 'feat: x'" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ENABLED=false
run "allow-list message-flag permits -m" "git commit -m 'feat: x'" 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW=message-flag
run "unrelated allow token does not permit -m" "git commit -m 'feat: x'" 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW=something-else

# --- in-progress sequencer is exempt -----------------------------------------
# A real repo mid-merge: `git commit` concludes the merge with the message git
# prepared, and gating it would strand the conflict resolution.
SEQ="$TEST_TMPDIR/seq"
mkdir -p "$SEQ"
(
  cd "$SEQ" || exit 1
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  git init -q .
  git config user.email t@e.st
  git config user.name t
  : >a
  git add a
  git commit -qm base --no-verify 2>/dev/null
) >/dev/null 2>&1

GITDIR="$SEQ/.git"
if [[ -d "$GITDIR" ]]; then
  : >"$GITDIR/MERGE_HEAD"
  rc=0
  MSYS_NO_PATHCONV=1 jq -n --arg c "git commit -m 'merge fix'" --arg d "$SEQ" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    bash "$HOOK" >/dev/null 2>&1
  rc=$?
  assert_exit "in-progress merge is exempt" 0 "$rc"

  rm -f "$GITDIR/MERGE_HEAD"
  MSYS_NO_PATHCONV=1 jq -n --arg c "git commit -m 'not a merge'" --arg d "$SEQ" \
    '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' |
    bash "$HOOK" >/dev/null 2>&1
  rc=$?
  assert_exit "same repo with no sequencer state is blocked" 2 "$rc"
else
  echo "ok: sequencer fixture skipped (git init unavailable)"
  PASS=$((PASS + 1))
fi

# --- the block message names the fix -----------------------------------------
out=$(bash "$HOOK" <<<"$(command_json "git commit -m 'feat: x'")" 2>&1)
assert_contains "block message names -F -" "$out" '-F -'
assert_contains "block message names the skill" "$out" '/commit'

echo
echo "passed: $PASS   failed: $FAIL"
((FAIL == 0))
