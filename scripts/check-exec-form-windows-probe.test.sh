#!/usr/bin/env bash
# Unit tests for check-exec-form-windows-probe.sh. Each scenario is a throwaway
# plugins/ tree; the script cds to its own repo root and scans that tree.
# shellcheck disable=SC2016
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-exec-form-windows-probe.sh"
GATE="$SELF_DIR/check-hook-exec-form.sh"
READER="$SELF_DIR/check-hook-exec-form-frontmatter.py"
REQUIREMENTS="$SELF_DIR/../.github/requirements-ci.txt"
LAUNCHER="$SELF_DIR/../lib/exec-bash.mjs"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

f=""

new_fixture() {
  fixture_tree::build "$1" --sut "$SCRIPT" --sut "$GATE" --sut "$READER" --plugins || return 1
  mkdir -p "${!1}/.github" "${!1}/lib"
  cp "$REQUIREMENTS" "${!1}/.github/requirements-ci.txt"
  cp "$LAUNCHER" "${!1}/lib/exec-bash.mjs"
}

plugin_file() {
  local fixture="$1" plugin="$2" rel="$3" content="$4"
  mkdir -p "$fixture/plugins/$plugin/$(dirname "$rel")"
  printf '%s\n' "$content" >"$fixture/plugins/$plugin/$rel"
}

run_check() (
  cd "$1" && bash scripts/check-exec-form-windows-probe.sh
)

NODE_ROW='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/hooks/x.mjs"]}]}]}}'
SHELL_ROW='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh\"","shell":"bash"}]}]}}'

assert_fail() { # <name> <output> <needle>
  local name="$1" out="$2" needle="$3"
  if grep -q "$needle" <<<"$out"; then
    ok "$name"
  else
    fail "$name: expected '$needle' in: $out"
  fi
}

# --- node exec form is a real executable spelling ---------------------------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
if out="$(run_check "$f" 2>&1)"; then
  if grep -q '1 exec-form row(s) name a real Windows executable.' <<<"$out" &&
    grep -q 'SKIP: Windows exec-form spawn probe not exercised' <<<"$out" &&
    grep -q 'does not authorize converting .sh rows' <<<"$out" &&
    grep -q 'EXEC_FORM_WINDOWS_PROBE_LIVE unset' <<<"$out"; then
    ok "node exec form passes and the non-Windows spawn skip is explicit"
  else
    fail "clean node row should name the skip and the count, got: $out"
  fi
else
  fail "node exec form should pass, got: $out"
fi
rm -rf "$f"

# --- shell form is outside this probe ---------------------------------------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$SHELL_ROW"
if out="$(run_check "$f" 2>&1)"; then
  if grep -q '0 exec-form row(s) name a real Windows executable.' <<<"$out"; then
    ok "shell form is not an exec-form row"
  else
    fail "shell form should count zero exec-form rows, got: $out"
  fi
else
  fail "shell form must pass, got: $out"
fi
rm -rf "$f"

# --- a .sh path as command is the shebang failure mode ----------------------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh","args":["a"]}]}]}'
if out="$(run_check "$f" 2>&1)"; then
  fail "a .sh command in exec form should fail, got: $out"
else
  assert_fail "script path as command fails" "$out" 'EXEC-FORM WINDOWS: plugins/alpha/hooks/hooks.json:.*is not a real Windows executable'
fi
rm -rf "$f"

# --- .cmd / .bat shims are not executables ----------------------------------
for shim in hook.cmd hook.bat; do
  new_fixture f
  plugin_file "$f" alpha hooks/hooks.json "{\"hooks\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"\${CLAUDE_PLUGIN_ROOT}/node_modules/.bin/${shim}\",\"args\":[]}]}]}"
  if run_check "$f" >/dev/null 2>&1; then
    fail "$shim as command should fail"
  else
    ok "$shim as command fails"
  fi
  rm -rf "$f"
done

# --- bare bash is not a portable exec-form command --------------------------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"bash","args":["x.sh"]}]}]}'
if out="$(run_check "$f" 2>&1)"; then
  fail "bare bash exec form should fail, got: $out"
else
  assert_fail "bare bash fails" "$out" 'exec-form command "bash" is not a real Windows executable'
fi
rm -rf "$f"

# --- an absolute bash.exe path is a shell image, not a fleet row ------------
new_fixture f
# portability-ok: Windows path fixture; \b is the bin and bash segments, not a GNU grep word boundary
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"C:\\\\Program Files\\\\Git\\\\usr\\\\bin\\\\bash.exe","args":["x.sh"]}]}]}'
if out="$(run_check "$f" 2>&1)"; then
  fail "bash.exe path should fail, got: $out"
else
  assert_fail "bash.exe path fails" "$out" 'names a shell image'
fi
rm -rf "$f"

# --- node.exe path and the documented bare .exe names pass ------------------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"C:\\\\Program Files\\\\nodejs\\\\node.exe","args":["x.mjs"]}]}]}'
if run_check "$f" >/dev/null 2>&1; then
  ok "absolute node.exe path passes"
else
  fail "absolute node.exe path should pass"
fi
rm -rf "$f"

# --- a bare name passes only when the gate's allowlist carries it -----------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"node","args":[]}]}]}'
if run_check "$f" >/dev/null 2>&1; then
  ok "bare node passes"
else
  fail "bare node should pass"
fi
rm -rf "$f"

for name in node.exe powershell.exe pwsh.exe; do
  new_fixture f
  plugin_file "$f" alpha hooks/hooks.json "{\"hooks\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$name\",\"args\":[]}]}]}"
  if out="$(run_check "$f" 2>&1)"; then
    fail "bare $name is not on the allowlist and should fail, got: $out"
  else
    assert_fail "bare $name fails" "$out" "exec-form command \"$name\" is not a real Windows executable"
  fi
  rm -rf "$f"
done

# --- the gate and the probe read one allowlist ------------------------------
# Same fixture, same bare name, both scripts: they must agree, and each must
# have judged the row (exit 0 or 1), not stopped on the environment (exit 2).
for name in node node.exe bash sh python3 pwsh powershell.exe; do
  new_fixture f
  plugin_file "$f" alpha hooks/hooks.json "{\"hooks\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$name\",\"args\":[]}]}]}"
  gate_rc=0
  probe_rc=0
  (cd "$f" && bash scripts/check-hook-exec-form.sh) >/dev/null 2>&1 || gate_rc=$?
  run_check "$f" >/dev/null 2>&1 || probe_rc=$?
  if [[ "$gate_rc" == "$probe_rc" && "$gate_rc" -le 1 ]]; then
    ok "gate and probe agree on bare $name (exit $gate_rc)"
  else
    fail "gate and probe disagree on bare $name (gate exit $gate_rc, probe exit $probe_rc)"
  fi
  rm -rf "$f"
done

# --- a probe that cannot read the gate's allowlist stops at exit 2 ----------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
rm "$f/scripts/check-hook-exec-form.sh"
rc=0
out="$(run_check "$f" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'cannot read exactly one EXEC_NAME_ALLOWLIST' <<<"$out"; then
  ok "a missing gate file exits 2"
else
  fail "a missing gate file should exit 2 (rc=$rc): $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
printf '%s\n' 'EXEC_NAME_ALLOWLIST=(node)' 'EXEC_NAME_ALLOWLIST=(node bash)' >"$f/scripts/check-hook-exec-form.sh"
rc=0
out="$(run_check "$f" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'cannot read exactly one EXEC_NAME_ALLOWLIST' <<<"$out"; then
  ok "two allowlist lines in the gate exit 2"
else
  fail "two allowlist lines should exit 2 (rc=$rc): $out"
fi
rm -rf "$f"

# --- args must be an array --------------------------------------------------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"node","args":"x.mjs"}]}]}'
if out="$(run_check "$f" 2>&1)"; then
  fail "a string args value should fail, got: $out"
else
  assert_fail "non-array args fails" "$out" 'not an array'
fi
rm -rf "$f"

# --- frontmatter exec form with a script command fails ----------------------
new_fixture f
mkdir -p "$f/plugins/alpha/skills/demo"
cat >"$f/plugins/alpha/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: demo
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/hooks/x.sh"
          args: ["a"]
---
body
EOF
if out="$(run_check "$f" 2>&1)"; then
  fail "frontmatter .sh exec form should fail, got: $out"
else
  assert_fail "frontmatter script command fails" "$out" 'EXEC-FORM WINDOWS: plugins/alpha/skills/demo/SKILL.md:'
fi
rm -rf "$f"

# --- unreadable hooks.json is a finding, not a pass -------------------------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{not json'
if out="$(run_check "$f" 2>&1)"; then
  fail "unreadable hooks.json should fail, got: $out"
else
  assert_fail "unreadable hooks.json fails" "$out" 'UNREADABLE HOOK CONFIG:'
fi
rm -rf "$f"

# --- forced spawn delivers the args array when node is present --------------
if command -v node >/dev/null 2>&1; then
  new_fixture f
  plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
  if out="$(cd "$f" && EXEC_FORM_WINDOWS_PROBE_FORCE=1 bash scripts/check-exec-form-windows-probe.sh 2>&1)"; then
    if grep -q 'spawn probe delivered the args array to node' <<<"$out"; then
      ok "forced spawn delivers the sentinel arg to node"
    else
      fail "forced spawn should report delivery, got: $out"
    fi
    if grep -q 'launcher probe delivered argv, stdin, exit 2 and a backslash CLAUDE_PLUGIN_ROOT' <<<"$out"; then
      ok "the forced launcher half round-trips argv, stdin, exit 2 and a backslash root"
    else
      fail "forced launcher half should report delivery, got: $out"
    fi
  else
    fail "forced spawn should pass, got: $out"
  fi
  rm -rf "$f"

  new_fixture f
  plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
  rc=0
  out="$(cd "$f" && EXEC_FORM_WINDOWS_PROBE_FORCE=1 EXEC_FORM_WINDOWS_PROBE_SIMULATE_DROP=1 bash scripts/check-exec-form-windows-probe.sh 2>&1)" || rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'ARGS-DROP:' <<<"$out" && grep -q 'Fleet sweep stopped' <<<"$out"; then
    ok "a simulated args-drop stops the fleet sweep"
  else
    fail "simulated args-drop should exit 1 with ARGS-DROP (rc=$rc): $out"
  fi
  rm -rf "$f"

  new_fixture f
  plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
  rc=0
  out="$(cd "$f" && EXEC_FORM_WINDOWS_PROBE_FORCE=1 EXEC_FORM_WINDOWS_PROBE_SIMULATE_LAUNCHER_DROP=1 bash scripts/check-exec-form-windows-probe.sh 2>&1)" || rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'LAUNCHER-PROBE: the script.s own exit 2 came back as exit 0' <<<"$out"; then
    ok "a simulated launcher drop fails the launcher half"
  else
    fail "simulated launcher drop should exit 1 with LAUNCHER-PROBE (rc=$rc): $out"
  fi
  rm -rf "$f"

  # A launcher that drops stdin and swallows the script's exit code.
  new_fixture f
  plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
  cat >"$f/lib/exec-bash.mjs" <<'EOF'
import { spawnSync } from "node:child_process";
const [script, ...args] = process.argv.slice(2);
spawnSync("bash", [script, ...args], { stdio: ["ignore", "inherit", "inherit"] });
EOF
  rc=0
  out="$(cd "$f" && EXEC_FORM_WINDOWS_PROBE_FORCE=1 bash scripts/check-exec-form-windows-probe.sh 2>&1)" || rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'LAUNCHER-PROBE: the script read 0 stdin bytes' <<<"$out" &&
    grep -q 'LAUNCHER-PROBE: the script.s own exit 2 came back as exit 0' <<<"$out"; then
    ok "a launcher that drops stdin and the exit code fails the launcher half"
  else
    fail "a stdin-dropping, exit-swallowing launcher should fail (rc=$rc): $out"
  fi
  rm -rf "$f"

  new_fixture f
  plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
  rm "$f/lib/exec-bash.mjs"
  rc=0
  out="$(cd "$f" && EXEC_FORM_WINDOWS_PROBE_FORCE=1 bash scripts/check-exec-form-windows-probe.sh 2>&1)" || rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'LAUNCHER-PROBE: lib/exec-bash.mjs not found' <<<"$out"; then
    ok "a forced run with no lib/exec-bash.mjs fails"
  else
    fail "a missing launcher should fail the forced run (rc=$rc): $out"
  fi
  rm -rf "$f"

  # A Windows backslash execPath still counts as node.exe. The fake answers the
  # spawn half; the launcher half needs a real node, so it gets the real one.
  new_fixture f
  plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
  winnode="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
  cat >"$winnode/node" <<'EOF'
#!/usr/bin/env bash
case "$*" in *launcher-probe.cjs*) exec "$REAL_NODE" "$@" ;; esac
payload=$(cat)
jq -n --arg payload "$payload" --args \
  '{execPath:"C:\\Program Files\\nodejs\\node.exe", argv:$ARGS.positional, stdinBytes:($payload|length)}' \
  "$@"
EOF
  chmod +x "$winnode/node"
  if out="$(cd "$f" && REAL_NODE="$(command -v node)" PATH="$winnode:$PATH" EXEC_FORM_WINDOWS_PROBE_FORCE=1 bash scripts/check-exec-form-windows-probe.sh 2>&1)"; then
    if grep -q 'spawn probe delivered the args array to node.exe' <<<"$out"; then
      ok "a backslash process.execPath counts as node.exe"
    else
      fail "backslash execPath should count as node.exe, got: $out"
    fi
  else
    fail "backslash execPath should pass, got: $out"
  fi
  rm -rf "$f" "$winnode"
else
  echo "SKIP: node is not on PATH; spawn-delivery cases not exercised" >&2
fi

# --- a required spawn with node hidden fails closed -------------------------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
hidden="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
# Keep jq and python (and uv, the PyYAML fallback), drop node.
mkdir -p "$hidden/bin"
for tool in bash jq python3 python uv; do
  src="$(command -v "$tool" 2>/dev/null || true)"
  [[ -n "$src" ]] && ln -s "$src" "$hidden/bin/$tool"
done
rc=0
out="$(cd "$f" && PATH="$hidden/bin:/usr/bin:/bin" EXEC_FORM_WINDOWS_PROBE_FORCE=1 EXEC_FORM_WINDOWS_PROBE_REQUIRE_SPAWN=1 bash scripts/check-exec-form-windows-probe.sh 2>&1)" || rc=$?
if [[ "$rc" -eq 1 ]] && grep -q 'SPAWN-PROBE:' <<<"$out" && grep -q 'cannot clear a fleet sweep' <<<"$out"; then
  ok "a required spawn with no node.exe fails closed"
else
  fail "required spawn without node should fail closed (rc=$rc): $out"
fi
rm -rf "$f" "$hidden"

# --- live probe: healthy fake claude, dropped args, and missing claude ------
new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
bin="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
cat >"$bin/claude" <<'EOF'
#!/usr/bin/env bash
settings=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--settings" ]]; then
    settings="$2"
    shift 2
    continue
  fi
  shift
done
mapfile -t hook_args < <(jq -r '.hooks.PreToolUse[0].hooks[0].args[]' "$settings")
printf '%s' '{"session_id":"probe"}' | node "${hook_args[@]}"
EOF
chmod +x "$bin/claude"
# The fake claude needs node and jq. Prepend only the fake bin.
if out="$(cd "$f" && PATH="$bin:$PATH" EXEC_FORM_WINDOWS_PROBE_LIVE=1 EXEC_FORM_WINDOWS_PROBE_FORCE=1 bash scripts/check-exec-form-windows-probe.sh 2>&1)"; then
  if grep -q 'live probe delivered args and stdin' <<<"$out"; then
    ok "a live probe that keeps args reports delivery and converts nothing"
  else
    fail "healthy live probe should report delivery, got: $out"
  fi
else
  fail "healthy live probe should pass, got: $out"
fi
rm -rf "$f" "$bin"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
bin="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
cat >"$bin/claude" <<'EOF'
#!/usr/bin/env bash
echo 'SyntaxError: Unexpected token :' >&2
echo 'at eval_stdin' >&2
exit 1
EOF
chmod +x "$bin/claude"
rc=0
out="$(cd "$f" && PATH="$bin:$PATH" EXEC_FORM_WINDOWS_PROBE_LIVE=1 EXEC_FORM_WINDOWS_PROBE_FORCE=1 bash scripts/check-exec-form-windows-probe.sh 2>&1)" || rc=$?
if [[ "$rc" -eq 1 ]] && grep -q 'ARGS-DROP:' <<<"$out" && grep -q 'Fleet sweep stopped' <<<"$out"; then
  ok "a live probe that shows eval_stdin stops the fleet sweep"
else
  fail "eval_stdin live probe should stop the sweep (rc=$rc): $out"
fi
rm -rf "$f" "$bin"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$NODE_ROW"
hidden="$(mktemp -d "$TMP_ROOT/d.XXXXXX")/bin"
mkdir -p "$hidden"
for tool in bash jq python3 python uv node; do
  src="$(command -v "$tool" 2>/dev/null || true)"
  [[ -n "$src" ]] && ln -s "$src" "$hidden/$tool"
done
if out="$(cd "$f" && PATH="$hidden:/usr/bin:/bin" EXEC_FORM_WINDOWS_PROBE_LIVE=1 EXEC_FORM_WINDOWS_PROBE_FORCE=1 bash scripts/check-exec-form-windows-probe.sh 2>&1)"; then
  if grep -q 'claude is not on PATH' <<<"$out"; then
    ok "a live probe without claude skips fail-soft"
  else
    fail "missing claude should skip, got: $out"
  fi
else
  fail "missing claude should not fail the spelling check, got: $out"
fi
rm -rf "$f" "$(dirname "$hidden")"

test_harness::report
