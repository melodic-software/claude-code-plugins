#!/usr/bin/env bash
# Exit 0 clean, 1 failures, 2 environment.
set -uo pipefail

here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)" || exit 2
scratch="$(mktemp -d)" || exit 2
trap 'rm -rf -- "${scratch:?}"' EXIT

fails=0
count=0

check() {
  local name="$1" want="$2" dir="$3"
  shift 3
  local out rc
  out="$(env -i "$@" "$BASH" "$dir/chat-surface.sh")"
  rc=$?
  count=$((count + 1))
  if [[ $rc -ne 0 ]]; then
    printf 'FAIL %s: exit %s\n' "$name" "$rc"
    fails=$((fails + 1))
  elif [[ "$out" != "$want" ]]; then
    printf 'FAIL %s: printed %q, want %q\n' "$name" "$out" "$want"
    fails=$((fails + 1))
  else
    printf 'ok   %s\n' "$name"
  fi
}

check "no variables is terminal" terminal "$here"
check "CLI entrypoint is terminal" terminal "$here" CLAUDE_CODE_ENTRYPOINT=cli
check "CLI mirrored by Remote Control stays terminal" terminal "$here" CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_CLIENT_PRESENCE_FILE=/x
check "desktop entrypoint is desktop" desktop "$here" CLAUDE_CODE_ENTRYPOINT=claude-desktop
check "cloud from the phone is mobile" mobile "$here" CLAUDE_CODE_ENTRYPOINT=remote_mobile CLAUDE_CODE_REMOTE=true
check "cloud otherwise is web" web "$here" CLAUDE_CODE_ENTRYPOINT=remote_web CLAUDE_CODE_REMOTE=true
check "cloud with no entrypoint is web" web "$here" CLAUDE_CODE_REMOTE=true
check "remote_mobile without the cloud flag is terminal" terminal "$here" CLAUDE_CODE_ENTRYPOINT=remote_mobile
check "remote flag other than true is terminal" terminal "$here" CLAUDE_CODE_REMOTE=1
check "unknown entrypoint is terminal" terminal "$here" CLAUDE_CODE_ENTRYPOINT=something-new

for value in terminal desktop web mobile; do
  check "override $value wins over detection" "$value" "$here" CHAT_SURFACE="$value" CLAUDE_CODE_ENTRYPOINT=claude-desktop CLAUDE_CODE_REMOTE=true
done
check "invalid override is ignored" mobile "$here" CHAT_SURFACE=phone CLAUDE_CODE_ENTRYPOINT=remote_mobile CLAUDE_CODE_REMOTE=true
check "empty override is ignored" desktop "$here" CHAT_SURFACE= CLAUDE_CODE_ENTRYPOINT=claude-desktop

mkdir "$scratch/no-env" && cp "$here/chat-surface.sh" "$scratch/no-env/" || exit 2
check "missing env file is terminal" terminal "$scratch/no-env" CHAT_SURFACE=mobile CLAUDE_CODE_REMOTE=true

mkdir "$scratch/bad-env" && cp "$here/chat-surface.sh" "$scratch/bad-env/" || exit 2
printf 'CHAT_SURFACE_REMOTE_VAR=1BAD\nCHAT_SURFACE_REMOTE_VALUE=true\n' >"$scratch/bad-env/chat-surface.env" || exit 2
check "invalid variable name in env file is terminal" terminal "$scratch/bad-env" 1BAD=true

printf '%s checks, %s failed\n' "$count" "$fails"
[[ $fails -eq 0 ]]
