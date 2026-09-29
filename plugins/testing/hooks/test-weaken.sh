#!/usr/bin/env bash
# PreToolUse hook: name what an Edit or Write takes away from a test file.
#
# ADVISORY by default: exits 0 with additionalContext and no
# permissionDecision field at all, because an `allow` would skip the user's
# permission prompt. Opt-in and path-scoped exactly as test-scan.sh is.
#
# Weakening, against the text the call replaces: fewer test blocks, fewer
# assertion tokens, more skip markers (the adapter's test_skip and body_skip),
# or an equality whose actual side stayed while its literal expected side
# changed. cant-fail-scan.sh --inventory counts both sides with the file's own
# adapter and config, so this hook holds no token list of its own. An Edit
# compares old_string with new_string; a Write compares the file on disk with
# content, and a Write that creates the file weakens nothing (hook::begin exits
# on a path that does not exist yet). A side the lexer ends inside a string or
# comment is not judged.
#
# With `rules: {test-weaken-block: error}` in .claude/testing.yaml, an added
# skip or a removed test block is denied unless the new text carries more
# `test-change: <reason>` markers than the old. The agent can write that
# marker itself: it makes the reason visible to reviewers and proves nothing.
# Removed assertions and changed literals never deny.
#
# Test seams: TEST_WEAKEN_SCANNER replaces the scanner, TEST_WEAKEN_TIMEOUT
# (seconds, default 8, below the hooks.json timeout of 10) bounds it.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED:-false}" == "true" ]] || exit 0

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=rewrite-guard.sh
source "$HOOK_DIR/rewrite-guard.sh"

hook::begin --no-membership test-weaken PreToolUse

if hook::gitignored_out_of_scope false "$FILE"; then
  hook::finish skipped findings array '[]'
fi

hook::jq_fields "$INPUT" '.tool_name' '.tool_use_id' '.tool_input.old_string' '.tool_input.new_string' \
  '.tool_input.content' || exit 0
tool="${HOOK_JQ_FIELDS[0]}" call="${HOOK_JQ_FIELDS[1]}"

DATA="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/testing-plugin-data}"
mkdir -p "$DATA/marks" 2>/dev/null
# Two `if` rows can match one path; only the run that creates the marker
# reports. PreToolUse and PostToolUse share a tool_use_id, so the name stays
# apart from test-scan's call- marker (test-scan prunes both).
if [[ -n "$call" ]] && ! (set -o noclobber && : >"$DATA/marks/weaken-$call") 2>/dev/null; then exit 0; fi

work="$(mktemp -d)" || exit 0
trap 'rm -rf "$work"' EXIT
case "$tool" in
Edit)
  printf '%s' "${HOOK_JQ_FIELDS[2]}" >"$work/old"
  printf '%s' "${HOOK_JQ_FIELDS[3]}" >"$work/new"
  old="$work/old"
  ;;
Write)
  printf '%s' "${HOOK_JQ_FIELDS[4]}" >"$work/new"
  old="$FILE"
  ;;
*) hook::finish skipped findings array '[]' ;;
esac

SCANNER="${TEST_WEAKEN_SCANNER:-$HOOK_DIR/../skills/audit/scripts/cant-fail-scan.sh}"
bash "$SCANNER" --file "$FILE" --inventory "$old" --inventory "$work/new" >"$work/out" 2>&1 &
pid=$!
(
  sleep "${TEST_WEAKEN_TIMEOUT:-8}"
  kill "$pid"
) >/dev/null 2>&1 &
watchdog=$!
wait "$pid"
rc=$?
kill "$watchdog" 2>/dev/null

if ((rc != 0)); then
  why="scanner exited $rc"
  ((rc > 128)) && why="scanner timed out after ${TEST_WEAKEN_TIMEOUT:-8}s"
  printf '%s test-weaken: %s: %s\n' "$(date -u +%FT%TZ)" "$FILE" "$why" >>"$DATA/test-weaken.log"
  printf 'test-weaken: %s: %s\n' "$FILE" "$why" >&2
  hook::finish error findings array '[]'
fi

# Side 1 is the old text, side 2 the new. The first output line is
# `block|advise <tab> <test-weaken-block level>`; nothing is printed when the
# edit weakens nothing or a side is unjudged. A skip that replaces a test start
# (it -> it.skip) counts once, as the skip.
report="$(awk -F'\t' '
function names(a, b, kind,    i, t, n) {
  for (i = 1; i <= KN[a, kind]; i++) {
    t = K[a, kind, i]
    if (L[a, kind, t] <= L[b, kind, t]) continue
    if (++n > 5) { out = out "\n    ..."; break }
    out = out "\n    " t
  }
}
$1 == "rule" { if ($2 == "test-weaken-block") level = $3; next }
$2 == "unjudged" { unj = 1; next }
$2 == "expect" {
  if (!(($1, $3, $4) in P)) { N[$1]++; PA[$1, N[$1]] = $3; PE[$1, N[$1]] = $4 }
  P[$1, $3, $4]++
  next
}
$2 == "test" || $2 == "assertion" || $2 == "skip" {
  C[$1, $2] += $3
  if (!(($1, $2, $4) in L)) K[$1, $2, ++KN[$1, $2]] = $4
  L[$1, $2, $4] += $3
}
END {
  if (unj) exit
  sk = C[2, "skip"] - C[1, "skip"]
  rt = C[1, "test"] - C[2, "test"] - (sk > 0 ? sk : 0)
  ra = C[1, "assertion"] - C[2, "assertion"]
  if (rt > 0) { block = 1; out = out "\n- removed " rt " test block(s):"; names(1, 2, "test") }
  if (sk > 0) { block = 1; out = out "\n- added " sk " skip marker(s):"; names(2, 1, "skip") }
  if (ra > 0) { out = out "\n- removed " ra " assertion token(s):"; names(1, 2, "assertion") }
  for (i = 1; i <= N[1]; i++) {
    a = PA[1, i]; e = PE[1, i]
    if (P[1, a, e] <= P[2, a, e]) continue
    for (j = 1; j <= N[2]; j++)
      if (PA[2, j] == a && PE[2, j] != e && P[2, a, PE[2, j]] > P[1, a, PE[2, j]])
        out = out "\n- changed the expected value of " a " from " e " to " PE[2, j]
  }
  if (out != "") printf "%s\t%s%s\n", block ? "block" : "advise", level, out
}' "$work/out")"
[[ -n "$report" ]] || hook::finish ok findings array '[]'
head="${report%%$'\n'*}"
body="${report#*$'\n'}"

lead="testing: $FILE_BASE: this $tool weakens its tests:"$'\n'"$body"
((${#lead} < 9000)) || lead="${lead:0:8800}"$'\n'"(truncated)"

# grep -c prints 0 and exits 1 on no match; the count is what matters.
if [[ "$head" == block$'\t'error ]] &&
  (($(grep -c 'test-change:[[:space:]]*[^[:space:]]' "$work/new") <= $(grep -c 'test-change:[[:space:]]*[^[:space:]]' "$old"))); then
  reason="$lead"$'\n'"rules.test-weaken-block is error in .claude/testing.yaml, so a skipped or removed test needs a stated reason. If the change is deliberate, retry the same edit with a comment in the edited text that reads test-change: <reason>, naming why the test goes (a removed feature, a tracked flaky test). Never skip or delete a test to make failing code pass."
  esc=""
  hook::json_escape_to esc "$reason"
  if [[ -n "${start:-}" ]] && hook::telemetry_enabled; then
    data=""
    hook::data_json_to data "${TOOL:-}" "${FILE_REL:-}" ""
    hook::emit_telemetry "$HOOK_PLUGIN" PreToolUse blocked "$start" "$data" "${REPO_ROOT:-}"
  fi
  hook::emit_document '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"$esc"'"}}'
  exit 0
fi

ctx="$lead"$'\n'"Before you continue, state the reason for each change (a changed requirement, a wrong expected value, a test of removed code). Never weaken a test to make failing code pass: fix the code instead."
hook::finish --context "$ctx" ok findings array '[]'
