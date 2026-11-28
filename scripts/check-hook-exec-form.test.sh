#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixture bodies are literal JSON/YAML carrying ${CLAUDE_PLUGIN_ROOT}; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-hook-exec-form.sh"
READER="$SELF_DIR/check-hook-exec-form-frontmatter.py"
REQUIREMENTS="$SELF_DIR/../.github/requirements-ci.txt"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

f=""

new_fixture() {
  fixture_tree::build "$1" --sut "$SCRIPT" --sut "$READER" --plugins || return 1
  mkdir -p "${!1}/.github"
  cp "$REQUIREMENTS" "${!1}/.github/requirements-ci.txt"
}

plugin_file() {
  local fixture="$1" plugin="$2" rel="$3" content="$4"
  mkdir -p "$fixture/plugins/$plugin/$(dirname "$rel")"
  printf '%s\n' "$content" >"$fixture/plugins/$plugin/$rel"
}

run_check() (
  cd "$1" && bash scripts/check-hook-exec-form.sh
)

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

new_fixture f
plugin_file "$f" disk-hygiene hooks/hooks.json "$PRE_2570_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  fail "pre-#2570 exec-form bash hooks should fail, got success: $out"
else
  if grep -q 'EXEC-FORM HOOK: plugins/disk-hygiene/hooks/hooks.json:.hooks.PreToolUse\[0\].hooks\[0\]: .*"bash"' <<<"$out" &&
    grep -q 'EXEC-FORM HOOK: plugins/disk-hygiene/hooks/hooks.json:.hooks.Stop\[0\].hooks\[0\]: .*"bash"' <<<"$out"; then
    ok "pre-#2570 shape fails, and BOTH exec-form entries are named"
  else
    fail "expected both PreToolUse and Stop entries flagged with their paths, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" disk-hygiene hooks/hooks.json "$SHELL_FORM_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  ok "shell form with a leading bare bash passes (args presence is the discriminator)"
else
  fail "shell form must not be flagged, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$ROOTED_EXEC_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  ok "exec form with a rooted command path passes"
else
  fail "rooted exec-form command should pass, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"C:\\Program Files\\nodejs\\node.exe","args":["x.mjs"]}]}]}'
if out="$(run_check "$f" 2>&1)"; then
  ok "exec form with an absolute Windows path passes"
else
  fail "absolute Windows path should pass, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/hooks/x.mjs"]}]}]}'
if out="$(run_check "$f" 2>&1)"; then
  ok "allowlisted bare name (node) passes"
else
  fail "node is the documented Windows exec-form spelling and must pass, got: $out"
fi
rm -rf "$f"

for name in bash sh python python3 py pwsh deno; do
  new_fixture f
  plugin_file "$f" alpha hooks/hooks.json "{\"hooks\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$name\",\"args\":[\"x\"]}]}]}"
  if run_check "$f" >/dev/null 2>&1; then
    fail "bare exec-form command '$name' should fail"
  else
    ok "bare exec-form command '$name' fails"
  fi
  rm -rf "$f"
done

if [[ "$(grep -c '^EXEC_NAME_ALLOWLIST=' "$SELF_DIR/lib/hook-configs.sh")" == 1 ]] &&
  grep -q '^EXEC_NAME_ALLOWLIST=(node)$' "$SELF_DIR/lib/hook-configs.sh"; then
  ok "allowlist is pinned to exactly (node)"
else
  fail "EXEC_NAME_ALLOWLIST changed; review the admission criterion and update this test deliberately"
fi

new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"hooks":[{"type":"command","command":"bash","args":[]}]}]}'
if run_check "$f" >/dev/null 2>&1; then
  fail "an empty args array is still exec form and must fail"
else
  ok "empty args array is still exec form"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":[{"matcher":"Bash","hooks":[
  {"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/bin/ok","args":["--x"]},
  {"type":"command","command":"python3","args":["y.py"]}]}]}'
if out="$(run_check "$f" 2>&1)"; then
  fail "the dirty sibling should fail, got success: $out"
else
  if [[ "$(echo "$out" | grep -c 'EXEC-FORM HOOK:')" == "1" ]] &&
    grep -q 'hooks\[1\]: .*"python3"' <<<"$out"; then
    ok "only the dirty sibling in a matcher entry is flagged"
  else
    fail "expected exactly one flag naming hooks[1]/python3, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":"./config/extra-hooks.json"}'
plugin_file "$f" alpha config/extra-hooks.json "$PRE_2570_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  fail "manifest-pointed hook file should fail, got success: $out"
else
  if grep -q 'EXEC-FORM HOOK: plugins/alpha/config/extra-hooks.json:' <<<"$out"; then
    ok "manifest string-path hook config is scanned"
  else
    fail "expected flag on the manifest-pointed file, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":["./hooks/hooks.json","./config/extra-hooks.json"]}'
plugin_file "$f" alpha hooks/hooks.json "$SHELL_FORM_HOOKS"
plugin_file "$f" alpha config/extra-hooks.json "$PRE_2570_HOOKS"
if run_check "$f" >/dev/null 2>&1; then
  fail "a bare exec-form command in one manifest array path should fail"
else
  ok "manifest array hook config fails on the offending element"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"bash","args":["x"]}]}]}}'
if out="$(run_check "$f" 2>&1)"; then
  fail "inline manifest hooks object should fail, got success: $out"
else
  if grep -q 'EXEC-FORM HOOK: plugins/alpha/.claude-plugin/plugin.json:.hooks.PreToolUse\[0\].hooks\[0\]:' <<<"$out"; then
    ok "inline manifest hooks object is scanned with a resolvable path"
  else
    fail "expected inline-object flag with its path, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","mcpServers":{"svc":{"command":"npx","args":["-y","pkg"]}},"hooks":{"PreToolUse":[]}}'
if out="$(run_check "$f" 2>&1)"; then
  ok "an MCP server command/args pair outside the hooks key is out of scope"
else
  fail "MCP server config must not be flagged, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$SHELL_FORM_HOOKS"
plugin_file "$f" alpha hooks/unreferenced.json "$PRE_2570_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  ok "unreferenced hooks/*.json sibling stays unscanned"
else
  fail "unreferenced sibling should not be flagged, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":"../../outside.json"}'
printf '%s\n' "$PRE_2570_HOOKS" >"$f/outside.json"
if out="$(run_check "$f" 2>&1)"; then
  if grep -q 'skipping out-of-tree hooks path' <<<"$out"; then
    ok "out-of-tree manifest hooks path is skipped with a visible notice"
  else
    fail "expected visible out-of-tree skip notice, got: $out"
  fi
else
  fail "out-of-tree path should be skipped (pass), got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha .claude-plugin/plugin.json '{not json'
plugin_file "$f" alpha hooks/hooks.json "$SHELL_FORM_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  ok "unparsable manifest is skipped (manifest validity has its own gate)"
else
  fail "unparsable manifest should not fail this gate, got: $out"
fi
rm -rf "$f"

skill_md() { plugin_file "$@"; }

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

new_fixture f
skill_md "$f" disk-hygiene skills/clean/SKILL.md "$FM_EXEC_PYTHON"
if out="$(run_check "$f" 2>&1)"; then
  fail "frontmatter exec-form python3 should fail, got success: $out"
else
  if [[ "$(echo "$out" | grep -c 'EXEC-FORM HOOK:')" == "1" ]] &&
    grep -q 'EXEC-FORM HOOK: plugins/disk-hygiene/skills/clean/SKILL.md:8: .*"python3"' <<<"$out"; then
    ok "frontmatter exec-form python3 fails with its line number, and the body example is ignored"
  else
    fail "expected exactly one flag at SKILL.md:8, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" repo-hygiene skills/clean/SKILL.md "$FM_SHELL_FORM"
if out="$(run_check "$f" 2>&1)"; then
  ok "frontmatter shell form with a leading bare bash passes"
else
  fail "frontmatter shell form must not be flagged, got: $out"
fi
rm -rf "$f"

new_fixture f
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
    grep -q 'SKILL.md:10: .*"sh"' <<<"$out"; then
    ok "only the dirty frontmatter sibling is flagged, with a block-sequence args"
  else
    fail "expected exactly one flag at line 10 for sh, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
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
  if grep -q 'with bare command "python3"$' <<<"$out"; then
    ok "unquoted command value is parsed without its trailing comment"
  else
    fail "expected the comment stripped from the reported value, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
description: "x"
metadata:
  hooks:
    PreToolUse:
      - hooks:
          - type: command
            command: bash
            args: ["x"]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  ok "a hooks: mapping nested under another key is not a declaration"
else
  fail "a nested hooks: mapping must not be walked as a declaration, got: $out"
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
- matcher: "Bash"
  hooks:
  - type: command
    command: bash
    args: ["x"]
---
body'
if run_check "$f" >/dev/null 2>&1; then
  fail "a zero-indent sequence under hooks: should stay inside the block"
else
  ok "a sequence at the hooks key's own indentation stays inside the block"
fi
rm -rf "$f"

new_fixture f
mkdir -p "$f/plugins/alpha/skills/x"
printf '%s\r\n' '---' 'hooks:' '  PreToolUse:' '    - hooks:' '        - type: command' '        # a comment' '          command: "bash"' '          args: ["x"]' '---' 'body' \
  >"$f/plugins/alpha/skills/x/SKILL.md"
if run_check "$f" >/dev/null 2>&1; then
  fail "a CRLF frontmatter hooks block should still be walked"
else
  ok "CRLF frontmatter is handled"
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
    - hooks: [{type: command, command: bash, args: ["x"]}]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "a flow-style hooks block should be walked and flagged, got success: $out"
else
  if grep -q 'EXEC-FORM HOOK: .*SKILL.md:4: .*"bash"' <<<"$out"; then
    ok "flow-style YAML in a hooks block is walked, not refused"
  else
    fail "expected a flag at line 4 for bash, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
    - hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/bin/guard"
          args:
            - --policy
            - '"'"'{"mode":"safe","roots":["{a}","{b}"]}'"'"'
---
body'
if out="$(run_check "$f" 2>&1)"; then
  ok "braces inside an args scalar are not read as a flow mapping"
else
  fail "a JSON-ish args scalar must not be judged as structure, got: $out"
fi
rm -rf "$f"

# BS keeps the literal backslash of the escape spellings unambiguous in source.
# shellcheck disable=SC1003  # a lone backslash IS the intended value here
BS='\'
for spelling in '"hooks":' "'hooks':" 'hooks :' "\"${BS}u0068ooks\":" "\"${BS}U00000068ooks\":" "\"${BS}x68ooks\":" '"hooks" :'; do
  new_fixture f
  skill_md "$f" alpha skills/x/SKILL.md "---
description: \"x\"
$spelling
  PreToolUse:
    - hooks:
        - type: command
          command: bash
          args: [\"x\"]
---
body"
  if out="$(run_check "$f" 2>&1)"; then
    fail "the '$spelling' key spelling should still be walked, got success: $out"
  else
    if grep -q 'SKILL.md:7: .*"bash"' <<<"$out"; then
      ok "the '$spelling' key spelling is walked like the bare one"
    else
      fail "expected a flag at line 7 for '$spelling', got: $out"
    fi
  fi
  rm -rf "$f"
done

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
"hooks": {PreToolUse: [{hooks: [{type: command, command: bash, args: ["x"]}]}]}
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "an inline hooks declaration should be walked and flagged, got success: $out"
else
  if grep -q 'EXEC-FORM HOOK: .*SKILL.md:2: .*"bash"' <<<"$out"; then
    ok "a whole hooks declaration on the key line is walked"
  else
    fail "expected a flag at line 2 for bash, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
hooks: {}
hooks:
  PreToolUse:
    - hooks:
        - type: command
          command: bash
          args: ["x"]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "a duplicate top-level hooks key should not clear the gate, got success: $out"
else
  if grep -q 'UNREADABLE FRONTMATTER: .*duplicate top-level `hooks` key' <<<"$out"; then
    ok "a duplicate top-level hooks key is reported, not silently first-wins"
  else
    fail "expected the duplicate-hooks message, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
    - hooks:
        - type: command
          command: node
          command: bash
          args: ["x"]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "a duplicate command key should not clear the gate, got success: $out"
else
  if grep -q 'UNREADABLE FRONTMATTER: .*duplicate `command` key' <<<"$out"; then
    ok "a duplicate key inside a hook object is reported"
  else
    fail "expected the duplicate-command message, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
base: &base
  command: node
  command: bash
  args: ["x"]
hooks:
  PreToolUse:
    - hooks:
        - <<: *base
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "a duplicate key inside a merged mapping should not clear the gate, got success: $out"
else
  if grep -q 'UNREADABLE FRONTMATTER: .*duplicate `command` key' <<<"$out"; then
    ok "a duplicate key reached through a merge key is reported"
  else
    fail "expected the duplicate-command message through the merge, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
   - a
  "unterminated
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "unparsable frontmatter should fail closed, got success: $out"
else
  if grep -q 'UNREADABLE FRONTMATTER: .*does not parse' <<<"$out"; then
    ok "unparsable YAML frontmatter fails closed"
  else
    fail "expected the does-not-parse message, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:  # the skill-scoped belt
  PreToolUse:
    - hooks:
        - type: command
          command: bash
          args: ["x"]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "a commented hooks: key should still open the block, got success: $out"
else
  if grep -q 'SKILL.md:6: .*"bash"' <<<"$out"; then
    ok "a trailing comment on the hooks key is not read as an inline value"
  else
    fail "expected the block to be walked and flagged at line 6, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" disk-hygiene skills/clean/SKILL.md '---
description: "x"
hooks:
  PreToolUse:
    - matcher: "Bash|PowerShell"
      hooks:
        # Shell form, matching hooks/hooks.json (#2568). Exec form resolves
        # `command` on PATH with no shell, and the bare `python3` this used to
        # name is the zero-length WindowsApps App Execution Alias stub.
        - type: command
          command: '"'"'"${CLAUDE_PLUGIN_ROOT}"/hooks/run-python-hook.sh "${CLAUDE_PLUGIN_ROOT}"/skills/clean/scripts/destructive_guard.py --plugin-root "${CLAUDE_PLUGIN_ROOT}"'"'"'
          shell: bash
          timeout: 60
metadata:
  workflow-stage: anytime
---

# Body
'
if out="$(run_check "$f" 2>&1)"; then
  ok "the interpreter-led shell form that #2572 landed passes"
else
  fail "the #2572 shape must pass — this gate would otherwise block its own unblocking, got: $out"
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
shared: &shared
  PreToolUse:
    - hooks:
        - type: command
          command: bash
          args: ["x"]
hooks: *shared
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "an aliased hooks value should be resolved and flagged, got success: $out"
else
  if grep -q 'EXEC-FORM HOOK: .*SKILL.md:6: .*"bash"' <<<"$out"; then
    ok "a YAML alias under the hooks key is resolved to its anchor"
  else
    fail "expected a flag at the anchor's command line, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse: &pre
    - hooks:
        - type: command
          command: bash
          args: ["x"]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "an anchored value inside a hooks block should be walked, got success: $out"
else
  if grep -q 'EXEC-FORM HOOK: .*SKILL.md:6: .*"bash"' <<<"$out"; then
    ok "an anchored value inside a hooks block is walked"
  else
    fail "expected a flag at line 6 for bash, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
base: &base
  type: command
  command: bash
  args: ["x"]
hooks:
  PreToolUse:
    - hooks:
        - <<: *base
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "a merge key should be expanded and flagged, got success: $out"
else
  if grep -q 'EXEC-FORM HOOK: .*"bash"' <<<"$out"; then
    ok "a merge key inside a hooks block is expanded"
  else
    fail "expected a bash flag through the merge key, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
base: &base
  command: bash
  args: ["x"]
hooks:
  PreToolUse:
    - hooks:
        - <<: *base
          command: "${CLAUDE_PLUGIN_ROOT}/bin/guard"
---
body'
if out="$(run_check "$f" 2>&1)"; then
  ok "an explicit key overrides the merged one, as YAML defines"
else
  fail "the explicit rooted command must win over the merged bare one, got: $out"
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
    - hooks:
        - type: command
          command: |
            bash
          args: ["x"]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "a block-scalar command should be read and flagged, got success: $out"
else
  if grep -q 'EXEC-FORM HOOK: .*"bash"' <<<"$out"; then
    ok "a block-scalar command is read as its content"
  else
    fail "expected a bash flag from the block scalar, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
skill_md "$f" alpha skills/x/SKILL.md '---
description: |
  A folded description that mentions hooks: and a list
  - like this
  and an alias-looking *token
anchors: &a
  x: 1
merged:
  <<: *a
allowed-tools:
  - Bash(echo:*)
---
body'
if out="$(run_check "$f" 2>&1)"; then
  ok "anchors, aliases, and block scalars outside a hooks block are inert"
else
  fail "non-hooks frontmatter must never be judged, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks": [ this is not json'
if out="$(run_check "$f" 2>&1)"; then
  fail "an unparsable hooks.json should fail closed, got success: $out"
else
  if grep -q 'UNREADABLE HOOK CONFIG: plugins/alpha/hooks/hooks.json:' <<<"$out"; then
    ok "an unparsable hook config fails closed and names the file"
  else
    fail "expected UNREADABLE HOOK CONFIG, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
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

new_fixture f
mkdir -p "$f/plugins/alpha/skills/x"
printf '%s\n' '# Not frontmatter' '' 'hooks:' '  PreToolUse:' '    - hooks:' '        - type: command' '          command: bash' '          args: ["x"]' \
  >"$f/plugins/alpha/skills/x/SKILL.md"
if out="$(run_check "$f" 2>&1)"; then
  ok "a hooks: block outside frontmatter is not a declaration"
else
  fail "body-only hooks: must not be flagged, got: $out"
fi
rm -rf "$f"

new_fixture f
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

new_fixture f
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
  if grep -q 'plugins/alpha/agents/reviewer.md:7:' <<<"$out"; then
    ok "agent frontmatter hooks are covered"
  else
    fail "expected the agent file flagged at line 7, got: $out"
  fi
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$SHELL_FORM_HOOKS"
printf '%s\n' 'import sys' 'sys.exit(2)' >"$f/scripts/check-hook-exec-form-frontmatter.py"
out="$(run_check "$f" 2>&1)"
rc=$?
if ((rc == 2)) && grep -q 'the frontmatter reader did not complete' <<<"$out"; then
  ok "a frontmatter reader that did not complete exits 2, never clearing plugins/"
else
  fail "expected exit 2 and the reader-did-not-complete line (rc=$rc): $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"node\n","args":["x.mjs"]}]}]}}'
if out="$(run_check "$f" 2>&1)"; then
  fail "a command of node plus a newline is not node and should fail, got success: $out"
elif grep -q 'EXEC-FORM HOOK: plugins/alpha/hooks/hooks.json:.hooks.Stop\[0\].hooks\[0\]: .*"node "' <<<"$out"; then
  ok "a trailing newline in a command is not the allowlisted name"
else
  fail "expected the node-plus-newline row flagged at its own path, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/opt/x\nbash","args":[]}]}]}}'
if out="$(run_check "$f" 2>&1)"; then
  ok "a path command with an embedded newline is one row, not a second bare one"
else
  fail "a command carrying a separator should pass as one row, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash","args":"x.sh"}]}]}}'
if out="$(run_check "$f" 2>&1)"; then
  fail "a bare bash with string args should fail, got success: $out"
elif grep -q 'EXEC-FORM HOOK: plugins/alpha/hooks/hooks.json:.hooks.Stop\[0\].hooks\[0\]: .*"bash"' <<<"$out"; then
  ok "a non-array args value is still exec form"
else
  fail "expected the string-args row flagged, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":["./config/extra-hooks.json",{"Stop":[{"hooks":[{"type":"command","command":"python3","args":["g.py"]}]}]}]}'
plugin_file "$f" alpha config/extra-hooks.json "$SHELL_FORM_HOOKS"
if out="$(run_check "$f" 2>&1)"; then
  fail "an inline map in a manifest hooks array should be scanned, got success: $out"
elif grep -q 'EXEC-FORM HOOK: plugins/alpha/.claude-plugin/plugin.json:.hooks\[1\].Stop\[0\].hooks\[0\]: .*"python3"' <<<"$out"; then
  ok "an inline map inside a manifest hooks array is scanned"
else
  fail "expected the array element's inline hook flagged with its path, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha .claude-plugin/plugin.json '{"name":"alpha","hooks":"./hooks/hooks.json"}'
plugin_file "$f" alpha hooks/hooks.json '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash","args":[]}]}]}}'
out="$(run_check "$f" 2>&1)"
if [[ "$(grep -c '^EXEC-FORM HOOK:' <<<"$out")" == 1 ]]; then
  ok "the default hooks.json named by its manifest is reported once"
else
  fail "expected exactly one finding, got: $out"
fi
rm -rf "$f"

new_fixture f
mkdir -p "$f/plugins/alpha/skills/demo"
printf '%s\n' '---' 'name: demo' 'hooks:' '  Stop:' '    - hooks:' '        - type: command' \
  '          command: bash' '          args: x.sh' '---' >"$f/plugins/alpha/skills/demo/SKILL.md"
if out="$(run_check "$f" 2>&1)"; then
  fail "a frontmatter bare bash with scalar args should fail, got success: $out"
elif grep -q 'EXEC-FORM HOOK: plugins/alpha/skills/demo/SKILL.md:7: .*"bash"' <<<"$out"; then
  ok "a frontmatter scalar args value is still exec form"
else
  fail "expected the frontmatter row flagged at line 7, got: $out"
fi
rm -rf "$f"

new_fixture f
plugin_file "$f" alpha hooks/hooks.json "$SHELL_FORM_HOOKS"
skill_md "$f" alpha skills/x/SKILL.md "$FM_SHELL_FORM"
if out="$(run_check "$f" 2>&1)"; then
  if grep -q 'No exec-form hooks with a bare command name.' <<<"$out"; then
    ok "a clean tree passes with an explicit statement"
  else
    fail "expected the clean-tree statement, got: $out"
  fi
else
  fail "clean tree should pass, got: $out"
fi
rm -rf "$f"

test_harness::report
