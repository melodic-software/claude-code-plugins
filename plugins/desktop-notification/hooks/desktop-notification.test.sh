#!/usr/bin/env bash
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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

FAKE_REPO="$WORK/repo"
mkdir -p "$FAKE_REPO"
git -C "$FAKE_REPO" init -q
git -C "$FAKE_REPO" config user.email t@t.t
git -C "$FAKE_REPO" config user.name t
git -C "$FAKE_REPO" commit --allow-empty -m init -q

# shellcheck source=hook-test-sink.sh
source "$HOOK_DIR/hook-test-sink.sh"

build_input() {
  local type="$1" message="${2:-Needs your attention}"
  MSYS_NO_PATHCONV=1 jq -n --arg t "$type" --arg m "$message" \
    '{notification_type: $t, message: $m}'
}

run() {
  local input="$1"
  shift
  (cd "$UNRELATED" && printf '%s' "$input" |
    env -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED \
      -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED \
      -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED \
      -u HOOK_TELEMETRY_SINK \
      CLAUDE_PROJECT_DIR="$FAKE_REPO" \
      CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=true \
      CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED=false \
      "$@" \
      bash "$HOOK" 2>/dev/null)
}

bel_count() {
  jq -r '.terminalSequence' <<<"$1" | tr -cd '\007' | wc -c | tr -d ' \r'
}

ctl_count() {
  printf '%s' "$1" | tr -cd "$2" | wc -c | tr -d ' \r'
}

epoch_delta_ms() {
  local start="$1" end="$2" ss sf es ef
  ss="${start%[.,]*}" sf="${start#*[.,]}"
  es="${end%[.,]*}" ef="${end#*[.,]}"
  echo $(((es * 1000000 + 10#$ef - ss * 1000000 - 10#$sf) / 1000))
}

build_input permission_prompt >"$WORK/kill-switch.json"
OUT="$(cd "$UNRELATED" &&
  env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$FAKE_REPO" \
    CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=false bash "$HOOK" <"$WORK/kill-switch.json" 2>&1)"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch false → silent exit 0"; else fail "kill switch (rc=$RC out=$OUT)"; fi

OUT="$(run "$(build_input permission_prompt)")"
RC=$?
if [[ $RC -eq 0 ]]; then ok "permission_prompt exit 0"; else fail "permission_prompt exit $RC"; fi
if printf '%s' "$OUT" | jq -e '.terminalSequence' >/dev/null 2>&1; then
  ok "permission_prompt → terminalSequence, stdout parses as JSON"
else
  fail "permission_prompt → no terminalSequence JSON: $OUT"
fi
if grep -q ']9;' <<<"$OUT"; then ok "permission_prompt → OSC 9 present"; else fail "permission_prompt → OSC 9 missing: $OUT"; fi
if grep -q ']2;' <<<"$OUT"; then fail "permission_prompt → OSC 2 present (would clobber session title)"; else ok "permission_prompt → no OSC 2 title"; fi
if grep -qE ']1337|]8;' <<<"$OUT"; then fail "permission_prompt → rejected OSC present"; else ok "permission_prompt → no rejected OSC (1337/8)"; fi

OUT="$(run "$(build_input idle_prompt)")"
if printf '%s' "$OUT" | jq -e '.terminalSequence' >/dev/null 2>&1; then ok "idle_prompt → terminalSequence"; else fail "idle_prompt → no terminalSequence: $OUT"; fi

OUT="$(run "$(build_input auth_success)")"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "non-actionable type → silent exit 0"; else fail "non-actionable type (rc=$RC out=$OUT)"; fi

plugin_input() {
  MSYS_NO_PATHCONV=1 jq -n --arg t "$1" --arg m "$2" \
    '{notification_type: "plugin_notification", message: $m, title: $t}'
}
OUT="$(run "$(plugin_input desktop-notification 'build finished')")"
if grep -q ']9;Claude Code: build finished' < <(jq -r '.terminalSequence' <<<"$OUT" 2>/dev/null); then
  ok "plugin_notification titled desktop-notification → OSC 9 with the toast text"
else
  fail "plugin_notification titled desktop-notification → no OSC 9: $OUT"
fi
OUT="$(run "$(plugin_input other-mod 'build finished')")"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "plugin_notification from another mod → silent exit 0"; else fail "plugin_notification other title (rc=$RC out=$OUT)"; fi

OUT="$(cd "$UNRELATED" && env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$FAKE_REPO" \
  CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=true bash "$HOOK" </dev/null 2>&1)"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "empty stdin → silent exit 0"; else fail "empty stdin (rc=$RC out=$OUT)"; fi

OUT="$(run "$(build_input permission_prompt)")"
if grep -q ']9;' <<<"$OUT"; then ok "backward-compat → OSC 9 present"; else fail "backward-compat → OSC 9 missing: $OUT"; fi
if [[ "$(bel_count "$OUT")" == "2" ]]; then ok "backward-compat → 2 BELs (OSC terminator + standalone bell)"; else fail "backward-compat → BEL count $(bel_count "$OUT"), want 2"; fi

OUT="$(run "$(build_input permission_prompt)" CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED=false)"
if grep -q ']9;' <<<"$OUT"; then ok "BELL off → OSC 9 terminator intact"; else fail "BELL off → OSC 9 missing: $OUT"; fi
if [[ "$(bel_count "$OUT")" == "1" ]]; then ok "BELL off → 1 BEL (OSC terminator only)"; else fail "BELL off → BEL count $(bel_count "$OUT"), want 1"; fi

OUT="$(run "$(build_input permission_prompt)" CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED=false)"
if grep -q ']9;' <<<"$OUT"; then fail "TERMINAL_NOTIFY off → OSC 9 still present: $OUT"; else ok "TERMINAL_NOTIFY off → no OSC 9"; fi
if printf '%s' "$OUT" | jq -e '.terminalSequence' >/dev/null 2>&1; then ok "TERMINAL_NOTIFY off → terminalSequence present"; else fail "TERMINAL_NOTIFY off → no terminalSequence: $OUT"; fi
if [[ "$(bel_count "$OUT")" == "1" ]]; then ok "TERMINAL_NOTIFY off → 1 BEL (standalone bell only)"; else fail "TERMINAL_NOTIFY off → BEL count $(bel_count "$OUT"), want 1"; fi

OUT="$(run "$(build_input permission_prompt)" \
  CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED=false CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED=false)"
if [[ -z "$OUT" ]]; then ok "both terminal channels off → silent stdout"; else fail "both off → stdout not empty: $OUT"; fi


OUT="$(run "$(build_input permission_prompt)")"
if printf '%s' "$OUT" | jq -e '.terminalSequence' >/dev/null 2>&1; then ok "telemetry/unset: terminalSequence parity"; else fail "telemetry/unset: no terminalSequence: $OUT"; fi
if printf '%s' "$OUT" | jq -e '.schema_version' >/dev/null 2>&1; then fail "telemetry/unset: envelope leaked to hook stdout"; else ok "telemetry/unset: no envelope in hook stdout"; fi

TEL="$(mktemp)"
STUB="$(make_sink "cat >\"$TEL\"")"
_OUT="$(run "$(build_input permission_prompt)" HOOK_TELEMETRY_SINK="$STUB")"
RC=$?
wait_for_sink "$TEL"
if [[ $RC -eq 0 ]]; then ok "telemetry/stub: hook exit 0"; else fail "telemetry/stub: hook exit $RC"; fi
if [[ -s "$TEL" ]]; then
  ok "telemetry/stub: envelope received"
  if check_envelope "$TEL"; then ok "telemetry/envelope: matches envelope schema"; else fail "telemetry/envelope: does not match envelope schema. envelope=$(cat "$TEL")"; fi
  if [[ "$(jq -r '.hook' "$TEL")" == "desktop-notification" ]]; then ok "telemetry/envelope: hook id"; else fail "telemetry/envelope: hook id = $(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.hook_event' "$TEL")" == "Notification" ]]; then ok "telemetry/envelope: hook_event Notification"; else fail "telemetry/envelope: hook_event = $(jq -r '.hook_event' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "telemetry/envelope: status ok"; else fail "telemetry/envelope: status = $(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.1" ]]; then ok "telemetry/envelope: schema_version 1.1"; else fail "telemetry/envelope: schema_version = $(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq -r '.data.notification_type' "$TEL")" == "permission_prompt" ]]; then ok "telemetry/envelope: data.notification_type"; else fail "telemetry/envelope: notification_type = $(jq -r '.data.notification_type' "$TEL")"; fi
  if jq -e '.data.channels | index("terminal_notify") and index("bell")' "$TEL" >/dev/null 2>&1; then ok "telemetry/envelope: channels has terminal_notify + bell"; else fail "telemetry/envelope: channels = $(jq -c '.data.channels' "$TEL")"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "telemetry/envelope: duration_ms non-negative integer"; else fail "telemetry/envelope: duration_ms = $(jq '.duration_ms' "$TEL")"; fi
else
  fail "telemetry/stub: no envelope written"
fi
rm -f "$TEL"

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

SINK_SLEEP=8
SAFETY_MARGIN_MS=3000
BASE_SAMPLES=3
BASE_SINK="$(make_sink "cat >/dev/null")"
SLOW_SINK="$(make_sink "cat >/dev/null; sleep $SINK_SLEEP")"

BASE_MS=""
for ((_i = 0; _i < BASE_SAMPLES; _i++)); do
  _TS0=$EPOCHREALTIME
  # shellcheck disable=SC2034  # captured so $() blocks until fd1 closes (baseline overhead)
  _OUT_BASE="$(run "$(build_input permission_prompt)" HOOK_TELEMETRY_SINK="$BASE_SINK")"
  _TS1=$EPOCHREALTIME
  _b=$(epoch_delta_ms "$_TS0" "$_TS1")
  if [[ -z "$BASE_MS" || $_b -lt $BASE_MS ]]; then BASE_MS=$_b; fi
done

_TS0=$EPOCHREALTIME
# shellcheck disable=SC2034  # captured so $() blocks until fd1 closes, proving no fd1 leak
_OUT_SLOW="$(run "$(build_input permission_prompt)" HOOK_TELEMETRY_SINK="$SLOW_SINK")"
RC_SLOW=$?
_TS1=$EPOCHREALTIME
SLOW_MS=$(epoch_delta_ms "$_TS0" "$_TS1")

DELTA_MS=$((SLOW_MS - BASE_MS))
THRESHOLD_MS=$((SINK_SLEEP * 1000 - SAFETY_MARGIN_MS))
echo "  (C1 fd1-leak: base=${BASE_MS}ms (min of ${BASE_SAMPLES}) slow=${SLOW_MS}ms delta=${DELTA_MS}ms, threshold <${THRESHOLD_MS}ms, sink sleeps ${SINK_SLEEP}s)"
if [[ $RC_SLOW -eq 0 ]]; then ok "telemetry/slow-sink: hook exit 0"; else fail "telemetry/slow-sink: hook exit $RC_SLOW"; fi
if [[ $DELTA_MS -lt $THRESHOLD_MS ]]; then
  ok "telemetry/slow-sink: hook did not wait for the sink (delta ${DELTA_MS}ms << ${SINK_SLEEP}s sleep = no fd1 leak)"
else
  fail "telemetry/slow-sink: delta ${DELTA_MS}ms ≈ sink's ${SINK_SLEEP}s sleep — fd1 leak blocks \$() until the sink exits"
fi

FAIL_FILE="$(mktemp)"
FAIL_SINK="$(make_sink "cat >\"$FAIL_FILE\"; exit 1")"
# shellcheck disable=SC2034
_OUT_FS="$(run "$(build_input permission_prompt)" HOOK_TELEMETRY_SINK="$FAIL_SINK")"
RC_FS=$?
wait_for_sink "$FAIL_FILE"
if [[ $RC_FS -eq 0 ]]; then ok "telemetry/fail-sink: hook exit 0 despite sink failure"; else fail "telemetry/fail-sink: hook exit $RC_FS"; fi
rm -f "$FAIL_FILE"


EVIL="$(printf -- '-danger"q\033]9;INJECTED\007mid\tafter\nline2')"

OUT="$(run "$(build_input permission_prompt "$EVIL")" CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED=false)"
RC=$?
SEQ="$(jq -r '.terminalSequence' <<<"$OUT")"
ESC_N="$(ctl_count "$SEQ" '\033')"
BEL_N="$(ctl_count "$SEQ" '\007')"
OTHER_N="$(ctl_count "${SEQ//[$'\033'$'\007']/}" '\000-\037')"
if [[ $RC -eq 0 ]]; then ok "sanitize/seq: exit 0"; else fail "sanitize/seq: exit $RC"; fi
if [[ "$ESC_N" == "1" ]]; then ok "sanitize/seq: exactly 1 ESC (framing only, no smuggled ESC)"; else fail "sanitize/seq: ESC count $ESC_N, want 1"; fi
if [[ "$BEL_N" == "1" ]]; then ok "sanitize/seq: exactly 1 BEL (OSC terminator only, no smuggled BEL)"; else fail "sanitize/seq: BEL count $BEL_N, want 1"; fi
if [[ "$OTHER_N" == "0" ]]; then ok "sanitize/seq: zero other C0 bytes (newline/tab stripped)"; else fail "sanitize/seq: $OTHER_N other C0 bytes remain"; fi
if grep -q 'INJECTED' <<<"$SEQ"; then ok "sanitize/seq: printable text preserved"; else fail "sanitize/seq: over-stripped printable text: $SEQ"; fi

SHIM="$WORK/osa-shim"
mkdir -p "$SHIM"
OSA_LOG="$WORK/osa.log"
{ printf '#!/usr/bin/env bash\necho Darwin\n'; } >"$SHIM/uname"
{
  printf '#!/usr/bin/env bash\n'
  # $#/$@/$a must stay literal in the emitted stub script.
  # shellcheck disable=SC2016
  printf '{ printf "ARGC=%%s\\n" "$#"; for a in "$@"; do printf "ARG=[%%s]\\n" "$a"; done; printf "PROG<<\\n"; cat; printf "\\n>>PROG\\n"; } >%q\n' "$OSA_LOG"
} >"$SHIM/osascript"
chmod +x "$SHIM/uname" "$SHIM/osascript"

IN_EVIL="$(build_input permission_prompt "$EVIL")"
(cd "$UNRELATED" && printf '%s' "$IN_EVIL" |
  env -u HOOK_TELEMETRY_SINK -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED \
    -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED \
    CLAUDE_PROJECT_DIR="$FAKE_REPO" CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=true \
    CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED=true PATH="$SHIM:$PATH" \
    bash "$HOOK" >/dev/null 2>&1)
wait_for_sink "$OSA_LOG"

if grep -qx 'ARGC=3' "$OSA_LOG" 2>/dev/null; then ok "sanitize/osascript: 3 args (- + title + body)"; else fail "sanitize/osascript: ARGC wrong: $(cat "$OSA_LOG" 2>/dev/null)"; fi
if grep -qxF 'ARG=[Permission Required]' "$OSA_LOG" 2>/dev/null; then ok "sanitize/osascript: title passed as argv item"; else fail "sanitize/osascript: title not an argv item: $(cat "$OSA_LOG" 2>/dev/null)"; fi
BODY_LINE="$(grep -m1 '^ARG=\[-danger' "$OSA_LOG" 2>/dev/null)"
if [[ -n "$BODY_LINE" ]]; then ok "sanitize/osascript: body passed as argv item (leading dash intact, not an option)"; else fail "sanitize/osascript: body argv item missing: $(cat "$OSA_LOG" 2>/dev/null)"; fi
BODY_CTL="$(ctl_count "$BODY_LINE" '\000-\037')"
if [[ "$BODY_CTL" == "0" ]]; then ok "sanitize/osascript: body argv item has no control bytes"; else fail "sanitize/osascript: body argv item carries $BODY_CTL control bytes"; fi
if grep -q 'display notification' < <(grep '^ARG=' "$OSA_LOG" 2>/dev/null); then fail "sanitize/osascript: program leaked into argv (interpolation!)"; else ok "sanitize/osascript: program not in argv"; fi
PROG="$(sed -n '/^PROG<</,/^>>PROG/p' "$OSA_LOG" 2>/dev/null)"
if grep -q 'danger' <<<"$PROG"; then fail "sanitize/osascript: message text interpolated into program: $PROG"; else ok "sanitize/osascript: message text absent from program (argv-only)"; fi
if grep -q 'display notification (item 2 of argv)' <<<"$PROG"; then ok "sanitize/osascript: program reads body from argv"; else fail "sanitize/osascript: program shape unexpected: $PROG"; fi

NSHIM="$WORK/ns-shim"
mkdir -p "$NSHIM"
NS_LOG="$WORK/notify-send.log"
{ printf '#!/usr/bin/env bash\necho Linux\n'; } >"$NSHIM/uname"
{
  printf '#!/usr/bin/env bash\nlog=%q\n' "$NS_LOG"
  cat <<'EOF'
for a in "$@"; do printf 'ARG=[%s]\n' "$a"; done >"$log"
EOF
} >"$NSHIM/notify-send"
chmod +x "$NSHIM/uname" "$NSHIM/notify-send"
(cd "$UNRELATED" && printf '%s' "$IN_EVIL" |
  env -u HOOK_TELEMETRY_SINK -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED \
    -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED \
    CLAUDE_PROJECT_DIR="$FAKE_REPO" CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=true \
    CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED=true PATH="$NSHIM:$PATH" \
    bash "$HOOK" >/dev/null 2>&1)
wait_for_sink "$NS_LOG"
if [[ "$(head -n1 "$NS_LOG" 2>/dev/null)" == "ARG=[--]" ]] && grep -q '^ARG=\[-danger' "$NS_LOG" 2>/dev/null; then
  ok "sanitize/notify-send: option parsing ends before the dash-leading body"
else
  fail "sanitize/notify-send: a dash-leading body can act as an option: $(cat "$NS_LOG" 2>/dev/null)"
fi

if command -v notify-send >/dev/null 2>&1; then
  ok "wsl/powershell: skipped, notify-send is on PATH here"
else
  PSHIM="$WORK/ps-shim"
  mkdir -p "$PSHIM"
  PS_LOG="$WORK/ps.log"
  { printf '#!/usr/bin/env bash\necho Linux\n'; } >"$PSHIM/uname"
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >%q\n' "$PS_LOG" >"$PSHIM/powershell.exe"
  chmod +x "$PSHIM/uname" "$PSHIM/powershell.exe"
  (cd "$UNRELATED" && printf '%s' "$IN_EVIL" |
    env -u HOOK_TELEMETRY_SINK -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED \
      -u CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED \
      CLAUDE_PROJECT_DIR="$FAKE_REPO" CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=true \
      CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED=true WSL_DISTRO_NAME=Test PATH="$PSHIM:$PATH" \
      bash "$HOOK" >/dev/null 2>&1)
  wait_for_sink "$PS_LOG"
  if grep -qx -- '-EncodedCommand' "$PS_LOG" 2>/dev/null; then ok "wsl/powershell: program passed as -EncodedCommand"; else fail "wsl/powershell: args unexpected: $(cat "$PS_LOG" 2>/dev/null)"; fi
  PS_PROG="$(tail -n1 "$PS_LOG" 2>/dev/null | base64 -d 2>/dev/null | iconv -f UTF-16LE -t UTF-8 2>/dev/null)"
  if grep -q 'ToastText02' <<<"$PS_PROG"; then ok "wsl/powershell: program raises a toast"; else fail "wsl/powershell: program shape unexpected: $PS_PROG"; fi
  if grep -q 'danger' <<<"$PS_PROG"; then fail "wsl/powershell: message text in program source: $PS_PROG"; else ok "wsl/powershell: message text absent from program source"; fi
  mapfile -t PS_LITERALS < <(grep -o "(& \$d '[A-Za-z0-9+/=]*')" <<<"$PS_PROG" | sed "s/^(& \$d '//; s/')\$//")
  PS_TITLE="$(base64 -d <<<"${PS_LITERALS[0]:-}" 2>/dev/null)"
  PS_BODY="$(base64 -d <<<"${PS_LITERALS[1]:-}" 2>/dev/null)"
  if [[ "$PS_TITLE" == "Permission Required" ]]; then ok "wsl/powershell: title decodes from its literal"; else fail "wsl/powershell: title decoded as [$PS_TITLE]"; fi
  if [[ "$PS_BODY" == -danger* && "$(ctl_count "$PS_BODY" '\000-\037')" == "0" ]]; then ok "wsl/powershell: body decodes intact with no control bytes"; else fail "wsl/powershell: body decoded as [$PS_BODY]"; fi
fi

FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
JQ_DATA="$(mktemp -d "$WORK/plugdata.XXXXXX")"
run_nojq() {
  (
    cd "$UNRELATED" || return 1
    printf '{"session_id":"test-nojq-1","notification_type":"permission_prompt","message":"Needs your attention"}' |
      env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA" \
        CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED=true bash "$HOOK"
  )
}
OUT_NOJQ=$(run_nojq)
RC_NOJQ=$?
if [[ $RC_NOJQ -eq 0 && -z "$OUT_NOJQ" ]]; then
  ok "jq-absent -> exit 0 with no output (a Notification systemMessage is discarded)"
else
  fail "jq-absent (rc=$RC_NOJQ out=$OUT_NOJQ)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
