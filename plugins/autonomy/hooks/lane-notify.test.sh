#!/usr/bin/env bash

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$LIB_DIR/lane-notify.sh"

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
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

wait_for() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

SHIM="$WORK/shim"
mkdir -p "$SHIM"
OSA_LOG="$WORK/osa.log"
printf '#!/usr/bin/env bash\necho Darwin\n' >"$SHIM/uname"
{
  printf '#!/usr/bin/env bash\n'
  # shellcheck disable=SC2016  # $#/$@/$a must stay literal in the emitted stub
  printf '{ printf "ARGC=%%s\\n" "$#"; for a in "$@"; do printf "ARG=[%%s]\\n" "$a"; done; printf "PROG<<\\n"; cat; printf "\\n>>PROG\\n"; } >%q\n' "$OSA_LOG"
} >"$SHIM/osascript"
chmod +x "$SHIM/uname" "$SHIM/osascript"

notify() {
  local title="$1" body="$2"
  shift 2
  : >"$OSA_LOG"
  # shellcheck disable=SC2016  # $1/$2/$3 below are the inner bash -c positionals; must NOT expand here
  (
    env -u CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED \
      -u CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_OS_TOAST_ENABLED \
      PATH="$SHIM:$PATH" \
      CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_TERMINAL_ENABLED=false \
      "$@" \
      bash -c 'source "$1"; lane::notify "$2" "$3"' _ "$LIB" "$title" "$body"
  ) >/dev/null 2>&1
}

notify "T" "B" CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false
sleep 0.1
if [[ -s "$OSA_LOG" ]]; then fail "master disabled → osascript still called: $(cat "$OSA_LOG")"; else ok "master disabled → no notification fired"; fi

notify "T" "B" CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=true CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_OS_TOAST_ENABLED=false
sleep 0.1
if [[ -s "$OSA_LOG" ]]; then fail "os_toast off → osascript still called"; else ok "os_toast channel off → no toast"; fi

notify "Autonomy lane stopped" "Lane foo (main) stopped" CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=true
wait_for "$OSA_LOG"
if grep -qx 'ARGC=3' "$OSA_LOG" 2>/dev/null; then ok "os_toast → 3 argv items (- + title + body)"; else fail "ARGC wrong: $(cat "$OSA_LOG" 2>/dev/null)"; fi
if grep -qxF 'ARG=[Autonomy lane stopped]' "$OSA_LOG" 2>/dev/null; then ok "title passed as argv item"; else fail "title not argv: $(cat "$OSA_LOG" 2>/dev/null)"; fi
if grep -qxF 'ARG=[Lane foo (main) stopped]' "$OSA_LOG" 2>/dev/null; then ok "body passed as argv item"; else fail "body not argv: $(cat "$OSA_LOG" 2>/dev/null)"; fi
PROG="$(sed -n '/^PROG<</,/^>>PROG/p' "$OSA_LOG" 2>/dev/null)"
if grep -q 'display notification (item 2 of argv)' <<<"$PROG"; then ok "program reads body from argv (no interpolation)"; else fail "program shape unexpected: $PROG"; fi
if grep -q 'stopped' <<<"$PROG"; then fail "body text interpolated into program"; else ok "body text absent from program"; fi

EVIL="$(printf 'lane\033]9;INJECT\007mid\nline2')"
notify "Autonomy lane stopped" "$EVIL" CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=true
wait_for "$OSA_LOG"
BODY_LINE="$(grep -m1 '^ARG=\[lane' "$OSA_LOG" 2>/dev/null)"
if [[ -n "$BODY_LINE" ]]; then ok "sanitized body delivered as argv item"; else fail "body argv missing: $(cat "$OSA_LOG" 2>/dev/null)"; fi
CTL="$(printf '%s' "$BODY_LINE" | tr -cd '\000-\037' | wc -c | tr -d ' \r')"
if [[ "$CTL" == "0" ]]; then ok "body argv item has zero control bytes"; else fail "body carries $CTL control bytes"; fi
if grep -q 'INJECT' <<<"$BODY_LINE"; then ok "printable text preserved (stripped bytes, not content)"; else fail "over-stripped: $BODY_LINE"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
