#!/usr/bin/env bash
# Contract tests for the Stop row (markdown_format_end_of_turn), launched
# exactly as hooks.json registers it: unset (the default), an uncommitted
# finding exits 0 with the finding in a systemMessage; true, it exits 2 with the
# finding on stderr; either way nothing is rewritten; stop_hook_active keeps it
# from blocking twice in one turn; false and the plugin kill switch run no
# check. The spawn budget case fences the cost of a Stop with the option false:
# the node launcher only.
# test-scope: plugins/markdown-format/hooks/hooks.json plugins/markdown-format/git-hooks/markdown-check.sh plugins/markdown-format/.claude-plugin/plugin.json
# test-scope: plugins/markdown-format/hooks/exec-bash.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HOOK_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
for tool in node jq git; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "SKIP: $tool not on PATH -- end-of-turn tests skipped"
    exit 0
  }
done
REAL_MD="$(command -v markdownlint-cli2 || true)"
[[ -n "$REAL_MD" ]] || REAL_MD="$REPO_ROOT/node_modules/.bin/markdownlint-cli2"
if [[ ! -x "$REAL_MD" ]]; then
  echo "SKIP: markdownlint-cli2 not found -- end-of-turn tests skipped"
  exit 0
fi
PATH="${REAL_MD%/*}:$PATH"
export PATH

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

# The Stop row's args from hooks.json, with the plugin root substituted.
mapfile -t ARGS < <(jq -r '.hooks.Stop[0].hooks[0].args[]' "$PLUGIN/hooks/hooks.json" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$PLUGIN#g")
expect "the Stop row launches node with the end-of-turn gate" \
  "node --run-if-unset-or-true MARKDOWN_FORMAT_ENABLED --run-if-unset-or-true MARKDOWN_FORMAT_END_OF_TURN --end-of-turn" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$PLUGIN/hooks/hooks.json") ${ARGS[1]} ${ARGS[2]} ${ARGS[3]} ${ARGS[4]} ${ARGS[6]}"

R="$WORK/repo"
git init -q -b main "$R"
git -C "$R" config user.name t
git -C "$R" config user.email t@example.invalid
printf '{ "config": { "default": true, "MD013": false } }\n' >"$R/.markdownlint-cli2.jsonc"
printf '# Seed\n' >"$R/a.md"
git -C "$R" add -A
git -C "$R" commit -q -m seed

stop() { # <stop_hook_active> [env...] -> "<rc>|<stderr>"
  local active="$1" err rc
  shift
  err="$(cd "$R" && printf '{"session_id":"s","hook_event_name":"Stop","stop_hook_active":%s,"cwd":"%s"}' "$active" "$R" |
    env "$@" node "${ARGS[@]}" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$err"
}

# report [env...]: one fire with stop_hook_active false, keeping stdout apart
# from stderr; sets REPORT_RC, REPORT_OUT and REPORT_ERR.
report() {
  REPORT_OUT="$(cd "$R" && printf '{"session_id":"s","hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}' "$R" |
    env "$@" node "${ARGS[@]}" 2>"$WORK/report.err")"
  REPORT_RC=$?
  REPORT_ERR="$(cat "$WORK/report.err")"
}

# The finding lines are the tool's own documented messages; the closing hint
# line is this plugin's wording, so the case drops it instead of restating it.
findings() { printf '%s' "${1%$'\n'*}"; }
FINDING='a.md:3: MD033/no-inline-html Inline HTML [Element: b]'
printf '# Seed\n\n<b>x</b>\n' >"$R/a.md"
report
expect "default: an uncommitted finding exits 0 with nothing on stderr" "0|" "$REPORT_RC|$REPORT_ERR"
expect "default: stdout is one JSON object with only a systemMessage" "systemMessage" \
  "$(jq -r 'keys | join(",")' <<<"$REPORT_OUT" 2>/dev/null)"
expect "default: the systemMessage carries the finding" "$FINDING" \
  "$(findings "$(jq -r '.systemMessage' <<<"$REPORT_OUT" 2>/dev/null)")"
expect "default: nothing is rewritten" "$(printf '# Seed\n\n<b>x</b>')" "$(cat "$R/a.md")"
unset_doc="$REPORT_OUT"
report CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN=
expect "default: an empty value reports the same way" "0|$unset_doc|" "$REPORT_RC|$REPORT_OUT|$REPORT_ERR"
expect "true: an uncommitted finding on a changed line exits 2 with the finding" "2|$FINDING" \
  "$(findings "$(stop false CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN=true)")"
expect "true: nothing is rewritten" "$(printf '# Seed\n\n<b>x</b>')" "$(cat "$R/a.md")"
expect "true: stop_hook_active means it already blocked this turn" "0|" \
  "$(stop true CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN=true)"
report CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN=false
expect "false: no check runs" "0||" "$REPORT_RC|$REPORT_OUT|$REPORT_ERR"
report CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=false
expect "default: the plugin kill switch runs no check" "0||" "$REPORT_RC|$REPORT_OUT|$REPORT_ERR"
expect "true: the plugin kill switch wins" "0|" \
  "$(stop false CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN=true CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=false)"
# Without markdownlint-cli2 the check script fails an agent (git-hooks test);
# the row turns that one failure into a silent pass, since the SessionStart
# probe already reports the missing tool. CLAUDECODE=1 makes the run an agent's,
# so these cases reach that failure rather than a person's notice.
NOTOOL="$WORK/no-markdownlint"
mkdir -p "$NOTOOL"
for t in node git bash sed awk cat mktemp rm dirname grep tr jq; do
  ln -s "$(command -v "$t")" "$NOTOOL/$t"
done
expect "true: a missing markdownlint-cli2 passes silently" "0|" \
  "$(stop false CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN=true CLAUDECODE=1 PATH="$NOTOOL")"
report CLAUDECODE=1 PATH="$NOTOOL"
expect "default: a missing markdownlint-cli2 passes silently" "0||" "$REPORT_RC|$REPORT_OUT|$REPORT_ERR"
git -C "$R" checkout -q a.md
report
expect "default: a clean work tree prints nothing" "0||" "$REPORT_RC|$REPORT_OUT|$REPORT_ERR"
expect "true: a clean work tree passes" "0|" "$(stop false CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN=true)"

CENSUS="$REPO_ROOT/scripts/hook-census.sh"
# A working Linux strace, not merely one on PATH: Git Bash ships Cygwin's, which has no -s.
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1 && strace -qq -o /dev/null -e trace=execve true 2>/dev/null; then
  out="$(bash "$CENSUS" markdown-format Stop markdown-format.sh \
    '{"session_id":"census","hook_event_name":"Stop","stop_hook_active":false,"cwd":"@DIR@"}' \
    --env CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_END_OF_TURN=false --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: with the option false a Stop costs only the node launcher" "spawns=1" "${out%% *}"
else
  echo "NOTE: a working strace or scripts/hook-census.sh is absent; the spawn budget case did not run."
fi

echo "markdown-format end-of-turn: $PASS passed, $FAIL failed"
((FAIL == 0))
