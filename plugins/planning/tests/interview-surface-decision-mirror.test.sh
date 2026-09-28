#!/usr/bin/env bash
# Pins the page-protocol rule that a session-recorded ledger decision is mirrored
# onto the interview page. The op already existed; the gap was that the protocol
# required it only for a verbatim terminal answer (#5009).
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../../.." && pwd)
surface="$root/plugins/planning/skills/interview/context/surface.md"
skill="$root/plugins/planning/skills/interview/SKILL.md"
loop="$root/plugins/planning/skills/interview/context/loop.md"
fail=0
need() {
  local label=$1 file=$2 phrase=$3
  if grep -qF "$phrase" "$file"; then
    echo "ok: $label"
  else
    echo "FAIL: $label"
    fail=1
  fi
}
need "R-K requires a same-wake mirror" "$surface" \
  "| R-K | When the session records or revises a ledger decision, mirror it onto the page with \`record-terminal\` in the same wake | skill |"
need "op table covers a session-recorded decision" "$surface" \
  "Mirror a terminal answer or a session-recorded decision"
need "SKILL.md mirrors a session-recorded decision" "$skill" \
  "A decision this session records or revises in the ledger is mirrored the same way."
need "loop.md mirrors a session-recorded decision" "$loop" \
  "and so is a decision this session records or revises in the ledger."
exit "$fail"
