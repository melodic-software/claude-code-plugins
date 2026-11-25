#!/usr/bin/env bash
# test-scope: plugins/guardrails/hooks/hooks.json
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
grep -F -x -q -e "bash=$(command -v bash)" -e 'bash=/bin/bash' -e 'bash=/usr/bin/bash' <<<"$got" ||
  fail "bash was not the PATH bash or a fallback path: $got"

rc=0
err=$(node "$ENTRY" 2>&1 >/dev/null) || rc=$?
[[ "$rc" -eq 1 ]] || fail "missing script should exit 1 (got $rc)"
grep -q 'usage:' <<<"$err" || fail "missing script should name usage: $err"

segv="$TEST_TMPDIR/segv.sh"
printf '#!/bin/bash\nkill -SEGV $$\n' >"$segv"
rc=0
err=$(node "$ENTRY" --fail-closed "$segv" 2>&1 >/dev/null) || rc=$?
[[ "$rc" -eq 2 ]] || fail "--fail-closed on a SIGSEGV child should exit 2 (got $rc)"
[[ "$(grep -c . <<<"$err")" -eq 1 ]] || fail "--fail-closed should write one stderr line: $err"
grep -q 'segv.sh' <<<"$err" || fail "--fail-closed line should name the script: $err"
grep -q 'SIGSEGV' <<<"$err" || fail "--fail-closed line should name the cause: $err"
if [[ "$(node -p process.platform)" == win32 ]]; then
  rc=$(node -e 'const r = require("node:child_process").spawnSync(process.execPath, process.argv.slice(1), { stdio: "ignore" }); console.log(r.status)' "$ENTRY" "$segv")
  [[ "$rc" -eq 2816 ]] || fail "a SIGSEGV child without --fail-closed should pass exit 2816 through on Windows (got $rc)"
else
  rc=0
  node "$ENTRY" "$segv" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 1 ]] || fail "a SIGSEGV child without --fail-closed should still exit 1 (got $rc)"
fi

for code in 0 2 3 139; do
  printf '#!/bin/bash\nexit %s\n' "$code" >"$TEST_TMPDIR/exit.sh"
  want=$code
  [[ "$code" -ne 3 && "$code" -ne 139 ]] || want=2
  rc=0
  node "$ENTRY" --fail-closed "$TEST_TMPDIR/exit.sh" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq "$want" ]] || fail "--fail-closed on exit $code should exit $want (got $rc)"
done
printf '#!/bin/bash\nexit 3\n' >"$TEST_TMPDIR/exit.sh"
rc=0
node "$ENTRY" "$TEST_TMPDIR/exit.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 3 ]] || fail "exit 3 without --fail-closed should pass through (got $rc)"

decoded=$(node --input-type=module -e '
import { pathToFileURL } from "node:url";
const { msysSignal } = await import(pathToFileURL(process.argv[2]).href);
console.log([[2816, "win32", true], [2816, "win32", false], [2816, "linux", true], [3, "win32", true],
  [0, "win32", true], [0xc0000005, "win32", true], [0xc0000100, "win32", true]]
  .map(([code, platform, failClosed]) => String(msysSignal(code, platform, failClosed))).join(" "));
' decode "$ENTRY")
[[ "$decoded" == "SIGSEGV null null null null null null" ]] || fail "msysSignal decoded wrongly: $decoded"

rc=0
CLAUDE_PLUGIN_OPTION_FC_GATE=false node "$ENTRY" --fail-closed --require-true FC_GATE "$segv" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "--fail-closed must not change a closed gate (got $rc)"

silent="$TEST_TMPDIR/silent.sh"
printf '#!/bin/bash\nexit 0\n' >"$silent"
rc=0
err=$(node "$ENTRY" --fail-closed --require-verdict "$silent" 2>&1 >/dev/null) || rc=$?
[[ "$rc" -eq 2 ]] || fail "--require-verdict on exit 0 with no marker should exit 2 (got $rc)"
[[ "$(grep -c . <<<"$err")" -eq 1 ]] || fail "--require-verdict should write one stderr line: $err"
grep -q 'silent.sh' <<<"$err" || fail "--require-verdict line should name the script: $err"
grep -q 'verdict marker' <<<"$err" || fail "--require-verdict line should name the cause: $err"
rc=0
node "$ENTRY" --require-verdict "$silent" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "--require-verdict alone on exit 0 with no marker should exit 2 (got $rc)"

marked="$TEST_TMPDIR/marked.sh"
seen_marker="$TEST_TMPDIR/marker-path.txt"
cat >"$marked" <<EOF
#!/bin/bash
printf '%s' "\$EXEC_BASH_VERDICT_FILE" >"$seen_marker"
: >"\$EXEC_BASH_VERDICT_FILE"
echo '{"systemMessage":"kept"}'
exit 0
EOF
rc=0
out=$(node "$ENTRY" --fail-closed --require-verdict "$marked" 2>/dev/null) || rc=$?
[[ "$rc" -eq 0 ]] || fail "--require-verdict on exit 0 with the marker should exit 0 (got $rc)"
[[ "$out" == '{"systemMessage":"kept"}' ]] || fail "--require-verdict should pass the script's stdout through: $out"
marker_path=$(cat "$seen_marker")
[[ -n "$marker_path" ]] || fail "--require-verdict did not hand the script a marker path"
[[ ! -e "$marker_path" && ! -e "${marker_path%/*}" ]] || fail "the marker directory outlived the launch: $marker_path"

printf '#!/bin/bash\nexit 2\n' >"$TEST_TMPDIR/exit.sh"
rc=0
node "$ENTRY" --require-verdict "$TEST_TMPDIR/exit.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "--require-verdict on exit 2 should exit 2 (got $rc)"
rc=0
err=$(node "$ENTRY" --fail-closed --require-verdict "$segv" 2>&1 >/dev/null) || rc=$?
[[ "$rc" -eq 2 ]] || fail "--require-verdict must keep the --fail-closed signal deny (got $rc)"
grep -q 'SIGSEGV' <<<"$err" || fail "--require-verdict must keep the --fail-closed signal line: $err"

cat >"$TEST_TMPDIR/novar.sh" <<'EOF'
#!/bin/bash
[[ -z "${EXEC_BASH_VERDICT_FILE+x}" ]] || exit 9
exit 0
EOF
rc=0
node "$ENTRY" --fail-closed "$TEST_TMPDIR/novar.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "a row without --require-verdict should allow exit 0 with no marker variable (got $rc)"

rc=0
CLAUDE_PLUGIN_OPTION_RV_GATE=false node "$ENTRY" --require-verdict --require-true RV_GATE "$silent" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "--require-verdict must not change a closed gate (got $rc)"

printf '#!/bin/bash\n:\n' >"$TEST_TMPDIR/rv-allow.sh"
printf '#!/bin/bash\ntrap - EXIT\nbuiltin exit 0\n' >"$TEST_TMPDIR/rv-crash.sh"
rv_payload='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
rc=0
printf '%s' "$rv_payload" | node "$ENTRY" --fail-closed --require-verdict "$HOOK_DIR/run-guards.sh" "$TEST_TMPDIR/rv-allow.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "run-guards.sh through --require-verdict should allow a clean run (got $rc)"
rc=0
printf '%s' "$rv_payload" | node "$ENTRY" --fail-closed "$HOOK_DIR/run-guards.sh" "$TEST_TMPDIR/rv-crash.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 0 ]] || fail "without --require-verdict a silent exit 0 is still an allow (got $rc)"
rc=0
printf '%s' "$rv_payload" | node "$ENTRY" --fail-closed --require-verdict "$HOOK_DIR/run-guards.sh" "$TEST_TMPDIR/rv-crash.sh" >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "a dispatcher that exits 0 with no verdict should be denied (got $rc)"

node "$HOOK_DIR/exec-bash.resolver.test.mjs" || fail "Windows resolver rejected Git Bash or accepted the relay"

rows=$(jq -c '.hooks | del(.SessionStart) | to_entries[] | .key as $e | .value[] | .matcher as $m
  | .hooks[] | . + {_event: $e, _matcher: $m}' "$HOOKS_JSON")
dispatcher=0
workflow=0
node_guards=0
while IFS= read -r row; do
  cmd=$(jq -r '.command' <<<"$row")
  [[ "$cmd" == "node" ]] || fail "exec-form command is $cmd, not node"
  jq -e '.args' <<<"$row" >/dev/null || fail "row has no args: $cmd"
  first=$(jq -r '.args[0]' <<<"$row")
  if [[ "$first" == *"/hooks/settings-write-ask.mjs" || "$first" == *"/hooks/connected-page-gate.mjs" ]]; then
    jq -e '._event == "PreToolUse" and (.args | length) == 1 and (has("shell") | not)' <<<"$row" >/dev/null ||
      fail "node guard row is not a bare PreToolUse node row: $first"
    node_guards=$((node_guards + 1))
    continue
  fi
  [[ "$first" == *"/hooks/exec-bash.mjs" ]] || fail "args[0] is not exec-bash.mjs: $first"
  jq -e 'has("shell") | not' <<<"$row" >/dev/null || fail "row still sets shell"
  if jq -e '(.args | index("--require-true")) != null' <<<"$row" >/dev/null; then
    second=$(jq -r '.args[1]' <<<"$row")
    script=$(jq -r '.args[3]' <<<"$row")
    [[ "$second" == "--require-true" ]] || fail "workflow gate flag is $second"
    [[ "$script" == *"workflow-resilience-check.sh" ]] || fail "gated row is not the workflow checker: $script"
    workflow=$((workflow + 1))
  else
    second=$(jq -r '.args[1]' <<<"$row")
    [[ "$second" == "--fail-closed" ]] || fail "guard row does not pass --fail-closed: $second"
    third=$(jq -r '.args[2]' <<<"$row")
    [[ "$third" == "--require-verdict" ]] || fail "guard row does not pass --require-verdict: $third"
    at=3
    [[ "$(jq -r '.args[3]' <<<"$row")" == "--bps-seed" ]] && at=5
    fourth=$(jq -r ".args[$at]" <<<"$row")
    [[ "$fourth" == *"/hooks/run-guards.sh" ]] || fail "args[$at] is not run-guards.sh: $fourth"
    if ((at == 5)); then
      [[ "$(jq -r '.args[4]' <<<"$row")" == *"/hooks/hook-utils.sh" ]] || fail "--bps-seed does not name hook-utils.sh"
      [[ "$(jq -r '.args[6]' <<<"$row")" == "--bps-seeded" ]] || fail "a --bps-seed row's run-guards.sh lacks --bps-seeded"
      [[ "$(jq -r '._matcher' <<<"$row")" == "Bash|PowerShell" ]] || fail "--bps-seed on a row other than Bash|PowerShell"
    else
      jq -e '(.args | index("--bps-seeded")) == null' <<<"$row" >/dev/null || fail "--bps-seeded without --bps-seed"
    fi
    dispatcher=$((dispatcher + 1))
  fi
done <<<"$rows"
[[ "$dispatcher" -eq 6 ]] || fail "expected the six dispatcher rows, found $dispatcher"
[[ "$workflow" -eq 1 ]] || fail "expected one workflow row, found $workflow"
[[ "$node_guards" -eq 2 ]] || fail "expected the settings-write-ask and connected-page-gate node rows, found $node_guards"

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
    "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "--skip-unless-stdin-contains", "x",
      "${CLAUDE_PLUGIN_ROOT}/hooks/run-guards.sh", "block-no-verify.sh"]}]}],
  "PostToolUse": [{"matcher": "Write|Edit", "hooks": [
    {"type": "command", "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "--skip-unless-stdin-contains", "x",
        "${CLAUDE_PLUGIN_ROOT}/hooks/run-guards.sh", "block-credential-read.sh"]},
    {"type": "command", "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "--skip-unless-stdin-contains", "x",
        "${CLAUDE_PLUGIN_ROOT}/hooks/run-guards.sh", "cli-flag-verify.sh"]}]}]
}}
EOF
caught=$(skips_on_blocking "$bad_json") || fail "could not read the blocking-skip fixture"
[[ "$(grep -c . <<<"$caught")" -eq 2 ]] || fail "expected 2 blocking rows with a skip flag, got: $caught"
grep -q '^PreToolUse: .*block-no-verify\.sh$' <<<"$caught" || fail "PreToolUse skip row not caught: $caught"
grep -q '^PostToolUse: .*block-credential-read\.sh$' <<<"$caught" || fail "block-* skip row not caught: $caught"
grep -q 'cli-flag-verify' <<<"$caught" && fail "an advisory verify row was flagged: $caught"

ss_rows=$(jq -r '[.hooks.SessionStart[]?.hooks[]? | .command] | join("|")' "$HOOKS_JSON")
# shellcheck disable=SC2016  # the literal hooks.json text
ss_want='sh "${CLAUDE_PLUGIN_ROOT}/lib/node-or-skip.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs" "${CLAUDE_PLUGIN_ROOT}/hooks/cloud-shfmt.sh"; ${PPID:+exit}; powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/lib/node-or-skip.ps1" "${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs" "${CLAUDE_PLUGIN_ROOT}/hooks/cloud-shfmt.sh"'
[[ "$ss_rows" == "$ss_want" ]] ||
  fail "guardrails registers a SessionStart row other than the cloud shfmt install: [$ss_rows]"

echo "exec-bash: stdin, exit 2, --fail-closed, --require-verdict, Git Bash resolution, and hooks.json shape passed ($dispatcher dispatcher rows)."
