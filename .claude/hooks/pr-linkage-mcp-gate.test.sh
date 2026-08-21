#!/usr/bin/env bash
# Tests for pr-linkage-mcp-gate.sh. Builds a throwaway fixture repo carrying
# the pr-issue-linkage gate file and an origin remote, then drives the hook
# with synthetic PreToolUse payloads and asserts on exit codes.
#
# Run: bash .claude/hooks/pr-linkage-mcp-gate.test.sh

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-linkage-mcp-gate.sh"
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/.github/workflows"
: >"$FIXTURE/.github/workflows/pr-issue-linkage.yml"
git -C "$FIXTURE" init -q
git -C "$FIXTURE" remote add origin https://github.com/melodic-software/claude-code-plugins.git

# Second fixture WITHOUT the gate file, for the no-policy case.
NOGATE=$(mktemp -d)
# Third fixture WITH the gate file but NO origin remote: the target repo is
# undeterminable, so even a bad body must allow.
NOORIGIN=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$NOGATE" "$NOORIGIN"' EXIT
git -C "$NOGATE" init -q
mkdir -p "$NOORIGIN/.github/workflows"
: >"$NOORIGIN/.github/workflows/pr-issue-linkage.yml"
git -C "$NOORIGIN" init -q

PASS=0
FAIL=0

# run <expected-exit> <name> <project-dir> <payload-json>
run() {
  local expected="$1" name="$2" dir="$3" payload="$4" rc=0
  CLAUDE_PROJECT_DIR="$dir" bash "$HOOK" <<<"$payload" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (expected exit $expected, got $rc)" >&2
  fi
}

# payload <tool> <owner> <repo> [body-json-string-or-omitted]
payload() {
  local tool="$1" owner="$2" repo="$3"
  if (($# >= 4)); then
    jq -cn --arg t "$tool" --arg o "$owner" --arg r "$repo" --arg b "$4" \
      '{tool_name:$t, tool_input:{owner:$o, repo:$r, title:"t", body:$b}}'
  else
    jq -cn --arg t "$tool" --arg o "$owner" --arg r "$repo" \
      '{tool_name:$t, tool_input:{owner:$o, repo:$r, title:"t"}}'
  fi
}

CREATE=mcp__github__create_pull_request
UPDATE=mcp__github__update_pull_request
OWNER=melodic-software
REPO=claude-code-plugins

GOOD=$'Closes #12\n\n## Summary\n\nx\n\n## Related\n\n- N/A'
NO_RELATED=$'Closes #12\n\n## Summary\n\nx'
EMPTY_RELATED=$'Closes #12\n\n## Related\n'
NO_KEYWORD=$'## Summary\n\nx\n\n## Related\n\n- N/A'
OPTOUT=$'No linked issue\n\n## Related\n\n- N/A'
COMMENTED=$'<!-- Closes #12 -->\n\n## Summary\n\nx\n\n<!-- ## Related\n- N/A -->'
BARE_HASH=$'Closes #\n\n## Related\n\n- N/A'
DEEP_HEADING=$'Fixes #7\n\n## Related\n\n### sub\n\ncontent'
CROSS_REPO=$'Resolves other/repo#9\n\n## Related\n\n- N/A'

run 0 "valid body passes" "$FIXTURE" "$(payload $CREATE $OWNER $REPO "$GOOD")"
run 2 "missing Related blocks" "$FIXTURE" "$(payload $CREATE $OWNER $REPO "$NO_RELATED")"
run 2 "empty Related blocks" "$FIXTURE" "$(payload $CREATE $OWNER $REPO "$EMPTY_RELATED")"
run 2 "missing keyword blocks" "$FIXTURE" "$(payload $CREATE $OWNER $REPO "$NO_KEYWORD")"
run 0 "No linked issue opt-out passes" "$FIXTURE" "$(payload $CREATE $OWNER $REPO "$OPTOUT")"
run 2 "markers only inside HTML comments block" "$FIXTURE" "$(payload $CREATE $OWNER $REPO "$COMMENTED")"
run 2 "bare 'Closes #' with no number blocks" "$FIXTURE" "$(payload $CREATE $OWNER $REPO "$BARE_HASH")"
run 0 "deeper heading is Related content" "$FIXTURE" "$(payload $CREATE $OWNER $REPO "$DEEP_HEADING")"
run 0 "owner/repo#N keyword form passes" "$FIXTURE" "$(payload $CREATE $OWNER $REPO "$CROSS_REPO")"
run 2 "create with no body field blocks (empty body)" "$FIXTURE" "$(payload $CREATE $OWNER $REPO)"
run 0 "update with no body field passes" "$FIXTURE" "$(payload $UPDATE $OWNER $REPO)"
run 2 "update with bad body blocks" "$FIXTURE" "$(payload $UPDATE $OWNER $REPO "$NO_RELATED")"
run 0 "different target repo is out of scope" "$FIXTURE" "$(payload $CREATE other-org other-repo "$NO_RELATED")"
run 0 "repo without the gate file never blocks" "$NOGATE" "$(payload $CREATE $OWNER $REPO "$NO_RELATED")"
run 0 "gated repo with no origin remote allows (undeterminable target)" "$NOORIGIN" "$(payload $CREATE $OWNER $REPO "$NO_RELATED")"
run 0 "unrelated tool passes" "$FIXTURE" "$(payload mcp__github__get_me $OWNER $REPO "$NO_RELATED")"
run 0 "empty stdin allows" "$FIXTURE" ""

echo "pass=$PASS fail=$FAIL"
((FAIL == 0))
