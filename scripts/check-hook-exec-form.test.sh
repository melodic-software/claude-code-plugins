#!/usr/bin/env bash
# Unit tests for check-hook-exec-form.sh. Builds a tiny synthetic plugins/ tree
# per scenario in a temp dir and invokes the script against it directly -- the
# script's own `cd "$(dirname "$0")/.."` makes this work unmodified: copy it to
# <fixture>/scripts/ and it scans <fixture>/plugins/.
# shellcheck disable=SC2016  # fixture bodies are literal JSON/YAML carrying ${CLAUDE_PLUGIN_ROOT}; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-hook-exec-form.sh"

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

new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/plugins"
  cp "$SCRIPT" "$dir/scripts/check-hook-exec-form.sh"
  chmod +x "$dir/scripts/check-hook-exec-form.sh"
  printf '%s' "$dir"
}

# plugin_file <fixture> <plugin> <relpath> <content>
plugin_file() {
  local fixture="$1" plugin="$2" rel="$3" content="$4"
  mkdir -p "$fixture/plugins/$plugin/$(dirname "$rel")"
  printf '%s\n' "$content" >"$fixture/plugins/$plugin/$rel"
}

run_check() (
  cd "$1" && bash scripts/check-hook-exec-form.sh
)

# The exact pre-#2570 disk-hygiene wiring: event-keyed `hooks` object, exec form
# on a bare `bash`, in BOTH the PreToolUse and the Stop entry.
PRE_2570_HOOKS='{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell",
        "hooks": [
          {
            "type": "command",
            "command": "bash",
            "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/run-python-hook.sh", "--mode", "engine-gate"],
            "timeout": 60
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/monitor.sh"] }
        ]
      }
    ]
  }
}'

# The #2570 fix: shell form. `bash` leads the command STRING, which is correct
# and must never be flagged -- `args` presence is the sole discriminator.
SHELL_FORM_HOOKS='{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh\" --mode engine-gate",
            "shell": "bash"
          }
        ]
      }
    ]
  }
}'

# Exec form done right: the interpreter is a rooted path, not a PATH lookup.
ROOTED_EXEC_HOOKS='{
  "hooks": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/bin/guard",
          "args": ["--mode", "engine-gate"]
        }
      ]
    }
  ]
}'

# --- the regression this gate exists for: pre-#2570 shape fails -------------
f="$(new_fixture)"
plugin_file "$f" disk-hygiene hooks/hooks.json "$PRE_2570_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  fail "pre-#2570 exec-form bash hooks should fail, got success: $out"
else
  if echo "$out" | grep -q 'EXEC-FORM HOOK: plugins/disk-hygiene/hooks/hooks.json:.hooks.PreToolUse\[0\].hooks\[0\]: .*"bash"' &&
    echo "$out" | grep -q 'EXEC-FORM HOOK: plugins/disk-hygiene/hooks/hooks.json:.hooks.Stop\[0\].hooks\[0\]: .*"bash"'; then
    ok "pre-#2570 shape fails, and BOTH exec-form entries are named"
  else
    fail "expected both PreToolUse and Stop entries flagged with their paths, got: $out"
  fi
fi
rm -rf "$f"

# --- the #2570 fix passes: shell form with a leading bare `bash` ------------
f="$(new_fixture)"
plugin_file "$f" disk-hygiene hooks/hooks.json "$SHELL_FORM_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  ok "shell form with a leading bare bash passes (args presence is the discriminator)"
else
  fail "shell form must not be flagged, got: $out"
fi
rm -rf "$f"

# --- exec form with a ${CLAUDE_PLUGIN_ROOT}-rooted command passes -----------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$ROOTED_EXEC_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  ok "exec form with a rooted command path passes"
else
  fail "rooted exec-form command should pass, got: $out"
fi
rm -rf "$f"

# --- exec form with an absolute Windows path passes -------------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"C:\\Program Files\\nodejs\\node.exe","args":["x.mjs"]}]}]}'
if out="$(run_check "$f" 2>&1)"; then
  ok "exec form with an absolute Windows path passes"
else
  fail "absolute Windows path should pass, got: $out"
fi
rm -rf "$f"

# --- the allowlist: `node` passes, the shimmed names do not -----------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/hooks/x.mjs"]}]}]}'
if out="$(run_check "$f" 2>&1)"; then
  ok "allowlisted bare name (node) passes"
else
  fail "node is the documented Windows exec-form spelling and must pass, got: $out"
fi
rm -rf "$f"

for name in bash sh python python3 py pwsh deno; do
  f="$(new_fixture)"
  plugin_file "$f" alpha hooks/hooks.json "{\"hooks\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$name\",\"args\":[\"x\"]}]}]}"
  if run_check "$f" >/dev/null 2>&1; then
    fail "bare exec-form command '$name' should fail"
  else
    ok "bare exec-form command '$name' fails"
  fi
  rm -rf "$f"
done

# --- allowlist contents are pinned ------------------------------------------
# Growing the allowlist must be a visible, reviewed diff that also edits this
# assertion -- never a quiet one-word change.
if grep -q '^EXEC_NAME_ALLOWLIST=(node)$' "$SCRIPT"; then
  ok "allowlist is pinned to exactly (node)"
else
  fail "EXEC_NAME_ALLOWLIST changed; review the admission criterion and update this test deliberately"
fi

# --- an empty args array is still exec form ---------------------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"bash","args":[]}]}]}'
if run_check "$f" >/dev/null 2>&1; then
  fail "an empty args array is still exec form and must fail"
else
  ok "empty args array is still exec form"
fi
rm -rf "$f"

# --- a matcher entry is not itself a hook object ----------------------------
# The outer object carries `matcher` and a nested `hooks` list but no command;
# only the inner dirty entry may be flagged, and the clean sibling must not be.
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/bin/ok","args":["--x"]},
  {"type":"command","command":"python3","args":["y.py"]}]}]}'
if out="$(run_check "$f" 2>&1)"; then
  fail "the dirty sibling should fail, got success: $out"
else
  if [[ "$(echo "$out" | grep -c 'EXEC-FORM HOOK:')" == "1" ]] &&
    echo "$out" | grep -q 'hooks\[1\]: .*"python3"'; then
    ok "only the dirty sibling in a matcher entry is flagged"
  else
    fail "expected exactly one flag naming hooks[1]/python3, got: $out"
  fi
fi
rm -rf "$f"

# --- manifest string-path hook config is scanned ----------------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":"./config/extra-hooks.json"}'
plugin_file "$f" alpha config/extra-hooks.json "$PRE_2570_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  fail "manifest-pointed hook file should fail, got success: $out"
else
  if echo "$out" | grep -q 'EXEC-FORM HOOK: plugins/alpha/config/extra-hooks.json:'; then
    ok "manifest string-path hook config is scanned"
  else
    fail "expected flag on the manifest-pointed file, got: $out"
  fi
fi
rm -rf "$f"

# --- manifest array of hook paths: the offending element fails --------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":["./hooks/hooks.json","./config/extra-hooks.json"]}'
plugin_file "$f" alpha hooks/hooks.json "$SHELL_FORM_HOOKS"
plugin_file "$f" alpha config/extra-hooks.json "$PRE_2570_HOOKS"
if run_check "$f" >/dev/null 2>&1; then
  fail "a bare exec-form command in one manifest array path should fail"
else
  ok "manifest array hook config fails on the offending element"
fi
rm -rf "$f"

# --- inline manifest hooks object is scanned --------------------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"bash","args":["x"]}]}]}}'
if out="$(run_check "$f" 2>&1)"; then
  fail "inline manifest hooks object should fail, got success: $out"
else
  if echo "$out" | grep -q 'EXEC-FORM HOOK: plugins/alpha/.claude-plugin/plugin.json:.hooks.PreToolUse\[0\].hooks\[0\]:'; then
    ok "inline manifest hooks object is scanned with a resolvable path"
  else
    fail "expected inline-object flag with its path, got: $out"
  fi
fi
rm -rf "$f"

# --- an exec-form-looking object OUTSIDE the manifest hooks key is ignored ---
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","mcpServers":{"svc":{"command":"npx","args":["-y","pkg"]}},"hooks":{"PreToolUse":[]}}'
if out="$(run_check "$f" 2>&1)"; then
  ok "an MCP server command/args pair outside the hooks key is out of scope"
else
  fail "MCP server config must not be flagged, got: $out"
fi
rm -rf "$f"

# --- unreferenced hooks/*.json sibling is not scanned -----------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$SHELL_FORM_HOOKS"
plugin_file "$f" alpha hooks/unreferenced.json "$PRE_2570_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  ok "unreferenced hooks/*.json sibling stays unscanned"
else
  fail "unreferenced sibling should not be flagged, got: $out"
fi
rm -rf "$f"

# --- out-of-tree manifest hooks path is skipped, visibly --------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":"../../outside.json"}'
printf '%s\n' "$PRE_2570_HOOKS" >"$f/outside.json"
if out="$(run_check "$f" 2>&1)"; then
  if echo "$out" | grep -q 'skipping out-of-tree hooks path'; then
    ok "out-of-tree manifest hooks path is skipped with a visible notice"
  else
    fail "expected visible out-of-tree skip notice, got: $out"
  fi
else
  fail "out-of-tree path should be skipped (pass), got: $out"
fi
rm -rf "$f"

# --- unparsable manifest does not crash the gate ----------------------------
f="$(new_fixture)"
plugin_file "$f" alpha .claude-plugin/plugin.json '{not json'
plugin_file "$f" alpha hooks/hooks.json "$SHELL_FORM_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  ok "unparsable manifest is skipped (manifest validity has its own gate)"
else
  fail "unparsable manifest should not fail this gate, got: $out"
fi
rm -rf "$f"

# --- frontmatter surface ----------------------------------------------------

# skill_md <fixture> <plugin> <relpath> <content>
skill_md() { plugin_file "$@"; }

# The #2568 shape: exec form on a bare python3 in a SKILL.md frontmatter hook.
FM_EXEC_PYTHON='---
description: "x"
hooks:
  PreToolUse:
    - matcher: "Bash|PowerShell"
      hooks:
        - type: command
          command: "python3"
          args: ["${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/guard.py", "--plugin-root", "${CLAUDE_PLUGIN_ROOT}"]
          timeout: 60
metadata:
  workflow-stage: anytime
---

# Body

Prose that mentions hooks: and a fenced example below.

```yaml
hooks:
  PreToolUse:
    - hooks:
        - type: command
          command: "bash"
          args: ["x"]
```
'

# The repo-hygiene shape that #2570 established: shell form, no args.
FM_SHELL_FORM='---
description: "x"
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        # Shell form (no `args`) on purpose.
        - type: command
          command: "bash \"${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/guard.sh\""
          shell: bash
shell: bash
---

# Body
'

f="$(new_fixture)"
skill_md "$f" disk-hygiene skills/clean/SKILL.md "$FM_EXEC_PYTHON"
if out="$(run_check "$f" 2>&1)"; then
  fail "frontmatter exec-form python3 should fail, got success: $out"
else
  if [[ "$(echo "$out" | grep -c 'EXEC-FORM HOOK:')" == "1" ]] &&
    echo "$out" | grep -q 'EXEC-FORM HOOK: plugins/disk-hygiene/skills/clean/SKILL.md:8: .*"python3"'; then
    ok "frontmatter exec-form python3 fails with its line number, and the body example is ignored"
  else
    fail "expected exactly one flag at SKILL.md:8, got: $out"
  fi
fi
rm -rf "$f"

f="$(new_fixture)"
skill_md "$f" repo-hygiene skills/clean/SKILL.md "$FM_SHELL_FORM"
if out="$(run_check "$f" 2>&1)"; then
  ok "frontmatter shell form with a leading bare bash passes"
else
  fail "frontmatter shell form must not be flagged, got: $out"
fi
rm -rf "$f"

# --- frontmatter: clean and dirty hook objects in one matcher ---------------
f="$(new_fixture)"
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/bin/ok"
          args: ["--x"]
        - type: command
          command: sh
          args:
            - "-c"
            - "echo hi"
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "the dirty frontmatter sibling should fail, got success: $out"
else
  if [[ "$(echo "$out" | grep -c 'EXEC-FORM HOOK:')" == "1" ]] &&
    echo "$out" | grep -q 'SKILL.md:10: .*"sh"'; then
    ok "only the dirty frontmatter sibling is flagged, with a block-sequence args"
  else
    fail "expected exactly one flag at line 10 for sh, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: an unquoted command with a trailing comment ---------------
f="$(new_fixture)"
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
    - hooks:
        - type: command
          command: python3  # resolved from PATH
          args: ["x.py"]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "unquoted command with a trailing comment should fail, got success: $out"
else
  if echo "$out" | grep -q 'with bare command "python3"$'; then
    ok "unquoted command value is parsed without its trailing comment"
  else
    fail "expected the comment stripped from the reported value, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: a nested hooks: key at depth is still walked --------------
# `hooks:` is matched at any indentation, so a nested declaration cannot hide.
f="$(new_fixture)"
skill_md "$f" alpha skills/x/SKILL.md '---
description: "x"
  hooks:
    PreToolUse:
      - hooks:
          - type: command
            command: bash
            args: ["x"]
---
body'
if run_check "$f" >/dev/null 2>&1; then
  fail "an indented frontmatter hooks: block should still be walked"
else
  ok "frontmatter hooks: is matched at any indentation"
fi
rm -rf "$f"

# --- frontmatter: CRLF line endings ----------------------------------------
f="$(new_fixture)"
mkdir -p "$f/plugins/alpha/skills/x"
printf '%s\r\n' '---' 'hooks:' '  PreToolUse:' '    - hooks:' '        - type: command' '        # a comment' '          command: "bash"' '          args: ["x"]' '---' 'body' \
  >"$f/plugins/alpha/skills/x/SKILL.md"
if run_check "$f" >/dev/null 2>&1; then
  fail "a CRLF frontmatter hooks block should still be walked"
else
  ok "CRLF frontmatter is handled"
fi
rm -rf "$f"

# --- frontmatter: flow-style mapping fails closed ---------------------------
f="$(new_fixture)"
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
    - hooks: [{type: command, command: bash, args: ["x"]}]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "flow-style hooks block should fail closed, got success: $out"
else
  if echo "$out" | grep -q 'flow-style YAML in a frontmatter hooks block'; then
    ok "flow-style frontmatter hooks block fails closed with a visible reason"
  else
    fail "expected the flow-style message, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: a ${...} placeholder is not mistaken for flow style -------
f="$(new_fixture)"
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
    - hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/bin/guard"
          args: ["${CLAUDE_PLUGIN_ROOT}"]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  ok "a \${...} placeholder is not read as flow style"
else
  fail "placeholder braces must not trip the flow-style guard, got: $out"
fi
rm -rf "$f"

# --- markdown without frontmatter, and without hooks, is inert --------------
f="$(new_fixture)"
mkdir -p "$f/plugins/alpha/skills/x"
printf '%s\n' '# Not frontmatter' '' 'hooks:' '  PreToolUse:' '    - hooks:' '        - type: command' '          command: bash' '          args: ["x"]' \
  >"$f/plugins/alpha/skills/x/SKILL.md"
if out="$(run_check "$f" 2>&1)"; then
  ok "a hooks: block outside frontmatter is not a declaration"
else
  fail "body-only hooks: must not be flagged, got: $out"
fi
rm -rf "$f"

# --- a frontmatter block with no hooks: key at all passes -------------------
f="$(new_fixture)"
skill_md "$f" alpha skills/x/SKILL.md '---
description: "x"
allowed-tools:
  - Bash(echo:*)
---
body'
if out="$(run_check "$f" 2>&1)"; then
  ok "frontmatter without a hooks: key passes"
else
  fail "hookless frontmatter should pass, got: $out"
fi
rm -rf "$f"

# --- an agent frontmatter hook is covered too -------------------------------
f="$(new_fixture)"
skill_md "$f" alpha agents/reviewer.md '---
name: reviewer
hooks:
  PreToolUse:
    - hooks:
        - type: command
          command: bash
          args: ["x"]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "agent frontmatter hooks should be scanned, got success: $out"
else
  if echo "$out" | grep -q 'plugins/alpha/agents/reviewer.md:7:'; then
    ok "agent frontmatter hooks are covered"
  else
    fail "expected the agent file flagged at line 7, got: $out"
  fi
fi
rm -rf "$f"

# --- a fully clean tree passes with a positive statement --------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json "$SHELL_FORM_HOOKS"
skill_md "$f" alpha skills/x/SKILL.md "$FM_SHELL_FORM"
if out="$(run_check "$f" 2>&1)"; then
  if echo "$out" | grep -q 'No exec-form hooks with a bare command name.'; then
    ok "a clean tree passes with an explicit statement"
  else
    fail "expected the clean-tree statement, got: $out"
  fi
else
  fail "clean tree should pass, got: $out"
fi
rm -rf "$f"

echo
echo "passed: $PASS, failed: $FAIL"
((FAIL == 0)) || exit 1
