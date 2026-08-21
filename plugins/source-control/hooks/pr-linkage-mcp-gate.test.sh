#!/usr/bin/env bash
# Black-box contract test for pr-linkage-mcp-gate.sh — the MCP-surface sibling
# of pr-body-linkage-gate.test.sh. Same caveat as that file: expectations are
# transcribed by hand from a reading of the ci-workflows pr-issue-linkage
# validator, not proven against it. What these cases cover is the payload
# handling unique to the MCP surface (create-without-body blocks,
# update-without-body allows, owner/repo scope guard, kill switch) plus the
# validator shapes a hand port gets wrong (comment stripping, deeper headings
# as Related content, bare `Closes #`).
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures
# and invokes the hook as a subprocess.

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/pr-linkage-mcp-gate.sh"

PASS=0
FAIL=0

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH -- pr-linkage-mcp-gate tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GATED="$WORK/gated"
NOGATE="$WORK/nogate"
NOORIGIN="$WORK/noorigin"
mkdir -p "$GATED/.github/workflows" "$NOGATE" "$NOORIGIN/.github/workflows"
: >"$GATED/.github/workflows/pr-issue-linkage.yml"
: >"$NOORIGIN/.github/workflows/pr-issue-linkage.yml"
git -C "$GATED" init -q
git -C "$GATED" remote add origin https://github.com/acme-corp/widgets.git
git -C "$NOGATE" init -q
git -C "$NOORIGIN" init -q

# run <expected-exit> <name> <cwd> <payload-json>
run() {
  local expected="$1" name="$2" dir="$3" payload="$4" rc=0
  bash "$HOOK" <<<"$payload" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (expected exit $expected, got $rc)" >&2
  fi
}

# payload <cwd> <tool> <owner> <repo> [body] — body omitted = no body field.
payload() {
  local dir="$1" tool="$2" owner="$3" repo="$4"
  if (($# >= 5)); then
    jq -cn --arg d "$dir" --arg t "$tool" --arg o "$owner" --arg r "$repo" --arg b "$5" \
      '{session_id:"test", cwd:$d, tool_name:$t, tool_input:{owner:$o, repo:$r, title:"t", body:$b}}'
  else
    jq -cn --arg d "$dir" --arg t "$tool" --arg o "$owner" --arg r "$repo" \
      '{session_id:"test", cwd:$d, tool_name:$t, tool_input:{owner:$o, repo:$r, title:"t"}}'
  fi
}

CREATE=mcp__github__create_pull_request
UPDATE=mcp__github__update_pull_request
OWNER=acme-corp
REPO=widgets

GOOD=$'Closes #12\n\n## Summary\n\nx\n\n## Related\n\n- N/A'
NO_RELATED=$'Closes #12\n\n## Summary\n\nx'
EMPTY_RELATED=$'Closes #12\n\n## Related\n'
NO_KEYWORD=$'## Summary\n\nx\n\n## Related\n\n- N/A'
OPTOUT=$'No linked issue\n\n## Related\n\n- N/A'
OPTOUT_ALIAS=$'No related issue: tracked in the profile file itself.\n\n## Related\n\n- N/A'
PAST_TENSE=$'Fixed #31\n\n## Related\n\n- N/A'
COMMENTED=$'<!-- Closes #12 -->\n\n## Summary\n\nx\n\n<!-- ## Related\n- N/A -->'
BARE_HASH=$'Closes #\n\n## Related\n\n- N/A'
DEEP_HEADING=$'Fixes #7\n\n## Related\n\n### sub\n\ncontent'
CROSS_REPO=$'Resolves other/repo#9\n\n## Related\n\n- N/A'

run 0 "valid body passes" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$GOOD")"
run 2 "missing Related blocks" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$NO_RELATED")"
run 2 "empty Related blocks" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$EMPTY_RELATED")"
run 2 "missing keyword blocks" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$NO_KEYWORD")"
run 0 "No linked issue opt-out passes" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$OPTOUT")"
run 0 "No related issue alias passes" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$OPTOUT_ALIAS")"
run 0 "past-tense keyword (Fixed #N) passes" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$PAST_TENSE")"
run 2 "markers only inside HTML comments block" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$COMMENTED")"
run 2 "bare 'Closes #' with no number blocks" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$BARE_HASH")"
run 0 "deeper heading is Related content" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$DEEP_HEADING")"
run 0 "owner/repo#N keyword form passes" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$CROSS_REPO")"
run 2 "create with no body field blocks (empty body)" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO)"
run 0 "update with no body field passes" "$GATED" "$(payload "$GATED" $UPDATE $OWNER $REPO)"
run 2 "update with bad body blocks" "$GATED" "$(payload "$GATED" $UPDATE $OWNER $REPO "$NO_RELATED")"
run 0 "different target repo is out of scope" "$GATED" "$(payload "$GATED" $CREATE other-org other-repo "$NO_RELATED")"
run 0 "gated repo with no origin remote allows (undeterminable target)" "$NOORIGIN" "$(payload "$NOORIGIN" $CREATE $OWNER $REPO "$NO_RELATED")"
run 0 "repo without the gate file never blocks" "$NOGATE" "$(payload "$NOGATE" $CREATE $OWNER $REPO "$NO_RELATED")"
run 0 "unrelated tool passes" "$GATED" "$(payload "$GATED" mcp__github__get_me $OWNER $REPO "$NO_RELATED")"
run 0 "empty stdin allows" "$GATED" ""

# Defer-guard: a consumer repo tracking its OWN equivalent gate in
# .claude/settings.json makes the plugin copy yield (deferred, exit 0) so the
# two never double-fire; unrelated settings wiring does not defer.
mkdir -p "$GATED/.claude"
cat >"$GATED/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"^mcp__github__(create|update)_pull_request$","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pr-linkage-mcp-gate.sh"}]}]}}
JSON
run 0 "consumer's own tracked gate defers the plugin copy" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$NO_RELATED")"
cat >"$GATED/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"^mcp__github__(create|update)_pull_request$","hooks":[{"type":"command","command":"bash","args":[".claude/hooks/pr-linkage-mcp-gate.sh"]}]}]}}
JSON
run 0 "exec-form wiring (gate name only in args) also defers" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$NO_RELATED")"
cat >"$GATED/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/other-gate.sh"}]}]}}
JSON
run 2 "unrelated settings hooks do not defer" "$GATED" "$(payload "$GATED" $CREATE $OWNER $REPO "$NO_RELATED")"

# Deferral telemetry envelope: status must be the documented "skipped" (an
# unknown status maps to error in the reference sink); the domain detail rides
# data.outcome. Capture the envelope with a stub sink and assert both fields.
cat >"$GATED/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"^mcp__github__(create|update)_pull_request$","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pr-linkage-mcp-gate.sh"}]}]}}
JSON
SINK="$WORK/capture-sink.sh"
CAPTURE="$WORK/captured-envelope.json"
printf '#!/usr/bin/env bash\ncat > "%s"\n' "$CAPTURE" >"$SINK"
chmod +x "$SINK"
HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$GATED" \
  bash "$HOOK" <<<"$(payload "$GATED" $CREATE $OWNER $REPO "$NO_RELATED")" >/dev/null 2>&1 || true
# The sink is fire-and-forget (backgrounded); poll in 20ms steps like the
# established wait_for_sink helper (markdown-format.test.sh) — a coarse sleep
# races variable process-spawn latency, notably on Windows Git Bash.
for _ in $(seq 1 150); do [[ -s "$CAPTURE" ]] && break; sleep 0.02; done
if [[ -s "$CAPTURE" ]] &&
  jq -e '.status == "skipped" and .data.outcome == "deferred"' "$CAPTURE" >/dev/null 2>&1; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: deferral envelope carries status=skipped + data.outcome=deferred (got: $(cat "$CAPTURE" 2>/dev/null))" >&2
fi
rm -rf "$GATED/.claude"

# Kill switch: disabled via the userConfig mirror allows a bad body through.
rc=0
CLAUDE_PLUGIN_OPTION_PR_LINKAGE_MCP_GATE_ENABLED=false \
  bash "$HOOK" <<<"$(payload "$GATED" $CREATE $OWNER $REPO "$NO_RELATED")" >/dev/null 2>&1 || rc=$?
if [[ "$rc" == "0" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: kill switch disables the gate (expected exit 0, got $rc)" >&2
fi

echo "pass=$PASS fail=$FAIL"
((FAIL == 0))
