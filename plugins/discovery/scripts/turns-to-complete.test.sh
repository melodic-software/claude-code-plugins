#!/usr/bin/env bash
# Black-box test for turns-to-complete.py.
#
# Builds fixture transcripts under its own mktemp dir; touches nothing else.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/turns-to-complete.py"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/projects"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# mkagent <name> <agentType> <date> <turns> [parallel]
# Writes <turns> assistant turns; with "parallel" each turn is three records
# (thinking, text, tool_use) sharing one message.id.
mkagent() {
  local name="$1" type="$2" day="$3" turns="$4" parallel="${5:-}"
  local dir="$ROOT/proj/sess/subagents"
  mkdir -p "$dir"
  printf '{"agentType":"%s"}\n' "$type" >"$dir/agent-$name.meta.json"
  python3 - "$dir/agent-$name.jsonl" "$day" "$turns" "$parallel" <<'PY'
import json, sys
path, day, turns, parallel = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
with open(path, "w") as fh:
    fh.write(json.dumps({"type": "user", "timestamp": f"{day}T01:00:00.000Z",
                         "message": {"role": "user", "content": "secret prompt"}}) + "\n")
    for i in range(turns):
        for kind in (["thinking", "text", "tool_use"] if parallel else ["tool_use"]):
            fh.write(json.dumps({"type": "assistant", "timestamp": f"{day}T01:00:01.000Z",
                                 "message": {"id": f"msg_{i}", "role": "assistant",
                                             "content": [{"type": kind}]}}) + "\n")
        fh.write(json.dumps({"type": "user", "timestamp": f"{day}T01:00:02.000Z",
                             "message": {"role": "user",
                                         "content": [{"type": "tool_result"}]}}) + "\n")
PY
}

# expect <label> <expected-exit> <grep-pattern-or-empty> <args...>
expect() {
  local label="$1" want="$2" pattern="$3"
  shift 3
  local out got
  out="$(python3 "$SUT" "$@" 2>&1)"
  got=$?
  if [[ "$got" -ne "$want" ]]; then
    fail "$label: expected exit $want, got $got: $out"
  elif [[ -n "$pattern" ]] && ! grep -Eq -- "$pattern" <<<"$out"; then
    fail "$label: output lacks /$pattern/: $out"
  else
    pass "$label"
  fi
}

# expect_absent <label> <pattern> <args...>
expect_absent() {
  local label="$1" pattern="$2"
  shift 2
  if python3 "$SUT" "$@" 2>&1 | grep -Eq -- "$pattern"; then
    fail "$label: output unexpectedly matches /$pattern/"
  else
    pass "$label"
  fi
}

mkagent par discovery:researcher 2026-08-01 5 parallel
mkagent full discovery:explorer 2026-08-02 40
mkagent below discovery:explorer 2026-08-03 39
mkagent other general-purpose 2026-08-04 7
mkagent late discovery:researcher 2026-09-10 3
mkdir -p "$ROOT/proj/sess/subagents"
: >"$ROOT/proj/sess/subagents/agent-nometa.jsonl"

expect "parallel records sharing a message.id count as one turn" 0 \
  '^\| 2026-08-01 \| discovery:researcher \| 5 \| no \| n/a \|' --root "$ROOT"
expect "a 40-turn dispatch is flagged at the ceiling" 0 \
  '^\| 2026-08-02 \| discovery:explorer \| 40 \| yes \|' --root "$ROOT"
expect "a 39-turn dispatch is not flagged" 0 \
  '^\| 2026-08-03 \| discovery:explorer \| 39 \| no \|' --root "$ROOT"
expect "the summary counts dispatches at the ceiling" 0 \
  '^\| discovery:explorer \| 2 \| 39 \| 39 \| 40 \| 40 \| 1 \|' --root "$ROOT"
expect_absent "a non-discovery agentType is excluded by default" 'general-purpose' --root "$ROOT"
expect "--agent-type selects another type" 0 'general-purpose' \
  --root "$ROOT" --agent-type general-purpose
expect_absent "--since drops earlier dispatches" '2026-08-0' --root "$ROOT" --since 2026-09-01
expect "--since keeps later dispatches" 0 '2026-09-10' --root "$ROOT" --since 2026-09-01
expect "--json emits per-dispatch rows and a summary" 0 '"at_ceiling": 1' --root "$ROOT" --json
expect_absent "transcript content is never printed" 'secret prompt' --root "$ROOT" --json
expect "a missing root exits 2" 2 'cannot read root' --root "$WORK/absent"

mkagent resumed discovery:researcher 2026-08-05 40
printf '%s\n' '{"type":"user","timestamp":"2026-08-05T02:00:00.000Z","message":{"role":"user","content":"continue"}}' \
  >>"$ROOT/proj/sess/subagents/agent-resumed.jsonl"
expect "a user record after the ceiling marks the dispatch resumed" 0 \
  '^\| 2026-08-05 \| discovery:researcher \| 40 \| yes \| yes \|' --root "$ROOT"
expect "a ceiling stop with no later user record reports unknown" 0 \
  '^\| 2026-08-02 \| discovery:explorer \| 40 \| yes \| unknown \|' --root "$ROOT"

if [[ "$fails" -ne 0 ]]; then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo "all passed"
