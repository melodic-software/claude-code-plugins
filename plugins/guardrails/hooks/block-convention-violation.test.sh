#!/usr/bin/env bash
# Contract test for block-convention-violation.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess, pipes PreToolUse JSON on stdin,
# asserts on exit code (2 = blocked, 0 = allowed). Each case runs against an
# isolated repo root whose team convention file this test controls.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-convention-violation.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Isolated repo root with an optional team convention body. A real git repo so
# repo-root resolution and the sequencer probe answer for THIS directory, not
# the enclosing marketplace repo.
newrepo() {
  local d
  d="$(mktemp -d "$TEST_TMPDIR/repo.XXXXXX")"
  git -C "$d" init -q -b main
  mkdir -p "$d/.claude"
  [[ -n "${1:-}" ]] && printf '%s\n' "$1" >"$d/.claude/source-control.md"
  printf '%s' "$d"
}

# run <label> <repo> <command> <expected-exit> [tool]
run() {
  local label="$1" repo="$2" command="$3" expected="$4" tool="${5:-Bash}" rc json
  json=$(jq -n --arg t "$tool" --arg c "$command" --arg d "$repo" \
    '{tool_name:$t,tool_input:{command:$c},cwd:$d}')
  CLAUDE_PROJECT_DIR="$repo" bash "$HOOK" <<<"$json" >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

TICKET=$'## subject_pattern\n^[A-Z]+-[0-9]+: .+\n\n## pr_title_pattern\nSame as `subject_pattern`.'
CC=$'## subject_pattern\nConventional Commits'
PCRE=$'## subject_pattern\n^(?:feat|fix): .+'

GOOD_COMMIT=$'git commit -F - --cleanup=verbatim <<\'EOF\'\nABC-123: do the thing\n\nBody line.\nEOF'
BAD_COMMIT=$'git commit -F - --cleanup=verbatim <<\'EOF\'\njunk subject\n\nBody line.\nEOF'

# --- unresolved -> no enforcement ---------------------------------------------
r="$(newrepo "")"
run "no team file: violating subject allowed" "$r" "$BAD_COMMIT" 0
r="$(newrepo $'## trailer_policy\nnone')"
run "key absent: violating subject allowed" "$r" "$BAD_COMMIT" 0
r="$(newrepo "$PCRE")"
run "PCRE pattern: non-enforceable, allowed" "$r" "$BAD_COMMIT" 0

# --- subject enforcement -------------------------------------------------------
r="$(newrepo "$TICKET")"
run "ticket pattern: conforming subject allowed" "$r" "$GOOD_COMMIT" 0
run "ticket pattern: violating subject blocked" "$r" "$BAD_COMMIT" 2
run "ticket pattern: violating subject in prose (no commit) allowed" "$r" "echo 'junk subject'" 0
r="$(newrepo "$CC")"
run "CC keyword: conforming feat: subject allowed" "$r" \
  $'git commit -F - <<\'EOF\'\nfeat: add thing\nEOF' 0
run "CC keyword: violating subject blocked" "$r" "$BAD_COMMIT" 2

# --- exemption taxonomy (inherited from block-noncanonical-commit) ------------
r="$(newrepo "$TICKET")"
run "--amend exempt" "$r" "git commit --amend --no-edit" 0
run "-C exempt" "$r" "git commit -C HEAD~1" 0
run "--fixup exempt" "$r" "git commit --fixup abc123" 0
run "-F path exempt (message not on command line)" "$r" "git commit -F msg.txt" 0
run "-m form not stdin-form (mechanic gate's concern), allowed here" "$r" \
  "git commit -m 'junk subject'" 0

# --- sequencer in progress: never content-gated -------------------------------
r="$(newrepo "$TICKET")"
git -C "$r" commit -q --allow-empty -F - --cleanup=verbatim <<'EOF'
ABC-1: seed
EOF
mkdir -p "$(git -C "$r" rev-parse --absolute-git-dir)"
touch "$(git -C "$r" rev-parse --absolute-git-dir)/MERGE_HEAD"
run "sequencer: violating subject allowed mid-merge" "$r" "$BAD_COMMIT" 0

# --- non-heredoc stdin producer: content unknown, skip ------------------------
r="$(newrepo "$TICKET")"
run "printf | git commit -F -: unreadable content, allowed" "$r" \
  "printf 'junk subject' | git commit -F -" 0

# --- gh pr create --title ------------------------------------------------------
r="$(newrepo "$TICKET")"
run "gh pr create: conforming --title allowed" "$r" \
  "gh pr create --title 'ABC-9: ship it' --body-file b.md" 0
run "gh pr create: violating --title blocked" "$r" \
  "gh pr create --title 'junk title' --body-file b.md" 2
run "gh pr create: violating --title= blocked" "$r" \
  "gh pr create --title='junk title'" 2
run "gh pr create: no --title never blocked" "$r" "gh pr create --web" 0
run "gh pr edit --title out of scope, allowed" "$r" "gh pr edit 12 --title 'junk'" 0
r="$(newrepo $'## subject_pattern\n^[A-Z]+-[0-9]+: .+')"
run "no pr_title_pattern key: title not gated" "$r" "gh pr create --title 'junk'" 0

# --- PowerShell canonical here-string form ------------------------------------
r="$(newrepo "$TICKET")"
PS_GOOD=$'@\'\nABC-77: powershell subject\n\'@ | git commit -F - --cleanup=verbatim'
PS_BAD=$'@\'\njunk subject\n\'@ | git commit -F - --cleanup=verbatim'
run "PS: conforming here-string subject allowed" "$r" "$PS_GOOD" 0 PowerShell
run "PS: violating here-string subject blocked" "$r" "$PS_BAD" 2 PowerShell
run "PS: violating gh pr create --title blocked" "$r" \
  "gh pr create --title 'junk title'" 2 PowerShell

# --- kill switch ---------------------------------------------------------------
r="$(newrepo "$TICKET")"
json=$(jq -n --arg c "$BAD_COMMIT" --arg d "$r" \
  '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')
CLAUDE_PROJECT_DIR="$r" CLAUDE_PLUGIN_OPTION_BLOCK_CONVENTION_GATE_ENABLED=false \
  bash "$HOOK" <<<"$json" >/dev/null 2>&1
assert_exit "kill switch off: violating subject allowed" 0 $?

report
