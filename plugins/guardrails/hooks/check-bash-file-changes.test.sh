#!/usr/bin/env bash
# test-scope: plugins/guardrails/hooks/hooks.json
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

payload() { # <event> <cwd> [tool]; BG=true marks the call run_in_background
  jq -cn --arg e "$1" --arg c "$2" --arg t "${3:-Bash}" --argjson bg "${BG:-false}" \
    '{session_id:"sess",transcript_path:"",cwd:$c,hook_event_name:$e,tool_name:$t,
      tool_use_id:"toolu_1",tool_input:{command:"node write.js",run_in_background:$bg}}'
}
# The notes a post fire carries, from whichever field the output used.
notes() { jq -r '.reason // .hookSpecificOutput.additionalContext // empty' <<<"$1"; }
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
assert_contains "new file: names the file, quoted" "$(jq -r .reason <<<"$OUT")" 'changed "config.txt"'
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
  "$(jq -r .hookSpecificOutput.additionalContext <<<"$OUT")" 'changed "config.txt"'

# 5. The PowerShell tool is gated the same way.
new_repo
pre "$REPO" PowerShell
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
OUT=$(post "$REPO" PostToolUse PowerShell)
assert_contains "powershell: names the tool and file" "$(jq -r .reason <<<"$OUT")" \
  'this PowerShell command changed "config.txt"'

# 5b. A tracked file whose content forges a diff header, and one whose name
#     git quotes or tab-suffixes in its own header: each still gets its lines
#     checked.
new_repo
printf 'one\n' >"$REPO/sp ace.txt"
printf 'one\n' >"$REPO/forged.txt"
git -C "$REPO" add . && git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qm more
pre "$REPO"
scratch append "$REPO/sp ace.txt" "dir = $LINUX_HOME"
scratch append "$REPO/forged.txt" "++ b/zzz"
scratch append "$REPO/forged.txt" "dir = $LINUX_HOME"
OUT=$(jq -r .reason <<<"$(post "$REPO")")
assert_contains "space in name: checked" "$OUT" 'changed "sp ace.txt"'
assert_contains "forged header: checked" "$OUT" 'changed "forged.txt"'

# 5c. The command writes and stages: a new file and a tracked file.
g() { git -C "$REPO" -c user.name=t -c user.email=t@example.invalid -c rerere.enabled=false "$@"; }
new_repo
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
scratch append "$REPO/tracked.txt" "dir = $LINUX_HOME"
g add config.txt tracked.txt
OUT=$(jq -r .reason <<<"$(post "$REPO")")
assert_contains "staged new file: checked" "$OUT" 'changed "config.txt"'
assert_contains "staged tracked file: checked" "$OUT" 'changed "tracked.txt"'

# 5d. The command writes and commits, leaving git status clean.
new_repo
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
scratch append "$REPO/tracked.txt" "dir = $LINUX_HOME"
g add config.txt tracked.txt && g commit -qm write
OUT=$(post "$REPO")
EXPECTED=$(edit_path Edit "$REPO/tracked.txt" "dir = $LINUX_HOME")
assert_contains "committed new file: checked" "$(jq -r .reason <<<"$OUT")" 'changed "config.txt"'
assert_contains "committed tracked file: the Edit path's own message" "$(jq -r .reason <<<"$OUT")" "$EXPECTED"

# 5d2. A no-op HEAD update after the commit does not hide it.
new_repo
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
g add config.txt && g commit -qm write && g reset -q --soft HEAD
assert_contains "commit then no-op reset: checked" "$(jq -r .reason <<<"$(post "$REPO")")" \
  'changed "config.txt"'

# 5d3. Nor does a checkout round trip back to the commit.
new_repo
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
g add config.txt && g commit -qm write && g checkout -q HEAD^ && g checkout -q -
assert_contains "commit then checkout round trip: checked" \
  "$(jq -r .reason <<<"$(post "$REPO")")" 'changed "config.txt"'

# 5d4. The first commit on an unborn branch: judged whole.
N=$((N + 1))
REPO="$TEST_TMPDIR/repo$N"
mkdir -p "$REPO" && git -C "$REPO" init -q
export CLAUDE_PROJECT_DIR="$REPO"
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
g add config.txt && g commit -qm first
assert_contains "initial commit: checked" "$(jq -r .reason <<<"$(post "$REPO")")" \
  'changed "config.txt"'

# 5d5. A commit in a linked worktree, whose .git is a file.
new_repo
g worktree add -q "$TEST_TMPDIR/linked$N" -b linked
REPO="$TEST_TMPDIR/linked$N"
export CLAUDE_PROJECT_DIR="$REPO"
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
g add config.txt && g commit -qm write
assert_contains "linked worktree commit: checked" "$(jq -r .reason <<<"$(post "$REPO")")" \
  'changed "config.txt"'

# 5d6. A conflicted merge the command resolves and commits.
new_repo
g checkout -qb side
scratch append "$REPO/tracked.txt" "side"
g commit -qam side
g checkout -q -
scratch append "$REPO/tracked.txt" "main"
g commit -qam main
pre "$REPO"
g merge -q side >/dev/null 2>&1
printf 'hello\ndir = %s\n' "$LINUX_HOME" >"$REPO/tracked.txt"
g add tracked.txt && g commit -qm merged
assert_contains "resolved merge commit: checked" "$(jq -r .reason <<<"$(post "$REPO")")" \
  'changed "tracked.txt"'

# ===================== MUST REPORT A SKIP OR TRUNCATION ======================

# R1. The #6709 repro: 20 benign files sort before the flagged one, so the
#     check stops at 20 of 21 and says one file went unexamined.
new_repo
pre "$REPO"
touch "$REPO"/a{01..20}
scratch write "$REPO/zz.sh" "root = $LINUX_HOME"
OUT=$(post "$REPO")
assert_eq "file cap: reported to Claude without blocking" "PostToolUse" \
  "$(jq -r .hookSpecificOutput.hookEventName <<<"$OUT")"
assert_contains "file cap: count and reason" "$(notes "$OUT")" \
  "1 changed file not examined: the check stops after the first 20 in path order"

# R1b. Past the cap with a finding among the first 20: the block reason
#      carries both.
new_repo
pre "$REPO"
touch "$REPO"/b{01..21}
scratch write "$REPO/a.txt" "root = $LINUX_HOME"
OUT=$(post "$REPO")
assert_eq "file cap with finding: still blocks" "block" "$(jq -r .decision <<<"$OUT")"
assert_contains "file cap with finding: names the file" "$(notes "$OUT")" 'changed "a.txt"'
assert_contains "file cap with finding: counts the rest" "$(notes "$OUT")" \
  "2 changed files not examined"

# R1c. More than 20 commits in one command, the flagged file only in the first:
#      the earlier commits go unread, and the check says so.
new_repo
pre "$REPO"
scratch write "$REPO/zz.sh" "root = $LINUX_HOME"
g add zz.sh && g commit -qm flagged
for i in {01..20}; do g commit -q --allow-empty -m "c$i"; done
assert_contains "commit cap: reported" "$(notes "$(post "$REPO")")" \
  "the command made 21 commits and the check reads only the last 20, so 1 earlier commit is not checked"

# R2. The command leaves more than 10000 paths in git status.
new_repo
pre "$REPO"
mkdir "$REPO/many" && seq -f "$REPO/many/f%g" 1 10001 | xargs touch
assert_contains "status over the entry limit: reported" "$(notes "$(post "$REPO")")" \
  "changed files not examined: git status failed or listed more than 10000 paths"

# R2b. The repository was already over the limit when the snapshot ran.
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
assert_contains "snapshot over the entry limit: reported" "$(notes "$(post "$REPO")")" \
  "changed files not examined: git status failed or listed more than 10000 paths"

# R3. A run_in_background command writes after the post fire.
new_repo
BG=true pre "$REPO"
assert_contains "background command: reported" "$(notes "$(BG=true post "$REPO")")" \
  "changed files not examined: the command runs in the background"

# R4. A new symbolic link to a file outside the repository: reported, and its
#     target is never read, so nothing outside the repository is quoted back.
new_repo
printf 'root = %s\n' "$LINUX_HOME" >"$TEST_TMPDIR/outside.txt"
pre "$REPO"
ln -s "$TEST_TMPDIR/outside.txt" "$REPO/link.txt"
OUT=$(notes "$(post "$REPO")")
assert_contains "new symlink: reported" "$OUT" "1 changed file not examined: a symbolic link is not followed"
assert_absent "new symlink: target not quoted" "$OUT" "jdoe"

# R5. A check with no snapshot (the PreToolUse fire never ran or failed).
new_repo
rm -rf "$SNAPSHOTS"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
assert_contains "no snapshot: reported" "$(notes "$(post "$REPO")")" \
  "changed files not examined: no git status snapshot was recorded before the command"

# ================= MUST SAY THE GUARD DID NOT RUN (#6905) ====================

# The notice the shell hooks' abort boundary gives a fail-open hook
# (abort-boundary.sh), with this hook's name.
DID_NOT_RUN='guardrails check-bash-file-changes: guard did not run (internal error, rc=1); this call was not checked. Details: claude --debug.'

# D1. The snapshot cannot be written: CLAUDE_PLUGIN_DATA names a file, so
#     creating the snapshot directory under it throws.
new_repo
printf 'x\n' >"$TEST_TMPDIR/not-a-dir"
RC=0
OUT=$(payload PreToolUse "$REPO" | CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/not-a-dir" \
  node "$HOOK" snapshot 2>"$TEST_TMPDIR/err") || RC=$?
assert_exit "snapshot throws: fail-open exit" 0 "$RC"
assert_eq "snapshot throws: systemMessage" "$DID_NOT_RUN" "$(jq -r .systemMessage <<<"$OUT")"
assert_eq "snapshot throws: stdout is one document" "1" "$(jq -s length <<<"$OUT")"
assert_eq "snapshot throws: notice is stderr's first line" "$DID_NOT_RUN" "$(head -n 1 "$TEST_TMPDIR/err")"

# D2. The check reads a snapshot that is valid JSON but not an object.
new_repo
pre "$REPO"
for f in "$SNAPSHOTS"/*.json; do printf 'null' >"$f"; done
RC=0
OUT=$(post "$REPO" 2>"$TEST_TMPDIR/err") || RC=$?
assert_exit "check throws: fail-open exit" 0 "$RC"
assert_eq "check throws: systemMessage" "$DID_NOT_RUN" "$(jq -r .systemMessage <<<"$OUT")"
assert_eq "check throws: notice is stderr's first line" "$DID_NOT_RUN" "$(head -n 1 "$TEST_TMPDIR/err")"

# ========================== MUST STAY QUIET =================================

# 5h. A normal run with a benign change writes nothing to stdout or stderr
#     and exits 0: the failure notice is for a failure only.
new_repo
RC=0
ERR=$(pre "$REPO" 2>&1 >/dev/null) || RC=$?
assert_silent "normal snapshot: stderr silent" "$ERR"
scratch write "$REPO/notes.txt" "nothing to see"
OUT=$(post "$REPO" 2>"$TEST_TMPDIR/err") || RC=$?
assert_exit "normal run: exit" 0 "$RC"
assert_silent "normal check: stdout silent" "$OUT"
assert_silent "normal check: stderr silent" "$(cat "$TEST_TMPDIR/err")"

# 5f. Exactly 20 benign changed files: at the cap, nothing left unexamined.
new_repo
pre "$REPO"
touch "$REPO"/c{01..20}
assert_silent "20 files, at the cap: silent" "$(post "$REPO")"

# 5g. A symbolic link already there before the command, untouched by it, and
#     a tracked file the command deletes.
new_repo
ln -s tracked.txt "$REPO/old-link"
pre "$REPO"
rm "$REPO/tracked.txt"
scratch write "$REPO/notes.txt" "nothing to see"
assert_silent "pre-existing link and a deletion: silent" "$(post "$REPO")"

# 5e. A checkout that brings in a branch with a flagged file is not this
#     command's writing.
new_repo
g checkout -qb other
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
g add config.txt && g commit -qm other
g checkout -q -
pre "$REPO"
g checkout -q other
assert_silent "checkout of a branch: silent" "$(post "$REPO")"

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

# 12. The kill switch.
new_repo
rm -rf "$SNAPSHOTS"
CLAUDE_PLUGIN_OPTION_BASH_FILE_CHANGE_CHECK_ENABLED=false pre "$REPO"
assert_eq "kill switch: no snapshot written" "no" "$([[ -d "$SNAPSHOTS" && -n "$(ls -A "$SNAPSHOTS")" ]] && echo yes || echo no)"
pre "$REPO"
scratch write "$REPO/config.txt" "root = $LINUX_HOME"
OUT=$(CLAUDE_PLUGIN_OPTION_BASH_FILE_CHANGE_CHECK_ENABLED=false post "$REPO")
assert_silent "kill switch: check silent" "$OUT"

# 12b. No CLAUDE_PLUGIN_DATA: nothing is written anywhere, not even to a
#      shared temp directory another user could plant a link at.
new_repo
T_TMP="$TEST_TMPDIR/tmpdir"
mkdir -p "$T_TMP"
payload PreToolUse "$REPO" | env -u CLAUDE_PLUGIN_DATA TMPDIR="$T_TMP" node "$HOOK" snapshot
assert_eq "no plugin data dir: temp dir untouched" "" "$(ls -A "$T_TMP")"

# 13. Malformed stdin.
assert_silent "malformed stdin: silent" "$(printf 'not json' | node "$HOOK" check)"

report
