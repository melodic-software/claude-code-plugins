#!/usr/bin/env bash
# Black-box test for count-rereads.py.
#
# Builds fixture transcripts under its own mktemp dir; touches nothing else.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/count-rereads.py"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# turn <file> <message-id> <block>...
# Appends one assistant record; several blocks share the record and its id.
turn() {
  local file="$1" id="$2" blocks="" sep=""
  shift 2
  local b
  for b in "$@"; do
    blocks+="$sep$b"
    sep=","
  done
  printf '{"type":"assistant","message":{"id":"msg_%s","content":[%s]}}\n' "$id" "$blocks" >>"$file"
}
read_of() { printf '{"type":"tool_use","name":"Read","input":{"file_path":"%s"}}' "$1"; }
read_part() { printf '{"type":"tool_use","name":"Read","input":{"file_path":"%s","offset":5,"limit":9}}' "$1"; }
edit_of() { printf '{"type":"tool_use","name":"Edit","input":{"file_path":"%s"}}' "$1"; }
grep_of() { printf '{"type":"tool_use","name":"Grep","input":{"pattern":"x","path":"%s"}}' "$1"; }
handback_of() { printf '{"type":"tool_use","name":"SubagentHandback","input":{"message":"x"}}'; }
bash_of() { printf '{"type":"tool_use","name":"Bash","input":{"command":"%s"}}' "$1"; }
text_of() { printf '{"type":"text","text":"%s"}' "$1"; }

# expect <label> <transcript> <grep-pattern>...
# Passes when the report matches every pattern.
expect() {
  local label="$1" transcript="$2" out p
  shift 2
  if ! out="$(python3 "$SUT" "$transcript" 2>&1)"; then
    fail "$label: nonzero exit: $out"
    return
  fi
  for p in "$@"; do
    if ! grep -Eq -- "$p" <<<"$out"; then
      fail "$label: output lacks /$p/: $out"
      return
    fi
  done
  pass "$label"
}

T="$WORK/three-turn.jsonl"
turn "$T" 1 "$(read_of /repo/b.md)" "$(grep_of /repo/a.md)"
turn "$T" 2 "$(read_of /repo/a.md)"
turn "$T" 3 "$(read_of /repo/b.md)" "$(text_of $'summary\\nstatus: complete')"
expect "3-turn transcript: one REREAD, one SCAN->READ, handback on turn 3" "$T" \
  '^REREAD: /repo/b\.md$' '^SCAN->READ: /repo/a\.md$' \
  '^REREAD count: 1$' '^SCAN->READ count: 1$' '^handback turn: 3$'

C="$WORK/clean.jsonl"
turn "$C" 1 "$(read_of /repo/a.md)" "$(read_of /repo/b.md)"
turn "$C" 2 "$(grep_of /repo/c.md)"
turn "$C" 3 "$(text_of 'status: complete')"
expect "clean transcript: zero and zero" "$C" '^REREAD count: 0$' '^SCAN->READ count: 0$'

E="$WORK/read-edit-read.jsonl"
turn "$E" 1 "$(read_of /repo/a.md)"
turn "$E" 2 "$(edit_of /repo/a.md)"
turn "$E" 3 "$(read_of /repo/a.md)"
expect "read, edit, read is not a REREAD" "$E" '^REREAD count: 0$'

H="$WORK/handback-tool.jsonl"
turn "$H" 1 "$(read_of /repo/a.md)"
turn "$H" 2 "$(handback_of)"
expect "SubagentHandback tool call is the handback turn" "$H" '^handback turn: 2$'

P="$WORK/parallel.jsonl"
turn "$P" 1 "$(read_of /repo/a.md)"
turn "$P" 1 "$(read_of /repo/b.md)"
turn "$P" 2 "$(read_of /repo/c.md)"
expect "records sharing a message.id are one turn" "$P" '^turns: 2$' '^handback turn: none$'

B="$WORK/bash-forms.jsonl"
turn "$B" 1 "$(bash_of 'cat /repo/a.md')" "$(bash_of 'ls /repo/docs')" "$(bash_of "grep -n x /repo/g.md")"
turn "$B" 2 "$(read_of /repo/a.md)" "$(read_of /repo/docs/d.md)" "$(read_of /repo/g.md)"
turn "$B" 3 "$(read_part /repo/a.md)" "$(bash_of 'cat /repo/a.md | wc -l')"
expect "Bash cat is a read, ls scans its directory, grep scans its file" "$B" \
  '^REREAD: /repo/a\.md$' '^SCAN->READ: /repo/docs/d\.md$' '^SCAN->READ: /repo/g\.md$' \
  '^REREAD count: 1$' '^SCAN->READ count: 2$'

E="$WORK/grep-e.jsonl"
turn "$E" 1 "$(bash_of 'grep -e needle /repo/e.md')"
turn "$E" 2 "$(read_of /repo/e.md)"
expect "grep -e keeps its first file operand" "$E" '^SCAN->READ: /repo/e\.md$' '^SCAN->READ count: 1$'

S="$WORK/same-turn.jsonl"
turn "$S" 1 "$(grep_of /repo/a.md)" "$(read_of /repo/a.md)"
expect "a scan and a read in one turn is not SCAN->READ" "$S" '^SCAN->READ count: 0$'

if [[ "$(python3 "$SUT" "$T")" == *"summary"* ]]; then
  fail "transcript content is never printed"
else
  pass "transcript content is never printed"
fi

if python3 "$SUT" "$WORK/absent.jsonl" >/dev/null 2>&1; then
  fail "a missing transcript exits nonzero"
else
  pass "a missing transcript exits nonzero"
fi

if [[ "$fails" -ne 0 ]]; then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo "all passed"
