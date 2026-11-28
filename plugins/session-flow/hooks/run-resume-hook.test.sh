#!/usr/bin/env bash
# test-scope: plugins/session-flow/hooks/hooks.json plugins/session-flow/scripts/resume_hook.py plugins/session-flow/scripts/focus.py plugins/session-flow/scripts/plugin_paths.py plugins/session-flow/reference/resume.md plugins/session-flow/lib/python-probe.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RUNNER="$SCRIPT_DIR/run-resume-hook.sh"
PASS=0
FAIL=0

expect() {
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS + 1))
    echo "PASS: $1"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 (expected '$2', got '$3')"
  fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DATA="$WORK/session-flow"
HANDOFF="$WORK/.work/handoffs/20261124T100000Z-handoff-widget.md"
mkdir -p "${HANDOFF%/*}"
printf -- '---\nhandoff_shape: 5\n---\n' >"$HANDOFF"
DIRECTIVE="Read @@DIR@/.work/handoffs/20261124T100000Z-handoff-widget.md, confirm its Original goal still governs the remaining next steps, then continue them."
prompt_payload() {
  printf '{"session_id":"census","transcript_path":"@TRANSCRIPT@","cwd":"@DIR@","hook_event_name":"UserPromptSubmit","permission_mode":"auto","prompt":"%s"}' "$1"
}

fire() {
  local body="$1"
  shift
  env -u CLAUDE_PLUGIN_OPTION_RESUME_CONTEXT_ENABLED HOME="$WORK/home" CLAUDE_PLUGIN_DATA="$DATA" "$@" \
    bash "$RUNNER" <<<"${body//@DIR@/$WORK}"
}

out="$(fire "$(prompt_payload "$DIRECTIVE")")"
expect "a resume directive injects the procedure" "0|yes" "$?|$([[ "$out" == *"session-flow resume procedure"* ]] && echo yes)"

out="$(fire "$(prompt_payload "$DIRECTIVE")")"
expect "a second paste in the session is silent" "0|" "$?|$out"

out="$(fire "$(prompt_payload "$DIRECTIVE")" CLAUDE_PLUGIN_DATA="$WORK/other" CLAUDE_PLUGIN_OPTION_RESUME_CONTEXT_ENABLED=false)"
expect "the user's false: silent exit 0" "0|" "$?|$out"

CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1 && strace -qq -o /dev/null -e trace=execve true 2>/dev/null; then
  census() {
    local body="$1" check="$2"
    shift 2
    bash "$CENSUS" session-flow UserPromptSubmit run-resume-hook.sh "$body" "$@" --check "$check"
  }
  quiet="test ! -s \"\$HOOK_STDOUT\""
  setup="mkdir -p .work/handoffs && printf -- '---\nhandoff_shape: 5\n---\n' >.work/handoffs/20261124T100000Z-handoff-widget.md"

  out="$(census "$(prompt_payload "fix the parser")" "$quiet")"
  expect "spawn budget: an ordinary prompt costs only the node launcher" "spawns=1" "${out%% *}"
  out="$(census "$(prompt_payload "$DIRECTIVE")" "$quiet" --setup "$setup" \
    --env CLAUDE_PLUGIN_OPTION_RESUME_CONTEXT_ENABLED=false)"
  expect "spawn budget: a directive with the user's setting off stops in bash" "spawns=3" "${out%% *}"
  out="$(census "$(prompt_payload "$DIRECTIVE")" "grep -q 'session-flow resume procedure' \"\$HOOK_STDOUT\"" --setup "$setup")"
  expect "spawn budget: an injection is bash, the Python probe and resume_hook.py" "spawns=7" "${out%% *}"
else
  echo "NOTE: a working strace or scripts/hook-census.sh is absent; the spawn budget cases did not run."
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
