#!/usr/bin/env bash

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-exported-msys-pathconv.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

run_win() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc out
  out=$(env OSTYPE=msys "$@" bash "$HOOK" <<<"$(command_json "$command")" 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
  if ((expected == 2)); then
    assert_contains "$label → message" "$out" "MSYS_NO_PATHCONV"
    assert_contains "$label → fix names the prefix form" "$out" "scope it to one command as a prefix"
  fi
}

run_win_pwsh() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc out
  out=$(env OSTYPE=msys "$@" bash "$HOOK" <<<"$(pwsh_command_json "$command")" 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

run_posix_host() {
  local label="$1" command="$2"
  local rc
  env OSTYPE=linux-gnu bash "$HOOK" <<<"$(command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" 0 "$rc"
}

run_posix_host "Linux host: exported suppressor allowed" 'export MSYS_NO_PATHCONV=1; git status'
run_posix_host "Linux host: ordinary command allowed" 'echo hello'

HIDE_JQ="$TEST_TMPDIR/hide-jq.sh"
# shellcheck disable=SC2016  # the shim's own expansions run in the hook's shell
printf '%s\n' \
  'command() { local a; for a in "$@"; do [[ "$a" == jq ]] && return 1; done; builtin command "$@"; }' \
  'jq() { return 127; }' >"$HIDE_JQ"
rc=0
env OSTYPE=linux-gnu BASH_ENV="$HIDE_JQ" bash "$HOOK" <<<"$(command_json 'git status')" \
  >"$TEST_TMPDIR/nojq.out" 2>"$TEST_TMPDIR/nojq.err" || rc=$?
assert_exit "Linux host, jq hidden: allowed (host gate before the jq gate)" 0 "$rc"
assert_silent "Linux host, jq hidden: stays quiet" "$(cat "$TEST_TMPDIR/nojq.out" "$TEST_TMPDIR/nojq.err")"
rc=0
env OSTYPE=msys BASH_ENV="$HIDE_JQ" bash "$HOOK" <<<"$(command_json 'git status')" >/dev/null 2>&1 || rc=$?
assert_exit "control: Windows host, jq hidden: still denied" 2 "$rc"

run_win "export MSYS_NO_PATHCONV=1 (blocked)" 'export MSYS_NO_PATHCONV=1; git status' 2
run_win "export MSYS2_ARG_CONV_EXCL (blocked)" "export MSYS2_ARG_CONV_EXCL='*'; git status" 2
run_win "the real #2870 incident shape (blocked)" \
  'unset GIT_DIR GIT_WORK_TREE; export MSYS_NO_PATHCONV=1; cd /d/worktrees/calib && git worktree add --detach /d/worktrees/ccp-measure2 origin/main' 2
run_win "export chained with && (blocked)" \
  'cd "<repo-root>" && export MSYS_NO_PATHCONV=1 && git show "origin/main:.github/workflows/ci.yml"' 2
run_win "export of both variables at once (blocked)" \
  "export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'; git status" 2
run_win "export with a leading unrelated assignment (blocked)" \
  'export FOO=bar MSYS_NO_PATHCONV=1; git status' 2
run_win "declare -x form (blocked)" 'declare -x MSYS_NO_PATHCONV=1; git status' 2
run_win "typeset -x form (blocked)" 'typeset -x MSYS2_ARG_CONV_EXCL=1; git status' 2
run_win "export at the very start of the command (blocked)" 'export MSYS_NO_PATHCONV=1' 2

run_win "export -- end-of-options form (blocked)" \
  'export -- MSYS_NO_PATHCONV=1; git worktree add /d/worktrees/x' 2
run_win "declare -rx combined flags (blocked)" \
  'declare -rx MSYS_NO_PATHCONV=1; git worktree add /d/worktrees/x' 2
run_win "declare -gx combined flags (blocked)" \
  'declare -gx MSYS_NO_PATHCONV=1; git status' 2
run_win "declare -xg combined flags, x first (blocked)" \
  'declare -xg MSYS_NO_PATHCONV=1; git status' 2
run_win "declare -x -g separate flags (blocked)" \
  'declare -x -g MSYS_NO_PATHCONV=1; git status' 2
run_win "declare -g -x separate flags, x second (blocked)" \
  'declare -g -x MSYS_NO_PATHCONV=1; git status' 2
run_win "typeset -gx combined flags (blocked)" \
  'typeset -gx MSYS2_ARG_CONV_EXCL=1; git status' 2
run_win "declare -r without x stays allowed" \
  'declare -r MSYS_NO_PATHCONV=1; git status' 0
run_win "declare -p inspection stays allowed" \
  'declare -p MSYS_NO_PATHCONV' 0
run_win "export -n un-export stays allowed" \
  'unset MSYS_NO_PATHCONV; git status; export -n MSYS_NO_PATHCONV' 0

run_win "per-command prefix (allowed)" \
  'MSYS_NO_PATHCONV=1 git show "origin/main:.github/workflows/ci.yml"' 0
run_win "per-command prefix, both variables (allowed)" \
  "MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' git show 'origin/main:.claude/settings.json'" 0
run_win "per-command prefix mid-chain (allowed)" \
  'cd "<repo-root>" && MSYS_NO_PATHCONV=1 git show "origin/main:.github/x.yml" | head -5' 0
run_win "bare assignment, not exported (allowed)" 'MSYS_NO_PATHCONV=1; git status' 0
run_win "bare assignment with && (allowed)" 'MSYS2_ARG_CONV_EXCL=1 && git status' 0

run_win "prefix on bash -c (blocked)" \
  "MSYS_NO_PATHCONV=1 bash -c 'git worktree add /d/worktrees/x'" 2
run_win "env prefix on bash -c (blocked)" \
  "env MSYS_NO_PATHCONV=1 bash -c 'git worktree add /d/worktrees/x'" 2
run_win "prefix on sh -c (blocked)" \
  "MSYS2_ARG_CONV_EXCL='*' sh -c 'git worktree add /d/worktrees/x'" 2
run_win "prefix on an absolute bash path (blocked)" \
  "MSYS_NO_PATHCONV=1 /usr/bin/bash -c 'git worktree add /d/worktrees/x'" 2
run_win "prefix on /usr/bin/env bash -c (blocked)" \
  "MSYS_NO_PATHCONV=1 /usr/bin/env bash -c 'git worktree add /d/worktrees/x'" 2
run_win "prefix on command bash -c (blocked)" \
  "MSYS_NO_PATHCONV=1 command bash -c 'git worktree add /d/worktrees/x'" 2
run_win "prefix on env -i bash (blocked, fail-closed on launcher flags)" \
  "MSYS_NO_PATHCONV=1 env -i bash -c 'git worktree add /d/worktrees/x'" 2
run_win "prefix on exec bash (blocked)" \
  "MSYS_NO_PATHCONV=1 exec bash -c 'git worktree add /d/worktrees/x'" 2
run_win "prefix on git itself stays allowed" \
  'MSYS_NO_PATHCONV=1 git show "origin/main:.github/workflows/ci.yml"' 0
run_win "prefix on gh stays allowed" \
  "MSYS_NO_PATHCONV=1 gh pr view 2878 --json body" 0
# The real corpus command that a first draft of this matcher wrongly blocked:
# the `sh` in `show` and the `s` of `settings.json` are not shell command words.
# Kept as a regression pin because it is exactly the shape a substring matcher
# gets wrong, and a false positive here is the failure mode that gets a guard
# switched off.
run_win "prefix on git show with a path containing 'sh' stays allowed" \
  "cd <repo-root> && MSYS_NO_PATHCONV=1 git show 'origin/main:.claude/settings.json'" 0
run_win "prefix on a command whose name merely ends in sh stays allowed" \
  "MSYS_NO_PATHCONV=1 refresh --all" 0
# ...and the matcher must not hang on it. An ERE draft backtracked
# catastrophically on this exact string; the token walk is linear.

run_win "grep for the variable name (allowed)" \
  'grep -rn "MSYS_NO_PATHCONV" docs/' 0
run_win "prose in a commit message (allowed)" \
  'git commit -m "docs: never export MSYS_NO_PATHCONV, use the prefix form"' 0
run_win "gh issue body mentioning it (allowed)" \
  'gh issue create --title "MSYS2_ARG_CONV_EXCL leaks across a command string" --body-file b.md' 0
run_win "unset, not export (allowed)" 'unset MSYS_NO_PATHCONV; git status' 0
run_win "a similarly named variable (allowed)" 'export MSYS_NO_PATHCONV_NOTES=1; git status' 0
run_win "echo of the name (allowed)" 'echo "MSYS_NO_PATHCONV"' 0

run_win "the full assignment quoted in a commit message (allowed)" \
  'git commit -m "fix: block export MSYS_NO_PATHCONV=1"' 0
run_win "echo of the full export command (allowed)" \
  'echo "export MSYS_NO_PATHCONV=1"' 0
run_win "grep for the export spelling (allowed)" \
  "grep -rn 'export MSYS_NO_PATHCONV=1' docs/" 0
run_win "quoted export handed to bash -c (blocked)" \
  "bash -c 'export MSYS_NO_PATHCONV=1; git worktree add /d/worktrees/x'" 2
run_win "quoted export handed to eval (blocked)" \
  'eval "export MSYS_NO_PATHCONV=1"; git status' 2
run_win "quoted bare shell word with an export (blocked)" \
  "'bash' -c 'export MSYS_NO_PATHCONV=1; git status'" 2
run_win "quoted absolute shell path with an export (blocked)" \
  "'/c/Program Files/Git/bin/bash.exe' -c 'export MSYS_NO_PATHCONV=1; git worktree add /d/worktrees/x'" 2
# portability-ok: the backslashes below are Windows path separators inside a
# literal PowerShell test fixture, not regex word-boundary escapes; the string
# never reaches grep or sed.
run_win_pwsh "PowerShell call operator on a quoted bash.exe path with an export (blocked)" \
  '& "C:\Program Files\Git\bin\bash.exe" -c "export MSYS_NO_PATHCONV=1; git status"' 2
run_win "prefix at the start of a quoted child command string (blocked)" \
  "bash -c \"MSYS_NO_PATHCONV=1 bash -c 'git worktree add /d/worktrees/x'\"" 2
# DECLARED RESIDUAL, pinned as deliberate: a heredoc body line is
# indistinguishable from a plain second command line without real shell
# parsing, so an export spelling there still blocks (fail-closed). Use the
# Write tool for documents that must carry the spelling.
run_win "export spelling in a heredoc body still blocks (residual, deliberate)" \
  $'cat > notes.md <<\'EOF\'\nexport MSYS_NO_PATHCONV=1\nEOF' 2
run_win "export on the second line of a multi-line command (blocked)" \
  $'cd /tmp\nexport MSYS_NO_PATHCONV=1\ngit worktree add /d/worktrees/x' 2

run_win "ordinary git worktree add with an MSYS path (allowed)" \
  'git worktree add --detach /d/worktrees/x origin/main' 0
run_win "ordinary command (allowed)" 'ls -la /c/Users' 0


run_win_pwsh "PowerShell wrapping bash -c with an export (blocked)" \
  "bash -c 'export MSYS_NO_PATHCONV=1; git worktree add /d/worktrees/x'" 2
run_win_pwsh "ordinary PowerShell (allowed)" 'Get-ChildItem <repo-root>' 0

run_win "over-length command naming the variable fails closed" \
  "export MSYS_NO_PATHCONV=1; echo $(printf 'x%.0s' {1..17000})" 2

rc=0
env OSTYPE=msys bash "$HOOK" </dev/null >/dev/null 2>&1 || rc=$?
assert_exit "empty stdin is a skip, not a block" 0 "$rc"

rc=0
env OSTYPE=msys bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{}}' >/dev/null 2>&1 || rc=$?
assert_exit "payload with no command is a skip" 0 "$rc"

guard_invoke --hook "$HOOK" --payload '{"tool_name":"Bash","tool_input":"git status"}' -- OSTYPE=msys
assert_exit "a payload whose fields jq cannot read fails closed" 2 "$GUARD_RC"
assert_eq "unreadable fields: the refusal says why" \
  "BLOCKED: the hook payload could not be parsed." "$GUARD_ERR"
assert_eq "unreadable fields: nothing on stdout" "" "$GUARD_OUT"
guard_invoke --hook "$HOOK" --payload "$(jq -n '{tool_name:"Bash",tool_input:{command:"ls\u0000 -la"}}')" -- OSTYPE=msys
assert_exit "a NUL byte in a harmless command fails closed" 2 "$GUARD_RC"
assert_eq "NUL byte: the refusal says why" \
  "BLOCKED: the payload carries a NUL byte. Reissue the call without it." "$GUARD_ERR"
assert_eq "NUL byte: nothing on stdout" "" "$GUARD_OUT"

rc=0
env OSTYPE=msys CLAUDE_PLUGIN_OPTION_BLOCK_EXPORTED_MSYS_PATHCONV_ENABLED=false \
  bash "$HOOK" <<<"$(command_json 'export MSYS_NO_PATHCONV=1; git status')" >/dev/null 2>&1 || rc=$?
assert_exit "kill switch disables the guard" 0 "$rc"

report
