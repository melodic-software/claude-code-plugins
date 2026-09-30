#!/usr/bin/env bash
# PreToolUse hook: block a command whose output is a credential.
#
# A shell tool call puts its stdout in the transcript. A command that prints a
# secret therefore writes the secret into the model's context, the session log
# and any tool that reads either. The discovery plugin's parent contract states
# the rule ("Credentials stay unread": verify presence, never read a value) and
# holds it by instruction only. This guard enforces the command half of it on
# the Bash and PowerShell tools.
#
# MATCHED SHAPES, one family per allow-list token:
#   credential-fill       `git credential fill`, `git credential-<helper> get`
#                         (`git credential-manager get`), `git-credential-<helper> get`
#   gh-auth-token         `gh auth token`
#   env-echo              `printenv` or `echo`/`printf` of a token-shaped variable;
#                         PowerShell `$env:X_TOKEN` as a statement, `Write-Output`/
#                         `Write-Host` of it, `Get-ChildItem`/`Get-Item env:X_TOKEN`.
#                         Token-shaped: the name contains TOKEN, SECRET, PASSWORD,
#                         PASSWD, API_KEY, APIKEY, ACCESS_KEY, PRIVATE_KEY or
#                         CREDENTIAL, in any case.
#   credential-file-read  `cat` (PowerShell `Get-Content`, `gc`, `type`) of
#                         `.git-credentials`, `.netrc`, `_netrc`, `.env` or `.env.*`.
#                         `.env.example`, `.env.sample` and `.env.template` carry no
#                         secret and are not matched.
#
# ALLOWED, because they answer presence without printing a value: `gh auth status`,
# `test -n "$GH_TOKEN"`, `[ -f ~/.netrc ]`, `printenv PATH`, `echo $HOME`,
# `echo "${GH_TOKEN:+set}"`, `echo ${#GH_TOKEN}`.
#
# COMMAND POSITION. A shape matches only where a command can start: the start of
# the string, or after ; & | ( ` { or a newline. So `git commit -m "block gh auth
# token"` and `grep 'git credential fill' docs.md` pass. The exception is a command
# string that also names a shell word (bash, sh, dash, zsh, ksh, pwsh, powershell,
# eval): quoted text can be handed to that shell and run, so any occurrence matches
# (`bash -c 'gh auth token'`).
#
# KNOWN GAPS (a deny rule is only partial; the parent contract says so too):
#   - readers other than the ones above: `python -c` and `node -e` opening a
#     credential file, `less`, `head`, `tail`, `sed`, `grep` and `bat` on one,
#     `.npmrc` and `.pypirc` auth lines, cloud CLI credential stores, SSH and GPG keys
#   - a bare `printenv`, `env` or `set`, which dumps every variable
#   - a variable whose name does not look like a token
#   - a shape assembled through expansion or `eval "$var"`, a wrapper such as `sudo`
#     or `xargs` in front, a keyword such as `then` or `do` in front, and an
#     encoded PowerShell command
#   - a command longer than the ceiling below, which is not parsed
# KNOWN FALSE POSITIVES, blocked fail-closed with the message below:
#   - a secret-shaped command whose output never reaches the transcript
#     (`curl -H "Authorization: Bearer $(gh auth token)" ...`, `gh auth token | wc -c`)
#   - `echo '$GITHUB_TOKEN'` (single quotes print the name), and a variable whose
#     name merely contains one of the words (`GH_TOKEN_FILE`)
#   - prose that quotes a shape beside a shell word in the same command string
#   - a shape spelled in a heredoc body
#
# Escape: the `block_credential_read_enabled` userConfig option (true/false; any
# other value keeps the guard on and says so) turns the guard off, and the
# comma-separated `block_credential_read_allow` option lists family tokens
# (credential-fill, gh-auth-token, env-echo, credential-file-read) to let through.
# userConfig is resolved at plugin-enable time, so an inline env prefix on the
# command cannot change either.
#
# BLOCKING: exits 2 on a detected shape that is not allow-listed.

set -uo pipefail

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off. Only the DISABLED arm is hoisted;
# a value that is neither `true` nor `false` keeps the guard on and says so
# through hook::emit_channels, which needs the library, so that arm runs below.
# scripts/check-killswitch-hoist.sh knows this shape.
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED:-true}" == "false" ]] && exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture: fail-open with a dual-channel "guard did not run" notice;
# 0 (allow) and 2 (block) pass through, like the other per-call Bash guards.
guard::abort_boundary block-credential-read PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

_bcr_enabled="${CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED:-true}"
if [[ "$_bcr_enabled" != "true" ]]; then
  _bcr_bad="guardrails block-credential-read: block_credential_read_enabled=${_bcr_enabled} is not exactly true or false; treating as enabled (a safety switch does not silently disable)"
  echo "$_bcr_bad" >&2
  hook::emit_channels PreToolUse "$_bcr_bad" "$_bcr_bad"
fi

# rc 1 (empty stdin) skips; rc 2 (not JSON) FAILS CLOSED; rc 3 (a payload cut
# short by the pipe, a transport fault) is a loud skip the dispatcher takes once.
hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require_jq_blocking "guardrails-block-credential-read" "block_credential_read_enabled"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' || jq_rc=$?
if ((jq_rc == 2)); then
  echo "BLOCKED: the hook payload could not be parsed." >&2
  exit 2
fi
((jq_rc != 0)) && exit 0

if ((HOOK_JQ_FIELDS_NUL)); then
  echo "BLOCKED: the payload carries a NUL byte, which a command cannot reliably carry." >&2
  echo "What a guard can read is not dependably what would run, so this is refused rather than matched." >&2
  echo "Fix: reissue the tool call without the embedded NUL." >&2
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0

# Past this length the command is not parsed (the dispatcher's own ceiling is the
# same number). A long command that reads a credential is not an accident.
MAX_COMMAND_LEN=16384
((${#COMMAND} > MAX_COMMAND_LEN)) && exit 0

# Everything below matches the lower-cased command: PowerShell names are case
# insensitive ($env:gh_token is the same variable), and only an exit code leaves
# this guard. No `shopt`: the dispatcher sources every guard into one shell, and
# a leaked nocasematch would change the guards sourced after this one.
SUBJECT="${COMMAND,,}"

# Cheap pre-filter: every shape below names one of these words, so a command
# that names none leaves without paying for the matcher.
[[ "$SUBJECT" =~ credential|token|secret|password|passwd|api_?key|access_key|private_key|printenv|_netrc|\.netrc|\.env ]] || exit 0

# Is a family token in the block_credential_read_allow userConfig comma list?
allowed() {
  local list=",${CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ALLOW:-},"
  [[ "$list" == *,"$1",* ]]
}

block() {
  local form="$1" shape="$2" fix="$3"
  printf '%s\n' \
    "BLOCKED: this command prints a credential ($shape); its output would land in the transcript." \
    "Fix: check that the credential is present instead of reading it:" \
    "  $fix" \
    "Never read, print or copy a credential value; record a capability you could not establish without one as a gap." \
    "Escape, if the read is intended: set the block_credential_read_enabled option to false, or add $form to block_credential_read_allow." >&2
  exit 2
}

# Each shape is one regex held in a variable: `;`, `&` and `|` are shell syntax
# when they sit unquoted inside a [[ =~ ]] pattern. Locals, because the guard is
# sourced into the dispatcher's shell.
match_shapes() {
  local s="$SUBJECT" sp='[[:space:]]' sq="'" dq='"' nl=$'\n'
  local lead stmt
  # End of a word: whitespace, a separator, a closing paren or quote, or end of string.
  local end="([[:space:];&|)${sq}${dq}]|\$)"
  # A command word may carry a directory prefix (/usr/bin/gh, C:\tools\gh).
  local pre="([^[:space:];&|\`(){}${sq}${dq}]*[/\\\\])?"
  local arg="[^;&|]"
  # A token-shaped variable name.
  local tokvar='[a-z0-9_*?]*(token|secret|password|passwd|api_key|apikey|access_key|private_key|credential)[a-z0-9_*?]*'
  # A path whose last part is a credential file.
  local credfile="([^[:space:];&|${sq}${dq}]*[/\\\\])?(\\.git-credentials|\\.netrc|_netrc|\\.env(\\.[a-z0-9_.-]+)?)"

  # A command string that names a shell may hand quoted text to it, so a shape
  # matches anywhere. `stmt` is `lead` without `(`: a bare PowerShell `$env:X`
  # after `(` is a condition, not output.
  if [[ "$s" =~ (^|[^[:alnum:]_.-])(bash|sh|dash|zsh|ksh|pwsh|powershell|eval)(\.exe)?[${sq}${dq}]?${sp} ]]; then
    lead='(^|[^[:alnum:]_.-])'
    stmt='(^|[^[:alnum:]_.(-])'
  else
    lead="(^|[;&|(\`{${nl}])${sp}*"
    stmt="(^|[;&|{${nl}])${sp}*"
  fi

  # Presence-shaped expansions print no value: drop `${NAME:+word}` before matching.
  while [[ "$s" =~ \$\{[a-z0-9_]+:\+[^}]*\} ]]; do
    s="${s/"${BASH_REMATCH[0]}"/}"
  done
  # Templates carry no secret.
  s="${s//.env.example/.x}"
  s="${s//.env.sample/.x}"
  s="${s//.env.template/.x}"

  local re_fill="${lead}${pre}git(\\.exe)?(${sp}+(-c${sp}+[^[:space:]]+|-[^[:space:]]+))*${sp}+credential(${sp}+fill|-[^[:space:]]+${sp}+get)${end}"
  local re_fill_bin="${lead}${pre}git-credential-[^[:space:]]+${sp}+get${end}"
  local re_gh="${lead}${pre}gh(\\.exe)?(${sp}+-[^[:space:]]+)*${sp}+auth${sp}+token${end}"
  local re_printenv="${lead}${pre}printenv(\\.exe)?${sp}+(${arg}*${sp})?${tokvar}${end}"
  local re_echo="${lead}${pre}(echo|printf|write-output|write-host)(\\.exe)?${sp}+${arg}*\\\$\\{?(env:)?${tokvar}"
  local re_psvar="${stmt}\\\$\\{?env:${tokvar}"
  local re_psenv="${lead}${pre}(get-childitem|get-item|gci|gi|dir|ls)${sp}+(${arg}*${sp})?[${sq}${dq}]?env:[/\\\\]?${tokvar}"
  local re_file="${lead}${pre}(cat|get-content|gc|type)(\\.exe)?${sp}+(${arg}*${sp})?[${sq}${dq}]?${credfile}${end}"

  if ! allowed credential-fill && [[ "$s" =~ $re_fill || "$s" =~ $re_fill_bin ]]; then
    block credential-fill "git credential fill / git credential-<helper> get" \
      "gh auth status    (or a request that needs no token, or  git ls-remote origin  to test access)"
  fi

  if ! allowed gh-auth-token && [[ "$s" =~ $re_gh ]]; then
    block gh-auth-token "gh auth token" \
      "gh auth status    (exit code 0 when logged in; prints no token)"
  fi

  if ! allowed env-echo &&
    [[ "$s" =~ $re_printenv || "$s" =~ $re_echo || "$s" =~ $re_psvar || "$s" =~ $re_psenv ]]; then
    block env-echo "a token-shaped environment variable" \
      "test -n \"\$NAME\" && echo set     (PowerShell:  if (\$env:NAME) { 'set' })"
  fi

  if ! allowed credential-file-read && [[ "$s" =~ $re_file ]]; then
    block credential-file-read "a credential file: .git-credentials, .netrc, .env" \
      "test -f <path> && echo present     (PowerShell:  Test-Path <path>)"
  fi
}

match_shapes
exit 0

