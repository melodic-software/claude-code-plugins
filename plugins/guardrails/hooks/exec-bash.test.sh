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
grep -E -q '^bash=(/bin/bash|/usr/bin/bash)$' <<<"$got" || fail "bash was not a real path: $got"

# --- usage -------------------------------------------------------------------
rc=0
err=$(node "$ENTRY" 2>&1 >/dev/null) || rc=$?
[[ "$rc" -eq 1 ]] || fail "missing script should exit 1 (got $rc)"
grep -q 'usage:' <<<"$err" || fail "missing script should name usage: $err"

# --- Windows resolver: Git Bash, never the WSL relay -------------------------
node "$HOOK_DIR/exec-bash.resolver.test.mjs" || fail "Windows resolver rejected Git Bash or accepted the relay"

# --- hooks.json: every row is node exec form --------------------------------
rows=$(jq -c '.hooks[][] | .hooks[]' "$HOOKS_JSON")
dispatcher=0
workflow=0
while IFS= read -r row; do
  cmd=$(jq -r '.command' <<<"$row")
  [[ "$cmd" == "node" ]] || fail "exec-form command is $cmd, not node"
  jq -e '.args' <<<"$row" >/dev/null || fail "row has no args: $cmd"
  first=$(jq -r '.args[0]' <<<"$row")
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
    [[ "$second" == *"/hooks/run-guards.sh" ]] || fail "args[1] is not run-guards.sh: $second"
    dispatcher=$((dispatcher + 1))
  fi
done <<<"$rows"
[[ "$dispatcher" -ge 8 ]] || fail "expected the dispatcher rows, found $dispatcher"
[[ "$workflow" -eq 1 ]] || fail "expected one workflow row, found $workflow"

echo "exec-bash: stdin, exit 2, Git Bash resolution, and hooks.json shape passed ($dispatcher dispatcher rows)."
