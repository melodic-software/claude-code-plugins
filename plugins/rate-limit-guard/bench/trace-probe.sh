#!/usr/bin/env bash
# trace-probe.sh [TEE] — capture an xtrace of a NON-ELECTED render (fresh drain
# stamp primed, spool file pre-created), and print everything the tee executes
# BEFORE the wrapped statusline passthrough. This is the probe that verifies the
# render path stays fork-free — the property #2521 exists to protect. TEE
# defaults to this repo's statusline-tee.sh. Runs against a throwaway HOME.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEE="${1:-$DIR/../scripts/statusline-tee.sh}"
W="$(mktemp -d)"
S="$W/.claude/rate-limit-guard/spool"
mkdir -p "$S"
printf -v NOW '%(%s)T' -1
printf '%s\n' "$NOW" >"$S/.last-drain"
IN='{"session_id":"sess-42","model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}'
# Prime the spool file too, so even its creation is a pure overwrite.
printf '{"e":%s,"p":%s}\n' "$NOW" "$IN" >"$S/sess-42.json"
TRACE="$W/trace.txt"
printf '%s' "$IN" | HOME="$W" RLG_TEE_DRAIN_INTERVAL=30 BASH_XTRACEFD=9 \
  bash -x "$TEE" cat >/dev/null 9>"$TRACE"
echo "=== pre-passthrough trace ==="
sed -n '1,/set +o pipefail/p' "$TRACE"
echo "=== TRACE PATH: $TRACE"
