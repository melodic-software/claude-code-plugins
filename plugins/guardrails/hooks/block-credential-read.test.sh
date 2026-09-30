#!/usr/bin/env bash
# Contract test for block-credential-read.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse Bash/PowerShell
# JSON on stdin, asserts on exit code (2 = blocked, 0 = allowed). Self-contained,
# no host-repo assertion library.

# shellcheck disable=SC2016  # command strings are literal test input, never expanded here
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-credential-read.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# run <label> <command> <expected> [ENV=value ...]: the Bash tool.
run() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc out
  out=$(env "$@" bash "$HOOK" <<<"$(command_json "$command")" 2>&1)
  rc=$?
  assert_exit "$label" "$expected" "$rc"
  if ((expected == 2)); then
    assert_contains "$label -> says what was blocked" "$out" "prints a credential"
    assert_contains "$label -> names the presence check" "$out" "check that the credential is present"
    assert_contains "$label -> names the escape" "$out" "block_credential_read_allow"
  fi
}

# run_ps <label> <command> <expected> [ENV=value ...]: the PowerShell tool.
run_ps() {
  local label="$1" command="$2" expected="$3"
  shift 3
  local rc
  env "$@" bash "$HOOK" <<<"$(pwsh_command_json "$command")" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# --- 1. git credential fill / helper get (blocked) ---------------------------
run "git credential fill" 'git credential fill' 2
run "git credential fill fed by printf" "printf 'host=github.com\n\n' | git credential fill" 2
run "git credential-manager get" 'git credential-manager get' 2
run "git credential-store get" 'git credential-store get' 2
run "git-credential-manager get, direct binary" 'git-credential-manager get' 2
run "git -C credential fill" 'git -C /tmp/repo credential fill' 2
run "credential fill after &&" 'cd /tmp && git credential fill' 2
run_ps "PowerShell: git credential fill" 'git credential fill' 2
run_ps "PowerShell: git.exe credential-manager get" 'git.exe credential-manager get' 2

# --- 2. gh auth token (blocked) ----------------------------------------------
run "gh auth token" 'gh auth token' 2
run "gh auth token with a host flag" 'gh auth token --hostname github.com' 2
run "gh auth token after a semicolon" 'echo hi; gh auth token' 2
run "gh auth token in a command substitution" 'curl -H "Authorization: Bearer $(gh auth token)" https://api.github.com' 2
run "gh auth token by absolute path" '/usr/bin/gh auth token' 2
run "gh auth token in a backtick substitution" 'TOKEN=`gh auth token`' 2
run "git credential fill in a backtick substitution" 'x=`git credential fill`' 2
run "printenv in a backtick substitution" 'x=`printenv GH_TOKEN`' 2
run "cat .netrc in a backtick substitution" 'x=`cat ~/.netrc`' 2

# --- 2b. leading NAME=value assignments do not hide the command (blocked) -----
run "assignment before gh auth token" 'TERM=xterm gh auth token' 2
run "assignment before git credential fill" 'X=1 git credential fill' 2
run "assignment before cat .netrc" 'FOO=1 cat ~/.netrc' 2
run "assignment before echo of a token" 'Y=1 echo $GH_TOKEN' 2
run "two assignments, one quoted, before printenv" 'A=1 B="x y" printenv GH_TOKEN' 2
run "assignment after a semicolon" 'echo hi; X=1 gh auth token' 2
run "assignment before an unrelated command" 'X=1 git status' 0
run_ps "PowerShell: gh auth token" 'gh auth token' 2
run_ps "PowerShell: gh.exe auth token piped" 'gh.exe auth token | Set-Clipboard' 2

# --- 3. printenv of a token variable (blocked) --------------------------------
run "printenv GH_TOKEN" 'printenv GH_TOKEN' 2
run "printenv GITHUB_TOKEN among others" 'printenv PATH GITHUB_TOKEN' 2
run "printenv of an api key" 'printenv ANTHROPIC_API_KEY' 2
run "printenv of a password" 'printenv DB_PASSWORD' 2
run "printenv, lower case name" 'printenv gh_token' 2
run_ps "PowerShell: printenv GH_TOKEN" 'printenv GH_TOKEN' 2

# --- 4. echo of a token variable (blocked) ------------------------------------
run "echo \$GITHUB_TOKEN" 'echo $GITHUB_TOKEN' 2
run "echo braced api key, quoted" 'echo "${ANTHROPIC_API_KEY}"' 2
run "echo in a string" 'echo "token is $GH_TOKEN"' 2
run "printf of a secret" 'printf "%s" "$CLIENT_SECRET"' 2
run "echo after a pipe-less chain" 'true && echo $NPM_TOKEN' 2
run "echo of a default expansion" 'echo ${GH_TOKEN:-}' 2
run "echo of an access key" 'echo $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY' 2
run_ps 'PowerShell: $env:GH_TOKEN as a statement' '$env:GH_TOKEN' 2
run_ps 'PowerShell: bare braced $env: variable' '${env:GITHUB_TOKEN}' 2
run_ps 'PowerShell: Write-Output $env:X_TOKEN' 'Write-Output $env:X_TOKEN' 2
run_ps 'PowerShell: Write-Host with a string' 'Write-Host "token: $env:GH_TOKEN"' 2
run_ps 'PowerShell: Get-ChildItem env:GH_TOKEN' 'Get-ChildItem env:GH_TOKEN' 2
run_ps 'PowerShell: gci Env:\ form' 'gci Env:\GITHUB_TOKEN' 2
run_ps 'PowerShell: Get-Item env: with a wildcard' 'Get-Item env:*TOKEN*' 2
run_ps 'PowerShell: lower-case variable name' 'Write-Output $env:gh_token' 2

# --- 5. Reading a credential file (blocked) -----------------------------------
run "cat .git-credentials" 'cat ~/.git-credentials' 2
run "cat .netrc" 'cat ~/.netrc' 2
run "cat _netrc" 'cat ~/_netrc' 2
run "cat .env" 'cat .env' 2
run "cat .env.local" 'cat .env.local' 2
run "cat .env.production" 'cat apps/web/.env.production' 2
run "cat with a flag" 'cat -n .env' 2
run "cat quoted path" 'cat "$HOME/.netrc"' 2
run "cat several files" 'cat README.md .env' 2
run "cat .env then a template" 'cat .env .env.example' 2
run "cat by redirect" 'cat < .env' 2
run "cat piped on" 'cat .env | grep KEY' 2
run_ps "PowerShell: Get-Content .env" 'Get-Content .env' 2
run_ps "PowerShell: gc -Raw of .netrc" 'gc -Raw $HOME\.netrc' 2
run_ps "PowerShell: type .git-credentials" 'type $HOME\.git-credentials' 2
run_ps "PowerShell: Get-Content -Path .env.local" 'Get-Content -Path .env.local' 2
run_ps "PowerShell: cat .env" 'cat .env' 2

# --- 6. A shell word makes quoted text live -----------------------------------
run "bash -c gh auth token" "bash -c 'gh auth token'" 2
run "sh -c cat .netrc" 'sh -c "cat ~/.netrc"' 2
run_ps "PowerShell: pwsh -Command reading .env" 'pwsh -Command "Get-Content .env"' 2
run_ps "PowerShell: bash -c inside" "bash -c 'printenv GH_TOKEN'" 2

# --- 7. Presence checks and unrelated commands (allowed) ----------------------
run "gh auth status" 'gh auth status' 0
run "test -n on a token variable" 'test -n "$GH_TOKEN" && echo set' 0
run "[ -n ] on a token variable" '[ -n "$GH_TOKEN" ] && echo present' 0
run "[[ -z ]] on a token variable" '[[ -z "${GITHUB_TOKEN:-}" ]] && echo unset' 0
run "[ -f ~/.netrc ]" '[ -f ~/.netrc ] && echo present' 0
run "test -f .env" 'test -f .env && echo present' 0
run "printenv PATH" 'printenv PATH' 0
run "printenv HOME" 'printenv HOME' 0
run "echo \$HOME" 'echo $HOME' 0
run "echo a plain word" 'echo token' 0
run "echo presence expansion" 'echo "${GH_TOKEN:+set}"' 0
run "echo length of a token variable" 'echo ${#GH_TOKEN}' 0
run "echo presence next to a plain variable" 'echo "${GH_TOKEN:+set} $HOME"' 0
run "git credential approve (stores, prints nothing)" 'git credential approve' 0
run "git config credential.helper" 'git config credential.helper' 0
run "git status" 'git status' 0
run "ls of an env file" 'ls -la .env' 0
run "cat of a template" 'cat .env.example' 0
run "cat of a sample" 'cat .env.sample' 0
run "cat of a template file" 'cat config/.env.template' 0
run "cat of .envrc" 'cat .envrc' 0
run "cat of a file that merely ends in .env" 'cat prod.env' 0
run "cat of a doc about .env" 'cat docs/.env-guide.md' 0
run "cat an ordinary file" 'cat README.md' 0
run_ps "PowerShell: Test-Path on a credential file" 'Test-Path $HOME\.netrc' 0
run_ps 'PowerShell: presence of $env:GH_TOKEN' 'if ($env:GH_TOKEN) { "set" }' 0
run_ps 'PowerShell: $env:PATH' '$env:PATH' 0
run_ps 'PowerShell: Get-ChildItem env:PATH' 'Get-ChildItem env:PATH' 0
run_ps 'PowerShell: Get-Content of a template' 'Get-Content .env.example' 0
run_ps 'PowerShell: Get-Content of an ordinary file' 'Get-Content README.md' 0

# --- 8. Quoted prose is not a command (allowed) -------------------------------
run "commit message naming gh auth token" 'git commit -m "block gh auth token"' 0
run "commit message naming git credential fill" 'git commit -m "guard: no git credential fill"' 0
run "grep for git credential fill" "grep 'git credential fill' docs.md" 0
run "grep -c for gh auth token" "grep -c 'gh auth token' docs.md" 0
run "echo of a command as prose" 'echo "run gh auth token to see it"' 0
run "issue body naming .netrc" 'gh issue create --title "never cat .netrc" --body-file b.md' 0
run "issue body naming printenv" 'gh issue comment 1 --body "do not printenv GH_TOKEN"' 0
run "commit message naming a credential file read" 'git commit -m "docs: never cat .env"' 0
run_ps "PowerShell: commit message naming gh auth token" 'git commit -m "block gh auth token"' 0
run_ps "PowerShell: Select-String for the shape" "Select-String -Pattern 'git credential fill' docs.md" 0

# --- 9. Kill switch and allow list --------------------------------------------
run "kill switch false disables the guard" 'gh auth token' 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED=false
run_ps "kill switch false disables the guard (PowerShell)" 'gh auth token' 0 \
  CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED=false
run "kill switch true keeps the guard on" 'gh auth token' 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED=true
run "kill switch typo stays enabled (blocked)" 'gh auth token' 2 \
  CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED=maybe
typo_out=$(env CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED=maybe \
  bash "$HOOK" <<<"$(command_json 'gh auth token')" 2>&1)
assert_contains "kill switch typo names the bad value" "$typo_out" "block_credential_read_enabled=maybe"
assert_contains "kill switch typo says it stays enabled" "$typo_out" "treating as enabled"

allow="CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ALLOW"
run "allow gh-auth-token" 'gh auth token' 0 "$allow=gh-auth-token"
run "allow list is exact per family: gh-auth-token does not open credential-fill" 'git credential fill' 2 "$allow=gh-auth-token"
run "allow credential-fill" 'git credential fill' 0 "$allow=credential-fill"
run "allow env-echo, echo" 'echo $GH_TOKEN' 0 "$allow=env-echo"
run "allow env-echo, printenv" 'printenv GH_TOKEN' 0 "$allow=env-echo"
run "allow credential-file-read" 'cat .env' 0 "$allow=credential-file-read"
run "allow list with several tokens, first" 'gh auth token' 0 "$allow=gh-auth-token,env-echo"
run "allow list with several tokens, second" 'echo $GH_TOKEN' 0 "$allow=gh-auth-token,env-echo"
run "allow list keeps the other families blocked" 'cat .netrc' 2 "$allow=gh-auth-token,env-echo"
run "allow list does not match a substring of a token" 'gh auth token' 2 "$allow=gh-auth-token-x"
run_ps "allow list applies to PowerShell" 'Get-Content .env' 0 "$allow=credential-file-read"
# A command that trips two families needs both allowed.
run "one allowed family does not excuse another in the same command" \
  'gh auth token; cat .netrc' 2 "$allow=gh-auth-token"
run "both families allowed" 'gh auth token; cat .netrc' 0 "$allow=gh-auth-token,credential-file-read"

# --- 10. Inputs -----------------------------------------------------------------
rc=0
bash "$HOOK" </dev/null >/dev/null 2>&1 || rc=$?
assert_exit "empty stdin is a skip, not a block" 0 "$rc"

rc=0
bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{}}' >/dev/null 2>&1 || rc=$?
assert_exit "payload with no command is a skip" 0 "$rc"

rc=0
bash "$HOOK" <<<'not json' >/dev/null 2>&1 || rc=$?
assert_exit "text that is not JSON fails closed" 2 "$rc"

rc=0
bash "$HOOK" <<<"$(command_json "$(printf 'echo %.0s' {1..4000})")" >/dev/null 2>&1 || rc=$?
assert_exit "a long command with no shape is allowed" 0 "$rc"

rc=0
bash "$HOOK" <<<"$(command_json "gh auth token; $(printf 'x%.0s' {1..17000})")" >/dev/null 2>&1 || rc=$?
assert_exit "a command over the length ceiling is not parsed (declared gap)" 0 "$rc"

report
