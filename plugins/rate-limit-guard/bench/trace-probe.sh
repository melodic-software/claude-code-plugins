#!/usr/bin/env bash
# trace-probe.sh [--count] [TEE] — capture an xtrace of a NON-ELECTED render
# (fresh drain stamp primed, spool file pre-created), and print everything the
# tee executes BEFORE the wrapped statusline passthrough. This is the probe that
# verifies the render path stays fork-free — the property #2521 exists to
# protect. TEE defaults to this repo's statusline-tee.sh. Runs against a
# throwaway HOME.
#
# --count instead prints, per render shape, how many processes the tee spawns
# before the passthrough: `<shape>: processes spawned: N`. A process is either
# an external command (PATH holds only stubs that log their pid, then exec the
# real one, so a child of a child is seen too) or a bash subshell fork (a `$( )`
# or pipeline element, seen as a second BASHPID in the xtrace). The two are
# merged by pid, so a subshell that becomes a jq counts once. Process counts do
# not drift with machine load, unlike the wall-clock lanes.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNT=0
if [[ "${1:-}" == "--count" ]]; then
  COUNT=1
  shift
fi
TEE="${1:-$DIR/../scripts/statusline-tee.sh}"
W="$(mktemp -d)"
IN='{"session_id":"sess-42","model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}'
# Same payload, one window moved: the drained snapshot body changes.
IN2='{"session_id":"sess-42","model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":24.5,"resets_at":1738425600}}}'

if ((COUNT)); then
  trap 'rm -rf "$W"' EXIT
  REAL_PATH="$PATH"
  PASSTHROUGH="$(type -P cat)" # absolute, so the stubs never log it
  LOG="$W/exec.log"
  mkdir "$W/stubs"
  # shellcheck disable=SC2016  # the stub body expands when it runs, not here
  printf '#!%s\nprintf "%%s\\n" "$$" >>"%s"\nexec "$(PATH="%s" type -P "${0##*/}")" "$@"\n' \
    "$BASH" "$LOG" "$REAL_PATH" >"$W/stub"
  chmod +x "$W/stub"
  # The counted render's PATH holds only these stubs, so an external the tee
  # starts calling that is missing here fails loudly instead of going uncounted.
  for c in jq mv rm mkdir chmod find sleep date; do
    ln -s "$W/stub" "$W/stubs/$c"
  done

  # count_shape LABEL HOME INPUT — one render of TEE under HOME, then the number
  # of distinct processes it spawned before the passthrough.
  count_shape() {
    local label="$1" home="$2" trace="$W/trace.txt" main n
    : >"$LOG"
    printf '%s' "$3" | HOME="$home" PATH="$W/stubs" RLG_TEE_DRAIN_INTERVAL=30 \
      PS4='@${BASHPID}@ ' BASH_XTRACEFD=9 "$BASH" -x "$TEE" "$PASSTHROUGH" \
      >/dev/null 2>"$W/err" 9>"$trace"
    if grep -q 'command not found' "$W/err"; then
      echo "trace-probe: the tee called an external with no stub; add it to the stub list:" >&2
      cat "$W/err" >&2
      exit 1
    fi
    sed -n '1,/set +o pipefail/p' "$trace" | sed -n 's/^@*\([0-9][0-9]*\)@ .*/\1/p' >"$W/pids"
    read -r main <"$W/pids"
    n="$(cat "$LOG" "$W/pids" | grep -vx "$main" | sort -u | grep -c .)"
    printf '%s: processes spawned: %s\n' "$label" "$n"
  }
  # age_stamp HOME FILE SECONDS — make the spool stamp FILE SECONDS old.
  age_stamp() {
    local now
    printf -v now '%(%s)T' -1
    printf '%s\n' "$((now - $3))" >"$1/.claude/rate-limit-guard/spool/$2"
  }

  # Non-elected: the drain stamp is fresh and the session's spool record exists.
  H="$W/idle"
  mkdir -p "$H/.claude/rate-limit-guard/spool"
  age_stamp "$H" .last-drain 0
  printf -v NOW '%(%s)T' -1
  printf '{"e":%s,"p":%s}\n' "$NOW" "$IN" >"$H/.claude/rate-limit-guard/spool/sess-42.json"
  count_shape "non-elected, unchanged input" "$H" "$IN"
  count_shape "non-elected, changed input" "$H" "$IN2"

  # Elected: the drain stamp is past the cadence. A fresh HOME is the first
  # render on a machine; the same HOME afterwards is steady state.
  H="$W/drain"
  mkdir -p "$H"
  count_shape "elected drain, first render on a machine" "$H" "$IN"
  age_stamp "$H" .last-drain 31
  count_shape "elected drain, snapshot unchanged" "$H" "$IN"
  age_stamp "$H" .last-drain 31
  count_shape "elected drain, snapshot rewritten" "$H" "$IN2"
  age_stamp "$H" .last-drain 31
  age_stamp "$H" .last-sweep 301
  count_shape "elected drain, snapshot rewritten, orphan sweep due" "$H" "$IN"
  exit 0
fi

S="$W/.claude/rate-limit-guard/spool"
mkdir -p "$S"
printf -v NOW '%(%s)T' -1
printf '%s\n' "$NOW" >"$S/.last-drain"
# Prime the spool file too, so even its creation is a pure overwrite.
printf '{"e":%s,"p":%s}\n' "$NOW" "$IN" >"$S/sess-42.json"
TRACE="$W/trace.txt"
printf '%s' "$IN" | HOME="$W" RLG_TEE_DRAIN_INTERVAL=30 BASH_XTRACEFD=9 \
  bash -x "$TEE" cat >/dev/null 9>"$TRACE"
echo "=== pre-passthrough trace ==="
sed -n '1,/set +o pipefail/p' "$TRACE"
echo "=== TRACE PATH: $TRACE"
