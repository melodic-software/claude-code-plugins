#!/usr/bin/env bash
# test-scope: plugins/session-flow/hooks/hooks.json plugins/session-flow/scripts/focus.py plugins/session-flow/lib/python-probe.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RUNNER="$SCRIPT_DIR/run-focus-hook.sh"
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
SESSION="census"
precompact='{"session_id":"census","transcript_path":"@TRANSCRIPT@","cwd":"@DIR@","hook_event_name":"PreCompact","trigger":"auto","custom_instructions":null}'
prompt_payload() {
  printf '{"session_id":"census","transcript_path":"@TRANSCRIPT@","cwd":"@DIR@","hook_event_name":"UserPromptSubmit","permission_mode":"auto","prompt":"%s"}' "$1"
}

fire() {
  local event="$1" body="$2"
  shift 2
  env -u CLAUDE_PLUGIN_OPTION_COMPACT_FOCUS_ENABLED HOME="$WORK" CLAUDE_PLUGIN_DATA="$DATA" "$@" \
    bash "$RUNNER" "$event" <<<"${body//@DIR@/$WORK}"
}

out="$(fire PreCompact "$precompact")"
expect "PreCompact with no focus folder: silent exit 0" "0|" "$?|$out"

out="$(fire UserPromptSubmit "$(prompt_payload "/goal runner condition")")"
expect "a typed /goal writes the focus file and prints nothing" "0||yes" \
  "$?|$out|$([[ -s "$DATA/focus/$SESSION.md" ]] && echo yes)"

out="$(fire PreCompact "$precompact")"
expect "PreCompact prints the focus file" "0|yes" "$?|$([[ "$out" == *"its condition: runner condition"* ]] && echo yes)"

NOPY="$WORK/nopy"
mkdir -p "$NOPY"
for stub in python3 python; do
  printf '#!/usr/bin/env bash\nexit 127\n' >"$NOPY/$stub"
  chmod +x "$NOPY/$stub"
done
out="$(fire PreCompact "$precompact" CLAUDE_PLUGIN_OPTION_COMPACT_FOCUS_ENABLED=false)"
expect "the user's false: silent exit 0" "0|" "$?|$out"

out="$(fire PreCompact "$precompact" PATH="$NOPY:$PATH")"
expect "no Python at the floor: silent exit 0" "0|" "$?|$out"

CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1 && strace -qq -o /dev/null -e trace=execve true 2>/dev/null; then
  CENSUS_DATA="$WORK/census/session-flow"
  mkdir -p "$CENSUS_DATA"
  census() {
    local event="$1" body="$2" check="$3"
    shift 3
    bash "$CENSUS" session-flow "$event" run-focus-hook.sh "$body" --env "CLAUDE_PLUGIN_DATA=$CENSUS_DATA" "$@" --check "$check"
  }
  quiet="test ! -s \"\$HOOK_STDOUT\""

  out="$(census UserPromptSubmit "$(prompt_payload "fix the parser")" "$quiet")"
  expect "spawn budget: an ordinary prompt costs only the node launcher" "spawns=1" "${out%% *}"
  out="$(census UserPromptSubmit "$(prompt_payload "/goal off by user")" "$quiet" \
    --env CLAUDE_PLUGIN_OPTION_COMPACT_FOCUS_ENABLED=false)"
  expect "spawn budget: a /goal with the user's setting off stops in bash" "spawns=3" "${out%% *}"
  out="$(census PreCompact "$precompact" "$quiet")"
  expect "spawn budget: PreCompact with no focus folder stops in bash" "spawns=3" "${out%% *}"
  out="$(census UserPromptSubmit "$(prompt_payload "/goal census condition")" \
    "test -s '$CENSUS_DATA/focus/$SESSION.md' && $quiet")"
  expect "spawn budget: a /goal write is bash, the Python probe and focus.py" "spawns=7" "${out%% *}"
  out="$(census PreCompact "$precompact" "grep -q 'census condition' \"\$HOOK_STDOUT\"")"
  expect "spawn budget: PreCompact printing the focus file" "spawns=7" "${out%% *}"
  out="$(census PreCompact "$precompact" "$quiet" --env CLAUDE_PLUGIN_OPTION_COMPACT_FOCUS_ENABLED=false)"
  expect "spawn budget: PreCompact with the user's setting off stops in bash" "spawns=3" "${out%% *}"
  out="$(census PreCompact "$precompact" "grep -q 'census condition' \"\$HOOK_STDOUT\"" \
    --env CLAUDE_PLUGIN_OPTION_COMPACT_FOCUS_ENABLED=yes)"
  expect "an invalid user value reaches focus.py, which drops it and prints" "spawns=7" "${out%% *}"
else
  echo "NOTE: a working strace or scripts/hook-census.sh is absent; the spawn budget cases did not run."
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
