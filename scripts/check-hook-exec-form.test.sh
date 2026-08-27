#!/usr/bin/env bash
# Unit tests for check-hook-exec-form.sh. Builds a tiny synthetic plugins/ tree
# per scenario in a temp dir and invokes the script against it directly -- the
# script's own `cd "$(dirname "$0")/.."` makes this work unmodified: copy it to
# <fixture>/scripts/ and it scans <fixture>/plugins/.
# shellcheck disable=SC2016  # fixture bodies are literal JSON/YAML carrying ${CLAUDE_PLUGIN_ROOT}; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-hook-exec-form.sh"
READER="$SELF_DIR/check-hook-exec-form-frontmatter.py"
REQUIREMENTS="$SELF_DIR/../.github/requirements-ci.txt"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/plugins" "$dir/.github"
  cp "$SCRIPT" "$dir/scripts/check-hook-exec-form.sh"
  cp "$READER" "$dir/scripts/check-hook-exec-form-frontmatter.py"
  chmod +x "$dir/scripts/check-hook-exec-form.sh" "$dir/scripts/check-hook-exec-form-frontmatter.py"
  # The gate reads the pyyaml pin from here for its uv fallback; copy the real
  # file so a fixture run resolves the same version CI installs.
  cp "$REQUIREMENTS" "$dir/.github/requirements-ci.txt"
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

# --- frontmatter: only a TOP-LEVEL hooks key is a declaration ---------------
# Claude Code reads `hooks` as a top-level frontmatter key. A `hooks:` mapping
# nested under some other key is data, not a hook registration, and must not be
# walked as one -- every markdown file reaches the walk now, so a nested match
# would be a false positive rather than extra coverage.
f="$(new_fixture)"
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

# --- frontmatter: a sequence at the key's own indentation stays in block ----
# YAML permits a block sequence to sit at the mapping key's indentation, so a
# zero-indent `- ` under a zero-indent `hooks:` must not close the block.
f="$(new_fixture)"
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

# --- frontmatter: flow style is the same document, and is walked ------------
f="$(new_fixture)"
skill_md "$f" alpha skills/x/SKILL.md '---
hooks:
  PreToolUse:
    - hooks: [{type: command, command: bash, args: ["x"]}]
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "a flow-style hooks block should be walked and flagged, got success: $out"
else
  if echo "$out" | grep -q 'EXEC-FORM HOOK: .*SKILL.md:4: .*"bash"'; then
    ok "flow-style YAML in a hooks block is walked, not refused"
  else
    fail "expected a flag at line 4 for bash, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: braces inside an ordinary scalar are not structure --------
# A block-sequence `args` entry may legitimately be a JSON-ish string. Reading
# YAML as text made that look like a flow mapping and red-lined a valid file;
# a real parser cannot make that mistake.
f="$(new_fixture)"
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

# --- frontmatter: every YAML spelling of the hooks key is a declaration -----
# Bare, double-quoted, single-quoted, space-before-colon, and the three escape
# encodings all denote the same key, and only a real parser sees that: the
# reader hands the document to one instead of matching the token as text, so
# the scanner has already decoded the key by the time the gate sees it.
# BS keeps the literal backslash of the escape spellings unambiguous in source.
# shellcheck disable=SC1003  # a lone backslash IS the intended value here
BS='\'
for spelling in '"hooks":' "'hooks':" 'hooks :' "\"${BS}u0068ooks\":" "\"${BS}U00000068ooks\":" "\"${BS}x68ooks\":" '"hooks" :'; do
  f="$(new_fixture)"
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
    if echo "$out" | grep -q 'SKILL.md:7: .*"bash"'; then
      ok "the '$spelling' key spelling is walked like the bare one"
    else
      fail "expected a flag at line 7 for '$spelling', got: $out"
    fi
  fi
  rm -rf "$f"
done

# --- frontmatter: a whole declaration on the key line is walked -------------
f="$(new_fixture)"
skill_md "$f" alpha skills/x/SKILL.md '---
"hooks": {PreToolUse: [{hooks: [{type: command, command: bash, args: ["x"]}]}]}
---
body'
if out="$(run_check "$f" 2>&1)"; then
  fail "an inline hooks declaration should be walked and flagged, got success: $out"
else
  if echo "$out" | grep -q 'EXEC-FORM HOOK: .*SKILL.md:2: .*"bash"'; then
    ok "a whole hooks declaration on the key line is walked"
  else
    fail "expected a flag at line 2 for bash, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: a duplicate hooks key is ambiguous, not a first-wins pass --
# PyYAML's loader keeps the last value; js-yaml rejects the document. A gate
# must not pick the reading that clears the file, and #1492 already proved a
# duplicate key can ship through a green suite.
f="$(new_fixture)"
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
  if echo "$out" | grep -q 'UNREADABLE FRONTMATTER: .*duplicate top-level `hooks` key'; then
    ok "a duplicate top-level hooks key is reported, not silently first-wins"
  else
    fail "expected the duplicate-hooks message, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: a duplicate key inside a hook object is ambiguous ----------
f="$(new_fixture)"
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
  if echo "$out" | grep -q 'UNREADABLE FRONTMATTER: .*duplicate `command` key'; then
    ok "a duplicate key inside a hook object is reported"
  else
    fail "expected the duplicate-command message, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: a duplicate arriving through a merge key is still caught --
# A merged mapping contributes its keys to the hook object, so checking only
# the keys written at the hook object itself would leave `<<` as the way in.
f="$(new_fixture)"
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
  if echo "$out" | grep -q 'UNREADABLE FRONTMATTER: .*duplicate `command` key'; then
    ok "a duplicate key reached through a merge key is reported"
  else
    fail "expected the duplicate-command message through the merge, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: unparsable YAML fails closed ------------------------------
# The one thing a real parser still cannot clear. A file the gate cannot read
# is a file it must not pass.
f="$(new_fixture)"
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
  if echo "$out" | grep -q 'UNREADABLE FRONTMATTER: .*does not parse'; then
    ok "unparsable YAML frontmatter fails closed"
  else
    fail "expected the does-not-parse message, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: a trailing comment on the hooks key is not a value --------
# `hooks:  # why` opens a block like any other; treating the comment as an
# inline declaration would be a false positive on ordinary YAML.
f="$(new_fixture)"
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
  if echo "$out" | grep -q 'SKILL.md:6: .*"bash"'; then
    ok "a trailing comment on the hooks key is not read as an inline value"
  else
    fail "expected the block to be walked and flagged at line 6, got: $out"
  fi
fi
rm -rf "$f"

# --- the interpreter-led shell form from #2568 must pass --------------------
# Shell form in a single-quoted YAML scalar, with a comment block and sibling
# keys inside the hooks block. This is the shape that removed the last
# violation from this repository; a gate that flagged its own remedy would
# leave the defect no correct way out.
f="$(new_fixture)"
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
  ok "the interpreter-led shell form #2572 lands passes"
else
  fail "the #2572 shape must pass — this gate would otherwise block its own unblocking, got: $out"
fi
rm -rf "$f"

# --- frontmatter: a YAML alias under the key is resolved, not skipped -------
# `hooks:` whose value is `*shared` expands to the anchored mapping. The old
# text walk matched neither a sequence nor a mapping key on that line and
# skipped it, so an anchored exec-form hook cleared the gate.
f="$(new_fixture)"
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
  if echo "$out" | grep -q 'EXEC-FORM HOOK: .*SKILL.md:6: .*"bash"'; then
    ok "a YAML alias under the hooks key is resolved to its anchor"
  else
    fail "expected a flag at the anchor's command line, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: an anchor on a value inside the block is walked -----------
f="$(new_fixture)"
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
  if echo "$out" | grep -q 'EXEC-FORM HOOK: .*SKILL.md:6: .*"bash"'; then
    ok "an anchored value inside a hooks block is walked"
  else
    fail "expected a flag at line 6 for bash, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: a merge key is expanded ----------------------------------
# `<<: *base` makes the merged mapping's keys the hook object's keys, so the
# exec-form pair arrives through the merge and must still be seen.
f="$(new_fixture)"
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
  if echo "$out" | grep -q 'EXEC-FORM HOOK: .*"bash"'; then
    ok "a merge key inside a hooks block is expanded"
  else
    fail "expected a bash flag through the merge key, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter: an explicit key wins over a merged one --------------------
f="$(new_fixture)"
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

# --- frontmatter: a block scalar command is read as its content -------------
f="$(new_fixture)"
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
  if echo "$out" | grep -q 'EXEC-FORM HOOK: .*"bash"'; then
    ok "a block-scalar command is read as its content"
  else
    fail "expected a bash flag from the block scalar, got: $out"
  fi
fi
rm -rf "$f"

# --- frontmatter outside the hooks key is never judged ----------------------
# Every markdown file under plugins/ reaches the reader, so shapes elsewhere in
# the frontmatter must stay inert -- otherwise the gate would red-line ordinary
# skills for YAML that has nothing to do with hooks.
f="$(new_fixture)"
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

# --- an unparsable hook config fails closed ---------------------------------
# A file the gate cannot read is a file the gate cannot clear; skipping it
# silently would recreate the no-op-that-looks-green failure it exists to stop.
f="$(new_fixture)"
plugin_file "$f" alpha hooks/hooks.json '{"hooks": [ this is not json'
if out="$(run_check "$f" 2>&1)"; then
  fail "an unparsable hooks.json should fail closed, got success: $out"
else
  if echo "$out" | grep -q 'UNREADABLE HOOK CONFIG: plugins/alpha/hooks/hooks.json:'; then
    ok "an unparsable hook config fails closed and names the file"
  else
    fail "expected UNREADABLE HOOK CONFIG, got: $out"
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

test_harness::report
