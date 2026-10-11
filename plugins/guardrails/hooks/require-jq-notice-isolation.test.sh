#!/usr/bin/env bash
# Cross-hook contract test: every guardrails hook's fail-open hook::require jq
# call passes the plugin name as its notice label, so the whole plugin shares
# one latch per channel.
#
# The jq notice speaks for the plugin ("guardrails: jq not on the hook PATH.
# Without jq, guardrails denies ... and skips its other file checks."), so one notice
# per session covers every guard. A per-hook label told the model once per
# guard, and its user marker never matched the one the SessionStart
# prerequisites probe writes (`<plugin>-<id>.<session>.user`), so the user
# heard the same news from the probe and again from the first skip.
#
# jq is hidden by the BASH_ENV shim require-jq-posture.test.sh documents: the
# LOOKUP of jq fails, PATH is untouched.
# test-scope: plugins/guardrails/hooks/*.sh plugins/guardrails/.claude-plugin/plugin.json plugins/guardrails/prerequisites.json
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

PLUGIN_NAME=$(jq -r .name "$HOOK_DIR/../.claude-plugin/plugin.json")

# Every hook whose source CALLS the FAIL-OPEN hook::require jq, discovered, not
# hand-enumerated. The anchor skips hook::require_jq_blocking, the fail-closed
# gate, which denies every call and has no latch (require-jq-posture.test.sh).
mapfile -t JQ_HOOKS < <(
  for f in "$HOOK_DIR"/*.sh; do
    base="${f##*/}"
    case "$base" in
    hook-utils.sh | *.test.sh) continue ;;
    *) ;;
    esac
    grep -lE 'hook::require jq[[:space:]]' "$f" 2>/dev/null || true
  done | sort
)
if ((${#JQ_HOOKS[@]} < 2)); then
  bad "expected at least 2 guardrails hooks calling the fail-open hook::require jq, found ${#JQ_HOOKS[@]}"
fi

# --- Every hook passes the plugin name as the label --------------------------
for h in "${JQ_HOOKS[@]}"; do
  label=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^hook::require[[:space:]]+jq[[:space:]]+\"?[A-Za-z]+\"?[[:space:]]+\"?([^\"[:space:]]+)\"? ]]; then
      label="${BASH_REMATCH[1]}"
      break
    fi
  done <"$h"
  assert_eq "${h##*/}: hook::require jq labels the notice with the plugin name" "$PLUGIN_NAME" "$label"
done

# --- Runtime: one notice per session across guards --------------------------
HIDE_JQ="$TEST_TMPDIR/hide-jq.sh"
# shellcheck disable=SC2016  # the shim's own expansions run in the hook's shell
printf '%s\n' \
  'command() { local a; for a in "$@"; do [[ "$a" == jq ]] && return 1; done; builtin command "$@"; }' \
  'jq() { return 127; }' >"$HIDE_JQ"

# run_hidden <data-dir> <hook> <payload> -> stdout of the hook with jq hidden.
run_hidden() {
  BASH_ENV="$HIDE_JQ" CLAUDE_PLUGIN_DATA="$1" CLAUDE_PLUGIN_ROOT="$HOOK_DIR/.." \
    bash "$HOOK_DIR/$2" <<<"$3" 2>/dev/null
}

BASH_PAYLOAD='{"session_id":"latch-s1","tool_name":"Bash","tool_input":{"command":"git status"}}'
DATA="$TEST_TMPDIR/data-shared"
out=$(run_hidden "$DATA" block-hook-bypass.sh "$BASH_PAYLOAD")
assert_contains "first guard: the user is told" "$(jq -r '.systemMessage // empty' <<<"$out")" \
  "$PLUGIN_NAME: jq not on the hook PATH"
assert_contains "first guard: the model is told" \
  "$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out")" "$PLUGIN_NAME: jq not on the hook PATH"
out=$(run_hidden "$DATA" block-noncanonical-commit.sh "$BASH_PAYLOAD")
assert_silent "second guard in the same session and agent: stays quiet" "$out"

# The SessionStart probe already told the user: the first skip tells the model only.
DATA2="$TEST_TMPDIR/data-probed"
mkdir -p "$DATA2/skip-notices"
: >"$DATA2/skip-notices/${PLUGIN_NAME}-jq.latch-s1.user"
out=$(run_hidden "$DATA2" block-hook-bypass.sh "$BASH_PAYLOAD")
assert_eq "after the probe: no second user notice" "" "$(jq -r '.systemMessage // empty' <<<"$out")"
assert_contains "after the probe: the model is still told once" \
  "$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out")" "$PLUGIN_NAME: jq not on the hook PATH"

report
