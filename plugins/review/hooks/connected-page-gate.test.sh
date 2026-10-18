#!/usr/bin/env bash
# Contract test for the connected-page Artifact guard.
#
# Contract: a PreToolUse Artifact call whose `file_path`, or any HTML entry in `files`,
# holds a content security policy with a loopback connect-src gets permissionDecision
# "deny". Pages come from the real digest builder. Everything else gets no output and
# exit 0: a page built without --connect, a call with no file, an unreadable path, a
# non-HTML asset, another tool, garbage input, and the guard switched off.
#
# Self-contained: defines its own assertion helpers; installed plugins are cache-isolated.
# test-scope: plugins/review/hooks/hooks.json

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/connected-page-gate.mjs"
BUILDER="$SCRIPT_DIR/../skills/explain-change/scripts/build-digest.mjs"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
assert_denies() {
  if grep -q '"permissionDecision":"deny"' <<<"$1" && grep -q 'connected page' <<<"$1"; then
    ok "$2"
  else
    fail "$2 - no deny in output: $1"
  fi
}
assert_silent() {
  if [[ -z "$1" ]]; then
    ok "$2"
  else
    fail "$2 - unexpected output: $1"
  fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

DATA='{"title":"t","files":[{"path":"a.js","status":"modified","note":"n","hunks":[]}]}'
ORIGIN="http://127.0.0.1:8765"

# A data dir shaped like the one view-bridge ensure-running leaves: private, with its session file.
BRIDGE="$WORK/bridge"
mkdir -m 700 "$BRIDGE"
printf '{"port":8765,"pid":1}' >"$BRIDGE/.view-session.json"
CONNECTED="$(printf '%s' "$DATA" | node "$BUILDER" --connect "$ORIGIN" --dir "$BRIDGE")"
PLAIN="$(printf '%s' "$DATA" | TMPDIR="$WORK" node "$BUILDER")"
if [[ ! -f "$CONNECTED" || ! -f "$PLAIN" ]]; then
  fail "the digest builder did not write both pages: connected=$CONNECTED plain=$PLAIN"
  exit 1
fi
printf 'asset' >"$WORK/logo.png"
printf 'connect-src http://127.0.0.1:1' >"$WORK/notes.txt"

# run <json tool_input> [tool_name] [env KEY=VALUE] - prints hook stdout
run() {
  local payload
  payload=$(printf '{"tool_name":"%s","cwd":"%s","tool_input":%s}' "${2:-Artifact}" "$WORK" "$1")
  if [[ -n "${3:-}" ]]; then
    env "$3" node "$HOOK" <<<"$payload"
  else
    node "$HOOK" <<<"$payload"
  fi
}

assert_denies "$(run "{\"action\":\"create\",\"file_path\":\"$CONNECTED\"}")" \
  "a page built with --connect is denied"
assert_silent "$(run "{\"action\":\"create\",\"file_path\":\"$PLAIN\"}")" \
  "the same data built without --connect is allowed"
assert_silent "$(run '{"action":"list"}')" \
  "a call with no file_path is allowed"
assert_silent "$(run "{\"action\":\"create\",\"file_path\":\"$WORK/missing.html\"}")" \
  "an unreadable path is allowed"
assert_denies "$(run "{\"action\":\"create\",\"file_path\":\"$PLAIN\",\"files\":[\"$WORK/logo.png\",\"$CONNECTED\"]}")" \
  "a connected page passed under files is denied"
assert_denies "$(run "{\"action\":\"create\",\"files\":[{\"file_path\":\"$CONNECTED\"}]}")" \
  "a connected page passed as a files object is denied"
assert_silent "$(run "{\"action\":\"create\",\"file_path\":\"$CONNECTED\"}" Artifact CLAUDE_PLUGIN_OPTION_CONNECTED_PAGE_GUARD_ENABLED=false)" \
  "the guard switched off allows a connected page"
assert_silent "$(run "{\"file_path\":\"$WORK/logo.png\"}")" \
  "a non-HTML asset is allowed"
assert_silent "$(run "{\"file_path\":\"$WORK/notes.txt\"}")" \
  "a text file naming a loopback connect-src is allowed"
assert_silent "$(run "{\"file_path\":\"$CONNECTED\"}" Write)" \
  "another tool is allowed"
assert_silent "$(printf 'not json' | node "$HOOK")" \
  "a malformed payload is allowed with no output"

# A relative path resolves against the payload cwd.
cp "$CONNECTED" "$WORK/rel.html"
assert_denies "$(run '{"file_path":"rel.html"}')" \
  "a relative path resolves against cwd"

echo "$PASS passed, $FAIL failed"
exit "$((FAIL > 0))"
