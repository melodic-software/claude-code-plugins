#!/usr/bin/env bash
# Unit tests for scripts/lib/hook-configs.sh: one fixture tree per case, the
# library sourced inside it, and the rows its callbacks receive compared whole.
# shellcheck disable=SC2016  # fixture bodies are literal JSON/YAML; expansion is never wanted
# shellcheck disable=SC2031  # f is written by fixture_tree::build through a nameref, never in rows()'s subshell
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SELF_DIR/.." && pwd)"

# shellcheck source=test-harness.sh
. "$SELF_DIR/test-harness.sh"
# shellcheck source=fixture-tree.sh
. "$SELF_DIR/fixture-tree.sh"

f=""

new_fixture() { # <out-var>
  fixture_tree::build "$1" --sut "$SCRIPTS_DIR/check-hook-exec-form-frontmatter.py" --lib --plugins || return 1
  mkdir -p "${!1}/.github"
  cp "$SCRIPTS_DIR/../.github/requirements-ci.txt" "${!1}/.github/requirements-ci.txt"
}

put() { # <fixture> <relpath> <content>
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" >"$1/$2"
}

# rows <fixture> [scan|sources]: what the callbacks saw, one `|`-joined line each.
rows() (
  cd "$1" || exit 2
  # shellcheck source=hook-configs.sh
  . scripts/lib/hook-configs.sh
  # shellcheck disable=SC2329  # called by hook_configs::scan by name
  on_hook() { local IFS='|'; printf 'H|%s\n' "$*"; }
  # shellcheck disable=SC2329  # see above
  on_bad() { local IFS='|'; printf 'X|%s\n' "$*"; }
  if [[ "${2:-scan}" == sources ]]; then
    hook_configs::sources lib-test
    printf 'S|%s\n' ${HOOK_CONFIG_SOURCES[@]+"${HOOK_CONFIG_SOURCES[@]}"}
  else
    hook_configs::scan lib-test on_hook on_bad
  fi
)

expect() { # <label> <got> <want>
  if [[ "$2" == "$3" ]]; then
    ok "$1"
  else
    fail "$1"$'\n'"--- want"$'\n'"$3"$'\n'"--- got"$'\n'"$2"
  fi
}

event() { # <hook-object-json>: a hooks.json with one Stop hook
  printf '{"hooks":{"Stop":[{"hooks":[%s]}]}}' "$1"
}

W='.hooks.Stop[0].hooks[0]'

# --- forms and args kinds ------------------------------------------------------
new_fixture f
put "$f" plugins/a/hooks/hooks.json "$(event '{"type":"command","command":"node","args":["x.mjs",2]},{"type":"command","command":"bash x.sh"},{"type":"command","command":"bash","args":"x.sh"}')"
expect "exec with array args, shell form, and exec with string args" "$(rows "$f" 2>&1)" \
  "H|plugins/a/hooks/hooks.json|$W|exec|array|node|node x.mjs 2
H|plugins/a/hooks/hooks.json|.hooks.Stop[0].hooks[1]|shell|none|bash x.sh|bash x.sh
H|plugins/a/hooks/hooks.json|.hooks.Stop[0].hooks[2]|exec|other|bash|bash"
rm -rf "$f"

# --- a newline, CR or tab in a command stays on its row ------------------------
new_fixture f
put "$f" plugins/a/hooks/hooks.json "$(event '{"type":"command","command":"node\n","args":["x"]},{"type":"command","command":"/opt/x\r\nbash","args":["a\tb"]}')"
expect "CR, LF and TAB map to a space, one row per hook" "$(rows "$f" 2>&1)" \
  "H|plugins/a/hooks/hooks.json|$W|exec|array|node |node  x
H|plugins/a/hooks/hooks.json|.hooks.Stop[0].hooks[1]|exec|array|/opt/x  bash|/opt/x  bash a b"
rm -rf "$f"

# --- an empty command and a root-level hook keep their columns -----------------
new_fixture f
put "$f" plugins/a/hooks/hooks.json '{"type":"command","command":"","args":["z"]}'
expect "an empty path and an empty command do not shift the fields" "$(rows "$f" 2>&1)" \
  "H|plugins/a/hooks/hooks.json||exec|array|| z"
rm -rf "$f"

# --- manifest: inline map, pointed file, and an array mixing both --------------
new_fixture f
put "$f" plugins/a/.claude-plugin/plugin.json '{"name":"a","hooks":{"Stop":[{"hooks":[{"type":"command","command":"node","args":[]}]}]}}'
put "$f" plugins/b/.claude-plugin/plugin.json '{"name":"b","hooks":["./config/h.json",{"Stop":[{"hooks":[{"type":"command","command":"sh","args":[]}]}]},7]}'
put "$f" plugins/b/config/h.json "$(event '{"type":"command","command":"python3","args":["g.py"]}')"
expect "inline maps (object and array element) and a pointed file are all walked" "$(rows "$f" 2>&1)" \
  "H|plugins/a/.claude-plugin/plugin.json|.hooks.Stop[0].hooks[0]|exec|array|node|node
H|plugins/b/.claude-plugin/plugin.json|.hooks[1].Stop[0].hooks[0]|exec|array|sh|sh
H|plugins/b/config/h.json|$W|exec|array|python3|python3 g.py"
expect "sources names each JSON config and the path of its event map" "$(rows "$f" sources 2>&1)" \
  "S|plugins/a/.claude-plugin/plugin.json	[\"hooks\"]
S|plugins/b/.claude-plugin/plugin.json	[\"hooks\",1]
S|plugins/b/config/h.json	[\"hooks\"]"
rm -rf "$f"

# --- a manifest pointing at the default file does not scan it twice ------------
new_fixture f
put "$f" plugins/a/.claude-plugin/plugin.json '{"name":"a","hooks":["./hooks/hooks.json","./hooks/hooks.json"]}'
put "$f" plugins/a/hooks/hooks.json "$(event '{"type":"command","command":"node","args":[]}')"
expect "the default file named by its manifest is one source" "$(rows "$f" 2>&1)" \
  "H|plugins/a/hooks/hooks.json|$W|exec|array|node|node"
expect "and one entry in sources" "$(rows "$f" sources 2>&1)" "S|plugins/a/hooks/hooks.json	[\"hooks\"]"
rm -rf "$f"

# --- a pointed path outside the plugin is refused, visibly ---------------------
new_fixture f
put "$f" plugins/a/.claude-plugin/plugin.json '{"name":"a","hooks":"../b/hooks/x.json"}'
put "$f" plugins/b/hooks/x.json "$(event '{"type":"command","command":"bash","args":[]}')"
expect "an out-of-tree hooks path is skipped with the guard's notice" "$(rows "$f" 2>&1)" \
  "lib-test: skipping out-of-tree hooks path in plugins/a/.claude-plugin/plugin.json: ../b/hooks/x.json"
rm -rf "$f"

# --- unreadable input reaches on-unreadable, with its surface ------------------
new_fixture f
put "$f" plugins/a/hooks/hooks.json '{not json'
put "$f" plugins/b/hooks/hooks.json "$(event '{"type":"command","command":"node","args":[]}')"
put "$f" plugins/c/.claude-plugin/plugin.json '{not json'
expect "an unparsable hooks.json and manifest are reported, the rest still walked" "$(rows "$f" 2>&1)" \
  "X|json|plugins/a/hooks/hooks.json||not parseable as JSON
H|plugins/b/hooks/hooks.json|$W|exec|array|node|node
X|manifest|plugins/c/.claude-plugin/plugin.json||not parseable as JSON"
expect "sources skips an unparsable manifest" "$(rows "$f" sources 2>&1)" \
  "S|plugins/a/hooks/hooks.json	[\"hooks\"]
S|plugins/b/hooks/hooks.json	[\"hooks\"]"
rm -rf "$f"

# --- frontmatter: exec with a sequence, exec without one, shell, unreadable ----
new_fixture f
put "$f" plugins/a/skills/s/SKILL.md '---
name: s
hooks:
  Stop:
    - hooks:
        - type: command
          command: node
          args: [x.mjs]
        - type: command
          command: bash
          args: x.sh
        - type: command
          command: bash x.sh
---
body'
put "$f" plugins/a/agents/bad.md '---
hooks: [unclosed
---'
expect "frontmatter V, N, S and X records map to the same callbacks" "$(rows "$f" 2>&1)" \
  "X|frontmatter|plugins/a/agents/bad.md|2|the YAML frontmatter does not parse, so this gate cannot clear it
H|plugins/a/skills/s/SKILL.md|7|exec|array|node|node
H|plugins/a/skills/s/SKILL.md|10|exec|other|bash|bash
H|plugins/a/skills/s/SKILL.md|13|shell|none|bash x.sh|bash x.sh"
rm -rf "$f"

# --- a frontmatter reader that does not complete stops the walk ----------------
new_fixture f
printf '%s\n' 'import sys' 'sys.exit(2)' >"$f/scripts/check-hook-exec-form-frontmatter.py"
out="$(rows "$f" 2>&1)"
rc=$?
if ((rc == 2)) && [[ "$out" == *"lib-test: the frontmatter reader did not complete"* ]]; then
  ok "a reader that did not complete exits 2"
else
  fail "a reader that did not complete should exit 2, got rc=$rc: $out"
fi
rm -rf "$f"

# --- sourced-only ---------------------------------------------------------------
out="$(bash "$SELF_DIR/hook-configs.sh" 2>&1)"
rc=$?
if ((rc == 2)) && [[ "$out" == *"sourced-only"* ]]; then
  ok "executing the library exits 2"
else
  fail "executing the library should exit 2, got rc=$rc: $out"
fi

test_harness::report
