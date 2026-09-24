#!/usr/bin/env bash
# Unit tests for check-hook-slow-shapes.sh. Each scenario builds a small
# plugins/ tree in a temp dir and runs the gate against it; the gate's own
# `cd "$(dirname "$0")/.."` scans <fixture>/plugins/. Every shape is exercised
# from both sides: a gate that only ever sees clean input proves nothing.
# shellcheck disable=SC2016  # fixture bodies are literal shell/JSON/YAML carrying ${CLAUDE_PLUGIN_ROOT} and $TRANSCRIPT; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-hook-slow-shapes.sh"
READER="$SELF_DIR/check-hook-exec-form-frontmatter.py"
REQUIREMENTS="$SELF_DIR/../.github/requirements-ci.txt"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
f=""

new_fixture() { # <out-var>
  fixture_tree::build "$1" --sut "$SCRIPT" --sut "$READER" --plugins || return 1
  mkdir -p "${!1}/.github"
  cp "$REQUIREMENTS" "${!1}/.github/requirements-ci.txt"
}

# plugin_file <fixture> <plugin> <relpath> <content>
plugin_file() {
  mkdir -p "$1/plugins/$2/$(dirname "$3")"
  printf '%s\n' "$4" >"$1/plugins/$2/$3"
}

# row_json <command> [<extra-object>]: one Stop row. The command goes in on
# stdin, not as an argument, because Git Bash rewrites a `.../hooks/x.sh`
# argument into a Windows path before a native jq sees it.
row_json() {
  local extra="${2:-}"
  [[ -n "$extra" ]] || extra='{}'
  printf '%s' "$1" | jq -Rs --argjson x "$extra" '{hooks:{Stop:[{hooks:[{type:"command",command:.} + $x]}]}}'
}

# hooks_json <fixture> <plugin> <command>
hooks_json() {
  mkdir -p "$1/plugins/$2/hooks"
  row_json "$3" >"$1/plugins/$2/hooks/hooks.json"
}

run_check() (
  cd "$1" && bash scripts/check-hook-slow-shapes.sh 2>&1
)

# expect <label> <fixture> <want-rc> [<needle>]
expect() {
  local label="$1" out rc
  out="$(run_check "$2")"
  rc=$?
  if ((rc == $3)) && [[ -z "${4:-}" || "$out" == *"$4"* ]]; then
    ok "$label"
  else
    fail "$label (rc=$rc, want $3${4:+ and '$4'}): $out"
  fi
}

ENV_SCRIPT='#!/usr/bin/env bash
exit 0'
ROOTED='"${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh'

# --- shape (b): a #!/usr/bin/env script with no interpreter prefix ---------

new_fixture f
plugin_file "$f" demo hooks/x.sh "$ENV_SCRIPT"
hooks_json "$f" demo "$ROOTED"
expect "(b) an unprefixed #!/usr/bin/env hook FAILS" "$f" 1 "ENV SHEBANG: plugins/demo/hooks/hooks.json"

new_fixture f
plugin_file "$f" demo hooks/x.sh "$ENV_SCRIPT"
hooks_json "$f" demo "bash $ROOTED"
expect "(b) the same hook with a leading bash passes" "$f" 0 "no slow hook shapes"

new_fixture f
plugin_file "$f" demo hooks/x.sh "$ENV_SCRIPT"
hooks_json "$f" demo '[ "$X" = true ] || exit 0; exec '"$ROOTED"
expect "(b) an opt-in row that execs the script unprefixed FAILS" "$f" 1 "ENV SHEBANG"

new_fixture f
plugin_file "$f" demo hooks/x.sh "$ENV_SCRIPT"
hooks_json "$f" demo '[ "$X" = true ] || exit 0; exec bash '"$ROOTED"
expect "(b) the opt-in row with exec bash passes" "$f" 0

new_fixture f
plugin_file "$f" demo hooks/x.sh '#!/bin/bash
exit 0'
hooks_json "$f" demo "$ROOTED"
expect "(b) an absolute-interpreter shebang has no env hop and passes" "$f" 0

new_fixture f
plugin_file "$f" demo hooks/x.sh "$ENV_SCRIPT"
mkdir -p "$f/plugins/demo/hooks"
row_json "$ROOTED" '{"args":[]}' >"$f/plugins/demo/hooks/hooks.json"
expect "(b) exec form (args present) is out of scope" "$f" 0

new_fixture f
plugin_file "$f" demo hooks/x.sh "$ENV_SCRIPT"
plugin_file "$f" demo skills/s/SKILL.md '---
name: s
hooks:
  PreToolUse:
    - hooks:
        - type: command
          command: '"'"'"${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh'"'"'
---
body'
expect "(b) a skill-frontmatter hook is scanned" "$f" 1 "ENV SHEBANG: plugins/demo/skills/s/SKILL.md"

# A shell-form frontmatter hook whose command is not a scalar is unreadable, a
# finding, never silently skipped.
new_fixture f
plugin_file "$f" demo hooks/x.sh "$ENV_SCRIPT"
plugin_file "$f" demo hooks/y.sh '#!/bin/bash
exit 0'
hooks_json "$f" demo 'bash "${CLAUDE_PLUGIN_ROOT}"/hooks/y.sh'
plugin_file "$f" demo skills/s/SKILL.md '---
name: s
hooks:
  PreToolUse:
    - hooks:
        - type: command
          command:
            - x.sh
---
body'
expect "(b) a non-scalar shell-form frontmatter command is a finding" "$f" 1 "UNREADABLE FRONTMATTER: plugins/demo/skills/s/SKILL.md"

new_fixture f
plugin_file "$f" demo hooks/x.sh "$ENV_SCRIPT"
plugin_file "$f" demo .claude-plugin/plugin.json '{"name":"demo","hooks":"./config/extra.json"}'
mkdir -p "$f/plugins/demo/config"
row_json "$ROOTED" >"$f/plugins/demo/config/extra.json"
expect "(b) a manifest-pointed hook config is scanned" "$f" 1 "ENV SHEBANG: plugins/demo/config/extra.json"

# --- shape (a): a whole-file read of the transcript -------------------------

# transcript_hook <body-after-assignment>
transcript_hook() {
  printf '#!/bin/bash\nTRANSCRIPT=$(jq -r .transcript_path)\n%s\nexit 0\n' "$1"
}

for read_line in 'mapfile LINES <"$TRANSCRIPT"' 'while read -r l; do :; done <"$TRANSCRIPT"' \
  'cat "$TRANSCRIPT" >/dev/null' 'grep -F x -- "${TRANSCRIPT}"' 'jq -c . "$TRANSCRIPT"'; do
  new_fixture f
  plugin_file "$f" demo hooks/x.sh "$(transcript_hook "$read_line")"
  hooks_json "$f" demo "bash $ROOTED"
  expect "(a) '$read_line' FAILS" "$f" 1 "TRANSCRIPT READ: plugins/demo/hooks/x.sh:3"
done

new_fixture f
plugin_file "$f" demo hooks/x.sh "$(transcript_hook 'tail -c 65536 -- "$TRANSCRIPT" | grep -F x')"
hooks_json "$f" demo "bash $ROOTED"
expect "(a) a tail -c bounded read passes" "$f" 0

new_fixture f
plugin_file "$f" demo hooks/x.sh "$(transcript_hook 'grep -F x -- "$TRANSCRIPT" | head -c 4096')"
hooks_json "$f" demo "bash $ROOTED"
expect "(a) a head -c AFTER a whole-file reader is not a bound and FAILS" "$f" 1 "TRANSCRIPT READ"

# A bound in an earlier command on the same line bounds nothing later.
for read_line in 'head -c 1 /dev/null; cat "$TRANSCRIPT"' 'tail -c 5 /dev/null && grep -F x "$TRANSCRIPT"'; do
  new_fixture f
  plugin_file "$f" demo hooks/x.sh "$(transcript_hook "$read_line")"
  hooks_json "$f" demo "bash $ROOTED"
  expect "(a) '$read_line' is not bounded by the earlier command and FAILS" "$f" 1 "TRANSCRIPT READ"
done

# Documented miss (header, "Out of reach"): text that merely contains
# `tail -c` reads as a bound. Pinned so a change in this behavior is seen;
# the growth ratchets, not this lint, catch the cost.
new_fixture f
plugin_file "$f" demo hooks/x.sh "$(transcript_hook 'grep -c "tail -c" "$TRANSCRIPT"')"
hooks_json "$f" demo "bash $ROOTED"
expect "(a) KNOWN MISS: bound text inside a grep pattern reads as bounded" "$f" 0

new_fixture f
plugin_file "$f" demo hooks/x.sh "$(transcript_hook '# slow-shape-ok: size-checked above
mapfile LINES <"$TRANSCRIPT"')"
hooks_json "$f" demo "bash $ROOTED"
expect "(a) a slow-shape-ok marker on the line above excuses the read" "$f" 0

new_fixture f
plugin_file "$f" demo hooks/x.sh "$(transcript_hook '[[ -f "$TRANSCRIPT" ]] || exit 0
python3 x.py --transcript "$TRANSCRIPT"')"
hooks_json "$f" demo "bash $ROOTED"
expect "(a) a test or hand-off of the path is not a read" "$f" 0

# A launcher's bare-name arguments resolve under the same plugin's hooks/.
new_fixture f
plugin_file "$f" demo hooks/run.sh '#!/bin/bash
exit 0'
plugin_file "$f" demo hooks/inner.sh "$(transcript_hook 'cat "$TRANSCRIPT"')"
hooks_json "$f" demo 'bash "${CLAUDE_PLUGIN_ROOT}"/hooks/run.sh inner.sh'
expect "(a) a launcher argument script is scanned" "$f" 1 "TRANSCRIPT READ: plugins/demo/hooks/inner.sh"

# --- deterministic output ----------------------------------------------------
# Several flagged scripts: the findings come out in sorted path order, the same
# on every run.
new_fixture f
for s in zz mm aa kk; do
  plugin_file "$f" demo "hooks/$s.sh" "$(transcript_hook 'cat "$TRANSCRIPT"')"
done
hooks_json "$f" demo 'bash "${CLAUDE_PLUGIN_ROOT}"/hooks/zz.sh; bash "${CLAUDE_PLUGIN_ROOT}"/hooks/mm.sh; bash "${CLAUDE_PLUGIN_ROOT}"/hooks/aa.sh; bash "${CLAUDE_PLUGIN_ROOT}"/hooks/kk.sh'
first="$(run_check "$f" | grep '^TRANSCRIPT READ: plugins/')"
second="$(run_check "$f" | grep '^TRANSCRIPT READ: plugins/')"
sorted="$(printf '%s\n' "$first" | LC_ALL=C sort)"
if [[ "$(grep -c . <<<"$first")" == 4 && "$first" == "$second" && "$first" == "$sorted" ]]; then
  ok "findings are sorted by path and identical across runs"
else
  fail "findings are sorted by path and identical across runs: $first"
fi

# ENV SHEBANG findings too: jq walks Stop before Notification (document order),
# and the output must still come out sorted.
new_fixture f
plugin_file "$f" demo hooks/x.sh "$ENV_SCRIPT"
printf '%s' "$ROOTED" | jq -Rs '{hooks:{Stop:[{hooks:[{type:"command",command:.}]}],
  Notification:[{hooks:[{type:"command",command:.}]}]}}' >"$f/plugins/demo/hooks/hooks.json"
first="$(run_check "$f" | grep '^ENV SHEBANG: plugins/')"
second="$(run_check "$f" | grep '^ENV SHEBANG: plugins/')"
sorted="$(printf '%s\n' "$first" | LC_ALL=C sort)"
if [[ "$(grep -c . <<<"$first")" == 2 && "$first" == "$second" && "$first" == "$sorted" ]]; then
  ok "ENV SHEBANG findings are sorted and identical across runs"
else
  fail "ENV SHEBANG findings are sorted and identical across runs: $first"
fi

# --- fail closed -------------------------------------------------------------

new_fixture f
mkdir -p "$f/plugins/demo/hooks"
printf '{not json\n' >"$f/plugins/demo/hooks/hooks.json"
expect "an unparsable hooks.json is a finding, not a clean run" "$f" 1 "UNREADABLE HOOK CONFIG"

new_fixture f
mkdir -p "$f/plugins/demo/hooks"
jq -n '{hooks:{}}' >"$f/plugins/demo/hooks/hooks.json"
expect "a corpus with no command hooks refuses to report clean" "$f" 1 "refusing to report clean"

test_harness::report
