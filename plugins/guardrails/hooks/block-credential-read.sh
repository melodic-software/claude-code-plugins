#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED:-false}" == "false" ]] && exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-credential-read PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

_bcr_enabled="${CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ENABLED:-false}"

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}
[[ "$_bcr_enabled" == true ]] ||
  guard::bad_switch_notice block_credential_read_enabled "$_bcr_enabled" "$INPUT"

hook::require_jq_blocking "guardrails-block-credential-read" "block_credential_read_enabled"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' || jq_rc=$?
guard::payload_verdict "$jq_rc" || exit $(($? == 3 ? 0 : 2))

COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0

MAX_COMMAND_LEN=16384
((${#COMMAND} > MAX_COMMAND_LEN)) && exit 0

SUBJECT="${COMMAND,,}"

[[ "$SUBJECT" =~ credential|token|secret|password|passwd|api_?key|access_key|private_key|printenv|_netrc|\.netrc|docker|env|\.ssh ]] || exit 0

allowed() {
  local list=",${CLAUDE_PLUGIN_OPTION_BLOCK_CREDENTIAL_READ_ALLOW:-},"
  [[ "$list" == *,"$1",* ]]
}

block() {
  local form="$1" shape="$2" fix="$3"
  printf '%s\n' \
    "BLOCKED: this command prints a credential ($shape) into the transcript. Check that it is present instead: $fix" \
    "Only the user can allow it ($form in block_credential_read_allow)." >&2
  exit 2
}

match_shapes() {
  local s="$SUBJECT" sp='[[:space:]]' sq="'" dq='"' nl=$'\n'
  local lead stmt
  local assign="(([a-z_][a-z0-9_]*=([^[:space:]${sq}${dq}]*|${sq}[^${sq}]*${sq}|${dq}[^${dq}]*${dq})${sp}+)*)"
  local end="([[:space:];&|)\`${sq}${dq}]|\$)"
  local pre="([^[:space:];&|\`(){}${sq}${dq}]*[/\\\\])?"
  local arg="[^;&|]"
  local tokvar='[a-z0-9_*?]*(token|secret|password|passwd|api_key|apikey|access_key|private_key|credential)[a-z0-9_*?]*'
  local dir="([^[:space:];&|${sq}${dq}]*[/\\\\])?"
  local jsonfile="(\\.credentials\\.json|\\.docker[/\\\\]config\\.json)"
  local keyfile="(\\.ssh[/\\\\]id_[a-z0-9_]+|\\.aws[/\\\\]credentials)"
  local credfile="${dir}(\\.git-credentials|\\.netrc|_netrc|\\.env(\\.[a-z0-9_.-]+)?|${jsonfile}|${keyfile})"
  local launch="((sudo|doas|env|exec|command|nohup|nice|time|xargs|timeout)(${sp}+-[^[:space:]]*|${sp}+[0-9][^[:space:]]*)*${sp}+)*"

  local re_shell="(^|[;&|(\`{${nl}])${sp}*${assign}${launch}${pre}(bash|sh|dash|zsh|ksh|pwsh|powershell|eval)(\\.exe)?[${sq}${dq}]?${sp}"
  if [[ "$s" =~ $re_shell ]]; then
    lead='(^|[^[:alnum:]_.-])'
    stmt='(^|[^[:alnum:]_.(-])'
  else
    lead="(^|[;&|(\`{${nl}])${sp}*${assign}"
    stmt="(^|[;&|{${nl}])${sp}*"
  fi

  while [[ "$s" =~ \$\{[a-z0-9_]+:\+[^}]*\} ]]; do
    s="${s/"${BASH_REMATCH[0]}"/}"
  done
  s="${s//.env.example/.x}"
  s="${s//.env.sample/.x}"
  s="${s//.env.template/.x}"

  local word="([^[:space:]${sq}${dq}]+|${sq}[^${sq}]*${sq}|${dq}[^${dq}]*${dq})"
  local sj="${COMMAND//\$ENV/\$jq_env_builtin}"
  sj="${sj,,}"
  while [[ "$sj" =~ ${sp}--arg(json)?${sp}+${word}${sp}+${word} ]]; do
    sj="${sj/"${BASH_REMATCH[0]}"/ }"
  done

  local re_fill="${lead}${pre}git(\\.exe)?(${sp}+(-c${sp}+[^[:space:]]+|-[^[:space:]]+))*${sp}+credential(${sp}+fill|-[^[:space:]]+${sp}+get)${end}"
  local re_fill_bin="${lead}${pre}git-credential-[^[:space:]]+${sp}+get${end}"
  local re_gh="${lead}${pre}gh(\\.exe)?(${sp}+-[^[:space:]]+)*${sp}+auth${sp}+token${end}"
  local re_printenv="${lead}${pre}printenv(\\.exe)?${sp}+(${arg}*${sp})?${tokvar}${end}"
  local re_echo="${lead}${pre}(echo|printf|write-output|write-host)(\\.exe)?${sp}+${arg}*\\\$\\{?(env:)?${tokvar}"
  local re_psvar="${stmt}\\\$\\{?env:${tokvar}"
  local re_psenv="${lead}${pre}(get-childitem|get-item|gci|gi|dir|ls)${sp}+(${arg}*${sp})?[${sq}${dq}]?env:[/\\\\]?${tokvar}"
  local re_file="${lead}${pre}(get-content|gc|type)(\\.exe)?${sp}+(${arg}*${sp})?[${sq}${dq}]?${credfile}${end}"
  local re_jqfile="${lead}${pre}jq(\\.exe)?${sp}+(${arg}*${sp})?[${sq}${dq}]?${dir}${jsonfile}${end}"
  local re_jqenv="${lead}${pre}jq(\\.exe)?${sp}+(${arg}*${sp})?[${sq}${dq}]?(env|\\\$jq_env_builtin)${end}"

  if ! allowed credential-fill && [[ "$s" =~ $re_fill || "$s" =~ $re_fill_bin ]]; then
    block credential-fill "git credential fill / git credential-<helper> get" \
      "gh auth status, or git ls-remote origin to test access"
  fi

  if ! allowed gh-auth-token && [[ "$s" =~ $re_gh ]]; then
    block gh-auth-token "gh auth token" \
      "gh auth status (exits 0 when logged in)"
  fi

  if ! allowed env-echo; then
    if [[ "$s" =~ $re_printenv || "$s" =~ $re_echo || "$s" =~ $re_psvar || "$s" =~ $re_psenv ]]; then
      block env-echo "a token-shaped environment variable" \
        "test -n \"\$NAME\" && echo set (PowerShell: if (\$env:NAME) { 'set' })"
    fi
    if [[ "$sj" =~ $re_jqenv ]]; then
      block env-echo "every environment variable, through jq env" \
        "test -n \"\$NAME\" && echo set"
    fi
  fi

  if ! allowed credential-file-read && { [[ "$s" =~ $re_file || "$sj" =~ $re_jqfile ]] || interpreter_reads "$s" "$lead" "$pre"; }; then
    block credential-file-read "a credential file: .git-credentials, .netrc, .env, .credentials.json, .docker/config.json, ~/.ssh/id_*, ~/.aws/credentials" \
      "test -f <path> && echo present (PowerShell: Test-Path <path>)"
  fi
}

interpreter_reads() {
  local s="$1" lead="$2" pre="$3" sp='[[:space:]]' nl=$'\n' sq="'" dq='"'
  local re_int="${lead}${pre}(python[0-9.]*|py|node|nodejs|deno|bun|ruby|perl|php)(\\.exe)?(${sp}|\$)"
  local path="(\\.git-credentials|\\.netrc|_netrc|\\.env(\\.[a-z0-9_-]+)?|\\.credentials\\.json|\\.docker[/\\\\]config\\.json|\\.ssh[/\\\\]id_[a-z0-9_]+|\\.aws[/\\\\]credentials)([^a-z0-9_.-]|\$)"
  local verb='(open|read|dotenv|file_get_contents|slurp|cat|source)'
  local lit="[${sq}${dq}]([^${sq}${dq}${nl}]*[^a-z0-9_${sq}${dq}${nl}])?"
  local re_read="${verb}[^${nl}]*${lit}${path}|${lit}${path}[^${nl}]*${verb}"
  local re_hd="<<-?${sp}*[${sq}${dq}]?([a-z0-9_]+)"
  local rest line code
  while [[ "$s" =~ $re_int ]]; do
    rest="${s#*"${BASH_REMATCH[0]}"}"
    line="${rest%%"$nl"*}"
    code="$line"
    if [[ "$line" =~ $re_hd && "$rest" == *"$nl"* ]]; then
      code+="$nl${rest#*"$nl"}"
      code="${code%%"$nl${BASH_REMATCH[1]}$nl"*}"
    fi
    [[ "$code" =~ $re_read ]] && return 0
    s="$rest"
  done
  return 1
}

match_shapes
exit 0
