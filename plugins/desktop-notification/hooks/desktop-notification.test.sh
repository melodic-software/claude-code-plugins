#!/usr/bin/env bash
# Black-box contract test for desktop-notification.sh (the desktop-notification plugin hook).
#
# Proves WIRING, not baseline parity: master kill switch, matcher detection
# (permission_prompt + idle_prompt emit a terminalSequence), non-actionable /
# empty stdin exit silently, the per-channel BELL + TERMINAL_NOTIFY gate matrix,
# the OSC allowlist (OSC 9 present, OSC 2 + rejected sequences absent), and the
# opt-in HOOK_TELEMETRY_SINK envelope contract.
#
# Self-contained: builds a throwaway git repo (deterministic git-branch probe)
# and defines its own assertion helpers — installed plugins are cache-isolated
# with no shared test lib. The OS_TOAST channel's actual toast emission is out of
# scope (osascript / notify-send are platform-specific, self-backgrounded, and
# stdout-redirected); os_toast is disabled by default here so terminal-channel
# assertions stay deterministic cross-platform.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/desktop-notification.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

# Fake repo so the git-branch probe is deterministic and REPO_ROOT resolves.
FAKE_REPO="$WORK/repo"
mkdir -p "$FAKE_REPO"
git -C "$FAKE_REPO" init -q
git -C "$FAKE_REPO" config user.email t@t.t
git -C "$FAKE_REPO" config user.name t
git -C "$FAKE_REPO" commit --allow-empty -m init -q

# make_sink <body> → path to an executable single-command stub sink running
# <body> (which reads the envelope on stdin). HOOK_TELEMETRY_SINK must be a
# single executable path, so tests point it at a stub script under $WORK.
make_sink() {
  local s
  s="$(mktemp -p "$WORK" sink.XXXXXX)"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$1"
  } >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}

# Block until <file> is non-empty (fire-and-forget sink flushed) or bound elapses.
wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

build_input() {
  local type="$1" message="${2:-Needs your attention}"
  MSYS_NO_PATHCONV=1 jq -n --arg t "$type" --arg m "$message" \
    '{notification_type: $t, message: $m}'
}

# stdout-only runner. Clears ambient channel + sink vars (hermetic against a live
# session's env), enables the master switch, defaults OS_TOAST off (keeps stdout
# deterministic + fires no real toast), then applies caller overrides last.
run() {
  local input="$1"
  shift
  (cd "$UNRELATED" && printf '%s' "$input" \
    | env -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED \
      -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED \
      -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED \
      -u HOOK_TELEMETRY_SINK \
      CLAUDE_PROJECT_DIR="$FAKE_REPO" \
      CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=true \
      CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED=false \
      "$@" \
      bash "$HOOK" 2>/dev/null)
}

# Count BEL (\007) bytes in a terminalSequence JSON payload (raw-decoded).
bel_count() {
  jq -r '.terminalSequence' <<<"$1" | tr -cd '\007' | wc -c | tr -d ' \r'
}

# --- Case 1: master kill switch false → silent exit 0 -----------------------
OUT="$(cd "$UNRELATED" && build_input permission_prompt \
  | env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$FAKE_REPO" \
    CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=false bash "$HOOK" 2>&1)"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch false → silent exit 0"; else fail "kill switch (rc=$RC out=$OUT)"; fi

# --- Case 2: enabled + permission_prompt → terminalSequence, OSC allowlist ---
OUT="$(run "$(build_input permission_prompt)")"
RC=$?
if [[ $RC -eq 0 ]]; then ok "permission_prompt exit 0"; else fail "permission_prompt exit $RC"; fi
if printf '%s' "$OUT" | jq -e '.terminalSequence' >/dev/null 2>&1; then
  ok "permission_prompt → terminalSequence, stdout parses as JSON"
else
  fail "permission_prompt → no terminalSequence JSON: $OUT"
fi
if printf '%s' "$OUT" | grep -q ']9;'; then ok "permission_prompt → OSC 9 present"; else fail "permission_prompt → OSC 9 missing: $OUT"; fi
if printf '%s' "$OUT" | grep -q ']2;'; then fail "permission_prompt → OSC 2 present (would clobber session title)"; else ok "permission_prompt → no OSC 2 title"; fi
if printf '%s' "$OUT" | grep -qE ']1337|]8;'; then fail "permission_prompt → rejected OSC present"; else ok "permission_prompt → no rejected OSC (1337/8)"; fi

# --- Case 3: enabled + idle_prompt → terminalSequence -----------------------
OUT="$(run "$(build_input idle_prompt)")"
if printf '%s' "$OUT" | jq -e '.terminalSequence' >/dev/null 2>&1; then ok "idle_prompt → terminalSequence"; else fail "idle_prompt → no terminalSequence: $OUT"; fi

# --- Case 4: non-actionable notification_type → silent exit 0 ---------------
OUT="$(run "$(build_input auth_success)")"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "non-actionable type → silent exit 0"; else fail "non-actionable type (rc=$RC out=$OUT)"; fi

# --- Case 5: empty stdin → silent exit 0 ------------------------------------
OUT="$(cd "$UNRELATED" && env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$FAKE_REPO" \
  CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=true bash "$HOOK" </dev/null 2>&1)"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "empty stdin → silent exit 0"; else fail "empty stdin (rc=$RC out=$OUT)"; fi

# --- Case 6: all channel vars unset → OSC 9 + 2 BELs ------------------------
OUT="$(run "$(build_input permission_prompt)")"
if printf '%s' "$OUT" | grep -q ']9;'; then ok "backward-compat → OSC 9 present"; else fail "backward-compat → OSC 9 missing: $OUT"; fi
if [[ "$(bel_count "$OUT")" == "2" ]]; then ok "backward-compat → 2 BELs (OSC terminator + standalone bell)"; else fail "backward-compat → BEL count $(bel_count "$OUT"), want 2"; fi

# --- Case 7: BELL off → OSC 9 + terminator only, 1 BEL ----------------------
OUT="$(run "$(build_input permission_prompt)" CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED=false)"
if printf '%s' "$OUT" | grep -q ']9;'; then ok "BELL off → OSC 9 terminator intact"; else fail "BELL off → OSC 9 missing: $OUT"; fi
if [[ "$(bel_count "$OUT")" == "1" ]]; then ok "BELL off → 1 BEL (OSC terminator only)"; else fail "BELL off → BEL count $(bel_count "$OUT"), want 1"; fi

# --- Case 8: TERMINAL_NOTIFY off → bare BEL, no OSC 9 -----------------------
OUT="$(run "$(build_input permission_prompt)" CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED=false)"
if printf '%s' "$OUT" | grep -q ']9;'; then fail "TERMINAL_NOTIFY off → OSC 9 still present: $OUT"; else ok "TERMINAL_NOTIFY off → no OSC 9"; fi
if printf '%s' "$OUT" | jq -e '.terminalSequence' >/dev/null 2>&1; then ok "TERMINAL_NOTIFY off → terminalSequence present"; else fail "TERMINAL_NOTIFY off → no terminalSequence: $OUT"; fi
if [[ "$(bel_count "$OUT")" == "1" ]]; then ok "TERMINAL_NOTIFY off → 1 BEL (standalone bell only)"; else fail "TERMINAL_NOTIFY off → BEL count $(bel_count "$OUT"), want 1"; fi

# --- Case 9: both terminal channels off → silent stdout ---------------------
OUT="$(run "$(build_input permission_prompt)" \
  CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED=false CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED=false)"
if [[ -z "$OUT" ]]; then ok "both terminal channels off → silent stdout"; else fail "both off → stdout not empty: $OUT"; fi

# ============================================================================
# Telemetry (HOOK_TELEMETRY_SINK) tests
# ============================================================================

# --- Case 10: sink unset → stdout parity, no envelope leak ------------------
OUT="$(run "$(build_input permission_prompt)")"
if printf '%s' "$OUT" | jq -e '.terminalSequence' >/dev/null 2>&1; then ok "telemetry/unset: terminalSequence parity"; else fail "telemetry/unset: no terminalSequence: $OUT"; fi
if printf '%s' "$OUT" | jq -e '.schema_version' >/dev/null 2>&1; then fail "telemetry/unset: envelope leaked to hook stdout"; else ok "telemetry/unset: no envelope in hook stdout"; fi

# --- Case 11: stub sink → schema-valid envelope, status ok, channels --------
TEL="$(mktemp)"
STUB="$(make_sink "cat >\"$TEL\"")"
# Enable both terminal channels (os_toast still off) → channels = [terminal_notify, bell], status ok.
_OUT="$(run "$(build_input permission_prompt)" HOOK_TELEMETRY_SINK="$STUB")"
RC=$?
wait_for_sink "$TEL"
if [[ $RC -eq 0 ]]; then ok "telemetry/stub: hook exit 0"; else fail "telemetry/stub: hook exit $RC"; fi
if [[ -s "$TEL" ]]; then
  ok "telemetry/stub: envelope received"
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    if jq -e "has(\"$field\")" "$TEL" >/dev/null 2>&1; then ok "telemetry/envelope: $field present"; else fail "telemetry/envelope: $field missing: $(cat "$TEL")"; fi
  done
  if [[ "$(jq -r '.hook' "$TEL")" == "desktop-notification" ]]; then ok "telemetry/envelope: hook id"; else fail "telemetry/envelope: hook id = $(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.hook_event' "$TEL")" == "Notification" ]]; then ok "telemetry/envelope: hook_event Notification"; else fail "telemetry/envelope: hook_event = $(jq -r '.hook_event' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "telemetry/envelope: status ok"; else fail "telemetry/envelope: status = $(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.0" ]]; then ok "telemetry/envelope: schema_version 1.0"; else fail "telemetry/envelope: schema_version = $(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq -r '.data.notification_type' "$TEL")" == "permission_prompt" ]]; then ok "telemetry/envelope: data.notification_type"; else fail "telemetry/envelope: notification_type = $(jq -r '.data.notification_type' "$TEL")"; fi
  if jq -e '.data.channels | index("terminal_notify") and index("bell")' "$TEL" >/dev/null 2>&1; then ok "telemetry/envelope: channels has terminal_notify + bell"; else fail "telemetry/envelope: channels = $(jq -c '.data.channels' "$TEL")"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "telemetry/envelope: duration_ms non-negative integer"; else fail "telemetry/envelope: duration_ms = $(jq '.duration_ms' "$TEL")"; fi
else
  fail "telemetry/stub: no envelope written"
fi
rm -f "$TEL"

# --- Case 12: all channels off → status skipped, channels empty -------------
TEL="$(mktemp)"
STUB="$(make_sink "cat >\"$TEL\"")"
_OUT="$(run "$(build_input permission_prompt)" \
  CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED=false \
  CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED=false \
  HOOK_TELEMETRY_SINK="$STUB")"
wait_for_sink "$TEL"
if [[ -s "$TEL" ]]; then
  if [[ "$(jq -r '.status' "$TEL")" == "skipped" ]]; then ok "telemetry/skipped: status skipped when no channel fires"; else fail "telemetry/skipped: status = $(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.data.channels | length' "$TEL")" == "0" ]]; then ok "telemetry/skipped: channels empty"; else fail "telemetry/skipped: channels = $(jq -c '.data.channels' "$TEL")"; fi
else
  fail "telemetry/skipped: no envelope written"
fi
rm -f "$TEL"

# --- Case 13: slow sink (C1 fd1-leak detector) → hook returns << 3s ---------
SLOW="$(make_sink "cat >/dev/null; sleep 3")"
TS_START=$EPOCHREALTIME
# shellcheck disable=SC2034  # captured so $() blocks until fd1 closes — proves no fd1 leak
_OUT_SLOW="$(run "$(build_input permission_prompt)" HOOK_TELEMETRY_SINK="$SLOW")"
RC_SLOW=$?
TS_END=$EPOCHREALTIME
SS="${TS_START%[.,]*}" SF="${TS_START#*[.,]}"
ES="${TS_END%[.,]*}" EF="${TS_END#*[.,]}"
SLOW_MS=$(((ES * 1000000 + 10#$EF - SS * 1000000 - 10#$SF) / 1000))
echo "  (C1 slow-sink elapsed: ${SLOW_MS}ms)"
if [[ $RC_SLOW -eq 0 ]]; then ok "telemetry/slow-sink: hook exit 0"; else fail "telemetry/slow-sink: hook exit $RC_SLOW"; fi
if [[ $SLOW_MS -lt 2000 ]]; then ok "telemetry/slow-sink: returned in ${SLOW_MS}ms (<<3000 = no fd1 leak)"; else fail "telemetry/slow-sink: ${SLOW_MS}ms — fd1 leak blocks"; fi

# --- Case 14: failing sink → hook exit 0 unaffected -------------------------
FAIL_FILE="$(mktemp)"
FAIL_SINK="$(make_sink "cat >\"$FAIL_FILE\"; exit 1")"
# shellcheck disable=SC2034
_OUT_FS="$(run "$(build_input permission_prompt)" HOOK_TELEMETRY_SINK="$FAIL_SINK")"
RC_FS=$?
wait_for_sink "$FAIL_FILE"
if [[ $RC_FS -eq 0 ]]; then ok "telemetry/fail-sink: hook exit 0 despite sink failure"; else fail "telemetry/fail-sink: hook exit $RC_FS"; fi
rm -f "$FAIL_FILE"

# ============================================================================
# Security: untrusted .message / branch sanitization
# ============================================================================

# A hostile .message carrying: a leading dash, a double-quote, a raw ESC + OSC 9
# open + BEL (escape-smuggling attempt), a raw newline (statement-injection
# attempt), and a tab. build_input JSON-encodes the control bytes via jq --arg;
# the hook must strip them at parse time before any sink.
EVIL="$(printf -- '-danger"q\033]9;INJECTED\007mid\tafter\nline2')"

# --- Case 15: emitted terminalSequence carries only framing control bytes ----
# BELL off → the only legitimate control bytes are ONE framing ESC (\033, opens
# OSC 9) and ONE terminating BEL (\007). Any ESC/BEL/newline/tab from .message
# must be gone: esc==1, bel==1, and zero other C0 bytes.
OUT="$(run "$(build_input permission_prompt "$EVIL")" CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED=false)"
RC=$?
SEQ="$(jq -r '.terminalSequence' <<<"$OUT")"
ESC_N="$(printf '%s' "$SEQ" | tr -cd '\033' | wc -c | tr -d ' \r')"
BEL_N="$(printf '%s' "$SEQ" | tr -cd '\007' | wc -c | tr -d ' \r')"
OTHER_N="$(printf '%s' "$SEQ" | tr -d '\033\007' | tr -cd '\000-\037' | wc -c | tr -d ' \r')"
if [[ $RC -eq 0 ]]; then ok "sanitize/seq: exit 0"; else fail "sanitize/seq: exit $RC"; fi
if [[ "$ESC_N" == "1" ]]; then ok "sanitize/seq: exactly 1 ESC (framing only, no smuggled ESC)"; else fail "sanitize/seq: ESC count $ESC_N, want 1"; fi
if [[ "$BEL_N" == "1" ]]; then ok "sanitize/seq: exactly 1 BEL (OSC terminator only, no smuggled BEL)"; else fail "sanitize/seq: BEL count $BEL_N, want 1"; fi
if [[ "$OTHER_N" == "0" ]]; then ok "sanitize/seq: zero other C0 bytes (newline/tab stripped)"; else fail "sanitize/seq: $OTHER_N other C0 bytes remain"; fi
# Printable payload text survives (proves we stripped control bytes, not content).
if printf '%s' "$SEQ" | grep -q 'INJECTED'; then ok "sanitize/seq: printable text preserved"; else fail "sanitize/seq: over-stripped printable text: $SEQ"; fi

# --- Case 16: osascript receives text as argv, not interpolated program ------
# Stub uname→Darwin (force the macOS branch cross-platform) and osascript→capture
# argv + stdin program. Proves (a) HEADLINE/BODY arrive as argv items, (b) the
# AppleScript source (with "display notification") comes via stdin and never
# carries the message text, (c) the delivered BODY arg has no control bytes.
SHIM="$WORK/osa-shim"
mkdir -p "$SHIM"
OSA_LOG="$WORK/osa.log"
{ printf '#!/usr/bin/env bash\necho Darwin\n'; } >"$SHIM/uname"
{
  printf '#!/usr/bin/env bash\n'
  # Single quotes are intentional: $#/$@/$a must appear LITERALLY in the emitted
  # stub script, not expand here in the test.
  # shellcheck disable=SC2016
  printf '{ printf "ARGC=%%s\\n" "$#"; for a in "$@"; do printf "ARG=[%%s]\\n" "$a"; done; printf "PROG<<\\n"; cat; printf "\\n>>PROG\\n"; } >%q\n' "$OSA_LOG"
} >"$SHIM/osascript"
chmod +x "$SHIM/uname" "$SHIM/osascript"

IN_EVIL="$(build_input permission_prompt "$EVIL")"
(cd "$UNRELATED" && printf '%s' "$IN_EVIL" \
  | env -u HOOK_TELEMETRY_SINK -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED \
    -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED \
    CLAUDE_PROJECT_DIR="$FAKE_REPO" CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=true \
    CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED=true PATH="$SHIM:$PATH" \
    bash "$HOOK" >/dev/null 2>&1)
wait_for_sink "$OSA_LOG"

if grep -qx 'ARGC=3' "$OSA_LOG" 2>/dev/null; then ok "sanitize/osascript: 3 args (- + title + body)"; else fail "sanitize/osascript: ARGC wrong: $(cat "$OSA_LOG" 2>/dev/null)"; fi
if grep -qxF 'ARG=[Permission Required]' "$OSA_LOG" 2>/dev/null; then ok "sanitize/osascript: title passed as argv item"; else fail "sanitize/osascript: title not an argv item: $(cat "$OSA_LOG" 2>/dev/null)"; fi
# Body argv line: starts with the hostile leading dash, carries no control bytes.
BODY_LINE="$(grep -m1 '^ARG=\[-danger' "$OSA_LOG" 2>/dev/null)"
if [[ -n "$BODY_LINE" ]]; then ok "sanitize/osascript: body passed as argv item (leading dash intact, not an option)"; else fail "sanitize/osascript: body argv item missing: $(cat "$OSA_LOG" 2>/dev/null)"; fi
BODY_CTL="$(printf '%s' "$BODY_LINE" | tr -cd '\000-\037' | wc -c | tr -d ' \r')"
if [[ "$BODY_CTL" == "0" ]]; then ok "sanitize/osascript: body argv item has no control bytes"; else fail "sanitize/osascript: body argv item carries $BODY_CTL control bytes"; fi
# The AppleScript program came via stdin, and no ARG= line carries the program.
if grep '^ARG=' "$OSA_LOG" 2>/dev/null | grep -q 'display notification'; then fail "sanitize/osascript: program leaked into argv (interpolation!)"; else ok "sanitize/osascript: program not in argv"; fi
# The message text must NOT appear inside the stdin program (no interpolation).
PROG="$(sed -n '/^PROG<</,/^>>PROG/p' "$OSA_LOG" 2>/dev/null)"
if printf '%s' "$PROG" | grep -q 'danger'; then fail "sanitize/osascript: message text interpolated into program: $PROG"; else ok "sanitize/osascript: message text absent from program (argv-only)"; fi
if printf '%s' "$PROG" | grep -q 'display notification (item 2 of argv)'; then ok "sanitize/osascript: program reads body from argv"; else fail "sanitize/osascript: program shape unexpected: $PROG"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
