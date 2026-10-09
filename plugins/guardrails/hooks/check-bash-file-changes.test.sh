#!/usr/bin/env bash
# Contract test for check-bash-file-changes.mjs (guardrails plugin).
#
# Black-box: fires the snapshot mode with a PreToolUse Bash payload, runs a real
# command against a scratch repository, then fires the check mode with the
# PostToolUse (or PostToolUseFailure) payload of the same tool_use_id. The
# expected findings come from the Write/Edit path itself: the same content is
# piped through run-guards.sh with the guards of the PreToolUse Write|Edit row,
# and its message must appear in what the check reports (#6674).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/check-bash-file-changes.mjs"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_BASH_FILE_CHANGE_CHECK_ENABLED
export CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/plugin-data"
export CLAUDE_PLUGIN_ROOT="${HOOK_DIR%/hooks}"
SNAPSHOTS="$CLAUDE_PLUGIN_DATA/bash-file-snapshots"

# Runtime-assembled flagged content (no contiguous literal in source).
SL='/'
LINUX_HOME="${SL}home${SL}jdoe${SL}project"
AWS_PREFIX='AKIA'
AWS_TOKEN="${AWS_PREFIX}IOSFODNN7EXAMPLE"

SCRATCH="$TEST_TMPDIR/scratch"
mkdir -p "$SCRATCH"
# The scratch script the issue describes: written outside the repository, then
# run with node, so no Write or Edit of the repository file ever happens.
cat >"$SCRATCH/write.js" <<'EOF'
const fs = require("fs");
const [, , mode, file, text] = process.argv;
if (mode === "append") fs.appendFileSync(file, text + "\n");
else fs.writeFileSync(file, text + "\n");
EOF

N=0
new_repo() {
  N=$((N + 1))
  REPO="$TEST_TMPDIR/repo$N"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  printf 'hello\n' >"$REPO/tracked.txt"
  printf 'ignored.txt\n' >"$REPO/.gitignore"
  git -C "$REPO" add . && git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qm init
  export CLAUDE_PROJECT_DIR="$REPO"
}

payload() { # <event> <cwd> [tool]
  jq -cn --arg e "$1" --arg c "$2" --arg t "${3:-Bash}" \
    '{session_id:"sess",transcript_path:"",cwd:$c,hook_event_name:$e,tool_name:$t,
      tool_use_id:"toolu_1",tool_input:{command:"node write.js"}}'
}
pre() { payload PreToolUse "$1" "${2:-Bash}" | node "$HOOK" snapshot; }
post() { payload "${2:-PostToolUse}" "$1" "${3:-Bash}" | node "$HOOK" check; }
scratch() { node "$SCRATCH/write.js" "$@"; }

# What the Write/Edit path itself says about this file and content.
WRITE_GUARDS=$(jq -r '.hooks.PreToolUse[] | select(.matcher | test("Write")) | .hooks[0].args
  | .[(index("${CLAUDE_PLUGIN_ROOT}/hooks/run-guards.sh") + 1):][]' "$HOOK_DIR/hooks.json")
edit_path() { # <tool> <file> <text>
  local input
  if [[ "$1" == Write ]]; then
    input=$(jq -cn --arg f "$2" --arg t "$3" '{file_path:$f,content:$t}')
  else
    input=$(jq -cn --arg f "$2" --arg t "$3" '{file_path:$f,old_string:"",new_string:$t}')
  fi
  local -a guards
  read -r -d '' -a guards <<<"$WRITE_GUARDS"
  # The guards' stderr is the message; their stdout documents are not.
  { jq -cn --arg c "$REPO" --arg t "$1" --argjson i "$input" \
    '{session_id:"sess",cwd:$c,hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i}' |
    bash "$HOOK_DIR/run-guards.sh" "${guards[@]}" >/dev/null; } 2>&1
}

# =========================== MUST FIRE ======================================

# 1. `node <scratch script>` creates a repository file with a hardcoded path.
new_repo
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
OUT=$(post "$REPO")
EXPECTED=$(edit_path Write "$REPO/config.txt" "root = $LINUX_HOME")
assert_contains "edit path itself blocks the new file" "$EXPECTED" "Linux user path detected"
assert_eq "new file: PostToolUse decision" "block" "$(jq -r .decision <<<"$OUT")"
assert_contains "new file: names the file" "$(jq -r .reason <<<"$OUT")" "changed config.txt"
assert_contains "new file: carries the Write path's own message" "$(jq -r .reason <<<"$OUT")" "$EXPECTED"
assert_eq "snapshot consumed by the check" "" "$(ls -A "$SNAPSHOTS")"

# 2. The script appends to a tracked file: judged as an Edit of the added lines.
new_repo
pre "$REPO"
scratch append "$REPO/tracked.txt" "dir = $LINUX_HOME"
OUT=$(post "$REPO")
EXPECTED=$(edit_path Edit "$REPO/tracked.txt" "dir = $LINUX_HOME")
assert_contains "edit path itself blocks the appended line" "$EXPECTED" "Linux user path detected"
assert_contains "tracked file: carries the Edit path's own message" "$(jq -r .reason <<<"$OUT")" "$EXPECTED"
assert_absent "tracked file: the untouched first line is not quoted" "$(jq -r .reason <<<"$OUT")" "hello"

# 3. Every guard of the Write|Edit row runs: a secret is caught as well.
new_repo
pre "$REPO"
scratch write "$REPO/creds.txt" "key = $AWS_TOKEN"
OUT=$(post "$REPO")
EXPECTED=$(edit_path Write "$REPO/creds.txt" "key = $AWS_TOKEN")
assert_contains "edit path itself blocks the secret" "$EXPECTED" "AWS"
assert_contains "secret: carries the Write path's own message" "$(jq -r .reason <<<"$OUT")" "$EXPECTED"

# 4. A command that fails still had its writes checked, through additionalContext.
new_repo
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
OUT=$(post "$REPO" PostToolUseFailure)
assert_eq "failure: event" "PostToolUseFailure" "$(jq -r .hookSpecificOutput.hookEventName <<<"$OUT")"
assert_contains "failure: additionalContext names the file" \
  "$(jq -r .hookSpecificOutput.additionalContext <<<"$OUT")" "changed config.txt"

# 5. The PowerShell tool is gated the same way.
new_repo
pre "$REPO" PowerShell
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
OUT=$(post "$REPO" PostToolUse PowerShell)
assert_contains "powershell: names the tool and file" "$(jq -r .reason <<<"$OUT")" \
  "this PowerShell command changed config.txt"

# ========================== MUST STAY QUIET =================================

# 6. A command that changes nothing.
new_repo
pre "$REPO"
assert_silent "no change: silent" "$(post "$REPO")"

# 7. A benign change.
new_repo
pre "$REPO"
scratch write "$REPO/notes.txt" "nothing to see"
scratch append "$REPO/tracked.txt" "more text"
assert_silent "benign change: silent" "$(post "$REPO")"

# 8. A file already dirty before the command, and not touched by it, is not
#    re-reported when the command changes some other file.
new_repo
scratch write "$REPO/earlier.txt" "root = $LINUX_HOME"
pre "$REPO"
scratch write "$REPO/notes.txt" "nothing to see"
assert_silent "pre-existing dirty file untouched: silent" "$(post "$REPO")"

# 9. A gitignored file (hook-precision rule 6).
new_repo
pre "$REPO"
scratch write "$REPO/ignored.txt" "root = $LINUX_HOME"
assert_silent "gitignored file: silent" "$(post "$REPO")"

# 10. A cwd outside any repository: no snapshot, no check, fail open.
rm -rf "$SNAPSHOTS"
mkdir -p "$TEST_TMPDIR/plain"
pre "$TEST_TMPDIR/plain"
assert_eq "non-git cwd: no snapshot written" "no" "$([[ -d "$SNAPSHOTS" && -n "$(ls -A "$SNAPSHOTS")" ]] && echo yes || echo no)"
scratch write "$TEST_TMPDIR/plain/config.txt" "root = $LINUX_HOME"
assert_silent "non-git cwd: silent" "$(post "$TEST_TMPDIR/plain")"

# 11. A check with no snapshot (the PreToolUse fire never ran).
new_repo
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
assert_silent "no snapshot: silent" "$(post "$REPO")"

# 12. The kill switch.
new_repo
rm -rf "$SNAPSHOTS"
CLAUDE_PLUGIN_OPTION_BASH_FILE_CHANGE_CHECK_ENABLED=false pre "$REPO"
assert_eq "kill switch: no snapshot written" "no" "$([[ -d "$SNAPSHOTS" && -n "$(ls -A "$SNAPSHOTS")" ]] && echo yes || echo no)"
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
OUT=$(CLAUDE_PLUGIN_OPTION_BASH_FILE_CHANGE_CHECK_ENABLED=false post "$REPO")
assert_silent "kill switch: check silent" "$OUT"

# 13. Malformed stdin.
assert_silent "malformed stdin: silent" "$(printf 'not json' | node "$HOOK" check)"

report
