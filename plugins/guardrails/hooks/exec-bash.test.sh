#!/usr/bin/env bash
# exec-bash.mjs is the exec-form entry for run-guards.sh: command is node,
# this file is args[0], and bash is a child. Bare bash is not the hook command.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRY="$HOOK_DIR/exec-bash.mjs"
HOOKS_JSON="$HOOK_DIR/hooks.json"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/exec-bash-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required" >&2
  exit 1
fi

# --- stdin, argv, and a blocking exit code pass through ----------------------
record="$TEST_TMPDIR/record.txt"
script="$TEST_TMPDIR/record.sh"
cat >"$script" <<'EOF'
#!/bin/bash
outfile=$1
token=$2
printf 'bash=%s\n' "$BASH" >"$outfile"
printf 'token=%s\n' "$token" >>"$outfile"
cat >>"$outfile"
exit 2
EOF
chmod +x "$script"

payload='{"probe":"dispatcher"}'
rc=0
printf '%s' "$payload" | node "$ENTRY" "$script" "$record" "kept-arg" >/dev/null || rc=$?
[[ "$rc" -eq 2 ]] || fail "exit 2 did not pass through (got $rc)"
got=$(cat "$record")
grep -q 'token=kept-arg' <<<"$got" || fail "script arg missing: $got"
grep -q "$payload" <<<"$got" || fail "stdin missing: $got"
# The launcher takes the first bash on PATH (a Homebrew bash included), else /bin/bash or /usr/bin/bash.
grep -F -x -q -e "bash=$(command -v bash)" -e 'bash=/bin/bash' -e 'bash=/usr/bin/bash' <<<"$got" ||
  fail "bash was not the PATH bash or a fallback path: $got"

# --- usage -------------------------------------------------------------------
rc=0
err=$(node "$ENTRY" 2>&1 >/dev/null) || rc=$?
[[ "$rc" -eq 1 ]] || fail "missing script should exit 1 (got $rc)"
grep -q 'usage:' <<<"$err" || fail "missing script should name usage: $err"

# --- Windows resolver: Git Bash, never the WSL relay -------------------------
node "$HOOK_DIR/exec-bash.resolver.test.mjs" || fail "Windows resolver rejected Git Bash or accepted the relay"

# --- hooks.json: every row except SessionStart is node exec form --------------------------------
# check-bash-file-changes.mjs is the one row node runs directly, with no bash:
# a snapshot before every Bash or PowerShell call and a check after it.
# Prints why a row is routed wrongly, or nothing. Rows carry _event and _matcher.
route_problem() { # <row>
  local row=$1 first event want
  first=$(jq -r '.args[0]' <<<"$row")
  if [[ "$first" == *"/hooks/check-bash-file-changes.mjs" ]]; then
    event=$(jq -r '._event' <<<"$row")
    case "$event" in
      PreToolUse) want=snapshot ;;
      PostToolUse | PostToolUseFailure) want=check ;;
      *)
        echo "native row on unexpected event $event"
        return
        ;;
    esac
    # Exactly [entry, mode]: no --skip-* or other launcher flag.
    if ! jq -e --arg w "$want" '.args == [.args[0], $w]' <<<"$row" >/dev/null; then
      echo "native $event row args are not [entry, $want]: $(jq -c '.args' <<<"$row")"
    elif ! jq -e 'has("shell") | not' <<<"$row" >/dev/null; then
      echo "native row sets shell"
    elif ! jq -e '._matcher == "Bash|PowerShell"' <<<"$row" >/dev/null; then
      echo "native row matcher is $(jq -r '._matcher' <<<"$row"), not Bash|PowerShell"
    fi
  elif [[ "$first" != *"/hooks/exec-bash.mjs" ]]; then
    echo "args[0] is not exec-bash.mjs: $first"
  fi
}

native_row() { # <event> <matcher> <args json> [extra json] -> row as route_problem reads it
  local extra=${4:-'{}'}
  jq -cn --arg e "$1" --arg m "$2" --argjson a "$3" --argjson x "$extra" \
    '{type: "command", command: "node", args: $a, _event: $e, _matcher: $m} + $x'
}
entry=/plugin/hooks/check-bash-file-changes.mjs
[[ -z "$(route_problem "$(native_row PreToolUse 'Bash|PowerShell' "[\"$entry\",\"snapshot\"]")")" ]] ||
  fail "a well-formed native snapshot row was rejected"
for bad in \
  "$(native_row PreToolUse 'Bash|PowerShell' '["/plugin/hooks/other.mjs","snapshot"]')" \
  "$(native_row PreToolUse 'Bash|PowerShell' "[\"$entry\",\"check\"]")" \
  "$(native_row PostToolUse 'Bash|PowerShell' "[\"$entry\",\"snapshot\"]")" \
  "$(native_row PostToolUse 'Bash|PowerShell' "[\"$entry\",\"--skip-if-all-false\",\"X\",\"check\"]")" \
  "$(native_row PostToolUse 'Bash|PowerShell' "[\"$entry\",\"check\"]" '{"shell":"bash"}')" \
  "$(native_row PostToolUseFailure 'Bash' "[\"$entry\",\"check\"]")"; do
  [[ -n "$(route_problem "$bad")" ]] || fail "a misrouted row was accepted: $bad"
done

rows=$(jq -c '.hooks | del(.SessionStart) | to_entries[] | .key as $e | .value[] | .matcher as $m
  | .hooks[] | . + {_event: $e, _matcher: $m}' "$HOOKS_JSON")
dispatcher=0
workflow=0
native=0
while IFS= read -r row; do
  cmd=$(jq -r '.command' <<<"$row")
  [[ "$cmd" == "node" ]] || fail "exec-form command is $cmd, not node"
  jq -e '.args' <<<"$row" >/dev/null || fail "row has no args: $cmd"
  problem=$(route_problem "$row")
  [[ -z "$problem" ]] || fail "$problem"
  if [[ "$(jq -r '.args[0]' <<<"$row")" == *"/hooks/check-bash-file-changes.mjs" ]]; then
    native=$((native + 1))
    continue
  fi
  jq -e 'has("shell") | not' <<<"$row" >/dev/null || fail "row still sets shell"
  if jq -e '(.args | index("--require-true")) != null' <<<"$row" >/dev/null; then
    second=$(jq -r '.args[1]' <<<"$row")
    script=$(jq -r '.args[3]' <<<"$row")
    [[ "$second" == "--require-true" ]] || fail "workflow gate flag is $second"
    [[ "$script" == *"workflow-resilience-check.sh" ]] || fail "gated row is not the workflow checker: $script"
    workflow=$((workflow + 1))
  else
    second=$(jq -r '.args[1]' <<<"$row")
    # The verify rows skip bash when all three verifiers are switched off.
    if [[ "$second" == "--skip-if-all-false" ]]; then
      names=$(jq -r '.args[2]' <<<"$row")
      [[ "$names" == "CLI_FLAG_VERIFY_ENABLED,SKILL_REFERENCE_VERIFY_ENABLED,STALE_PATH_VERIFY_ENABLED" ]] ||
        fail "verify gate names $names, not the three verifier switches"
      second=$(jq -r '.args[3]' <<<"$row")
    fi
    [[ "$second" == *"/hooks/run-guards.sh" ]] || fail "args[1] is not run-guards.sh: $second"
    dispatcher=$((dispatcher + 1))
  fi
done <<<"$rows"
[[ "$dispatcher" -ge 8 ]] || fail "expected the dispatcher rows, found $dispatcher"
[[ "$workflow" -eq 1 ]] || fail "expected one workflow row, found $workflow"
[[ "$native" -eq 3 ]] || fail "expected the snapshot and two check rows of check-bash-file-changes, found $native"

# --- no launcher skip flag on a blocking row ----------------------------------
# A --skip-* launcher flag decides in node, before any guard runs, that a row
# has nothing to do. On a PreToolUse row, or a row that runs a block-* guard,
# that would let a launcher edit switch a blocking guard off.
skips_on_blocking() { # <hooks.json> -> one line per offending row
  jq -r '.hooks | to_entries[] | .key as $event | .value[] | .hooks[]
    | select(.args != null)
    | select(any(.args[]; startswith("--skip-")))
    | select($event == "PreToolUse" or any(.args[]; test("(^|/)block-[^/]*\\.sh$")))
    | "\($event): \(.args | join(" "))"' "$1"
}
offenders=$(skips_on_blocking "$HOOKS_JSON") || fail "could not read $HOOKS_JSON"
[[ -z "$offenders" ]] || fail "a blocking row carries a launcher skip flag: $offenders"

bad_json="$TEST_TMPDIR/blocking-skip.json"
cat >"$bad_json" <<'EOF'
{"hooks": {
  "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "node",
    "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "--skip-if-all-false", "BLOCK_NO_VERIFY_ENABLED",
      "${CLAUDE_PLUGIN_ROOT}/hooks/run-guards.sh", "block-no-verify.sh"]}]}],
  "PostToolUse": [{"matcher": "Write|Edit", "hooks": [
    {"type": "command", "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "--skip-unless-stdin-contains", "x",
        "${CLAUDE_PLUGIN_ROOT}/hooks/run-guards.sh", "block-credential-read.sh"]},
    {"type": "command", "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "--skip-if-all-false", "CLI_FLAG_VERIFY_ENABLED",
        "${CLAUDE_PLUGIN_ROOT}/hooks/run-guards.sh", "cli-flag-verify.sh"]}]}]
}}
EOF
caught=$(skips_on_blocking "$bad_json") || fail "could not read the blocking-skip fixture"
[[ "$(grep -c . <<<"$caught")" -eq 2 ]] || fail "expected 2 blocking rows with a skip flag, got: $caught"
grep -q '^PreToolUse: .*block-no-verify\.sh$' <<<"$caught" || fail "PreToolUse skip row not caught: $caught"
grep -q '^PostToolUse: .*block-credential-read\.sh$' <<<"$caught" || fail "block-* skip row not caught: $caught"
grep -q 'cli-flag-verify' <<<"$caught" && fail "an advisory verify row was flagged: $caught"

# --- SessionStart node notice: shell form, needs no node ---------------------
# The row's behavior, with and without node and under PowerShell, is run by
# scripts/node-notice-rows.test.sh; this pins that guardrails keeps it shell form.
notice=$(jq -c '.hooks.SessionStart[].hooks[]' "$HOOKS_JSON")
[[ "$(jq -s 'length' <<<"$notice")" -eq 1 ]] || fail "expected one SessionStart row"
jq -e '.type == "command" and (has("args") | not) and (.command | startswith("sh ") and contains("prerequisites.sh\" node-notice /guardrails:check"))' \
  <<<"$notice" >/dev/null || fail "SessionStart row is not the shell-form node notice: $notice"

echo "exec-bash: stdin, exit 2, Git Bash resolution, and hooks.json shape passed ($dispatcher dispatcher rows)."
