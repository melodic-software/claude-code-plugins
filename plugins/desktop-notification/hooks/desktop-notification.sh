#!/usr/bin/env bash
# Notification hook: cross-platform terminal/desktop alert when Claude Code needs input.
# Triggered on the permission_prompt and idle_prompt notification types.
#
# ADVISORY: always exits 0 — Notification hooks cannot block (they return
# terminalSequence output; exit 2 only shows stderr). Master kill switch
# HOOK_DESKTOP_NOTIFICATION_ENABLED gates the whole hook. When on, it emits up
# to three INDEPENDENTLY-gated channels (each default ON):
#   BELL            — audible terminal bell (bare BEL).
#   TERMINAL_NOTIFY — OSC 9 desktop notification (race-free, cross-platform;
#                     honored because the hook is synchronous — CC reads the
#                     terminalSequence field and emits the sequence on our
#                     behalf, including on Windows Terminal, which handles OSC 9).
#   OS_TOAST        — OS-native toast, self-backgrounded so the hook returns at
#                     once. macOS: osascript (built-in). Linux: notify-send
#                     (libnotify — apt install libnotify-bin / dnf install
#                     libnotify). Windows / other: no toast branch — a
#                     fire-and-forget process leaves no live activator host for a
#                     WinRT toast to render into, so terminal channels carry the
#                     attention (Windows Terminal honors the OSC 9 above).
# Channels are additive — enabling more stacks them.
#
# Config from the consumer's settings `env` block (all default ON when enabled):
#   HOOK_DESKTOP_NOTIFICATION_ENABLED=false                  disable entirely
#   HOOK_DESKTOP_NOTIFICATION_BELL_ENABLED=false             mute the bell
#   HOOK_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED=false  mute OSC 9
#   HOOK_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED=false         mute the OS toast

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "DESKTOP_NOTIFICATION"

# Capture $EPOCHREALTIME immediately after the kill switch so telemetry duration
# covers the hook's work. EPOCHREALTIME is Bash 5.0+; on older bash it is unset,
# so default to empty — referencing it bare under `set -u` would abort before the
# advisory exit 0. Empty start => telemetry is skipped, the hook still notifies.
start=${EPOCHREALTIME:-}

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT → silent no-op). stdin is read ONCE here and both fields are
# parsed from the buffered value; reading fd0 twice would drain the pipe.
INPUT=$(cat)

# Extract notification details; strip CR (Git Bash pipe output).
TYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // "unknown"' 2>/dev/null | tr -d '\r')
MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // "Needs your attention"' 2>/dev/null | tr -d '\r')
[[ -n "$TYPE" ]] || TYPE="unknown"
[[ -n "$MESSAGE" ]] || MESSAGE="Needs your attention"

# Map notification type to (headline, default-message). Exit on non-actionable
# types (no telemetry — same shape as a matcher miss). The default-message
# override only applies when the system supplied the generic placeholder.
case "$TYPE" in
  permission_prompt)
    HEADLINE="Permission Required"
    DEFAULT_MSG="Needs your approval to continue"
    ;;
  idle_prompt)
    HEADLINE="Input Needed"
    DEFAULT_MSG="Waiting for your input"
    ;;
  *) exit 0 ;;
esac

[[ "$MESSAGE" == "Needs your attention" ]] && MESSAGE="$DEFAULT_MSG"

# Consuming-repo root — used for the telemetry sink's relative-path resolution
# and (below) the optional git branch context on the OS toast body.
REPO_ROOT="$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")"

# Channels that actually fired, for the telemetry data payload.
CHANNELS=()

# Channels 1+2 — terminal-escape notification (race-free, cross-platform base).
# Built from two INDEPENDENT appends so each channel gates alone:
#   TERMINAL_NOTIFY → OSC 9 desktop notification. Its trailing BEL is the OSC
#     TERMINATOR, NOT the audible bell — it must always close the OSC 9 sequence,
#     so disabling BELL never strips it.
#   BELL → a standalone bare BEL (audible bell for any terminal).
# Deliberately NOT OSC 2 (window title): CC sets the terminal title to the
# session name, and an OSC 2 here would clobber it on every prompt.
SEQ=""
if [[ "${HOOK_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED:-true}" == "true" ]]; then
  SEQ+=$(printf '\033]9;%s\007' "$HEADLINE: $MESSAGE")
  CHANNELS+=("terminal_notify")
fi
if [[ "${HOOK_DESKTOP_NOTIFICATION_BELL_ENABLED:-true}" == "true" ]]; then
  SEQ+=$(printf '\007')
  CHANNELS+=("bell")
fi

# Channel 3 — OS-native toast (default on). Self-backgrounded so the hook
# returns immediately. CRITICAL: redirect each child's stdout off CC's capture
# pipe (>/dev/null 2>&1 &). A bare `&` child inherits fd1, so CC blocks for EOF
# until the spawn's startup timeout and the hook hangs. The redirect keeps fd1
# off the pipe; the hook's own terminalSequence JSON still reaches CC.
if [[ "${HOOK_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED:-true}" == "true" ]]; then
  # Optional git branch context for the toast body (generic; empty outside a
  # git repo → body is just the message).
  BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null | tr -d '\r')
  BODY="$MESSAGE"
  [[ -n "$BRANCH" ]] && BODY="$MESSAGE — $BRANCH"
  case "$(uname -s)" in
    Darwin)
      osascript -e "display notification \"$BODY\" with title \"$HEADLINE\"" >/dev/null 2>&1 &
      CHANNELS+=("os_toast")
      ;;
    Linux)
      if command -v notify-send >/dev/null 2>&1; then
        notify-send "$HEADLINE" "$BODY" >/dev/null 2>&1 &
        CHANNELS+=("os_toast")
      fi
      ;;
    *) ;; # Windows / unknown — no OS toast; terminal channels carry attention.
  esac
fi

# Telemetry (opt-in, HOOK_TELEMETRY_SINK). Built only when a sink is wired: the
# channels JSON + envelope cost a jq subprocess, never spent on the default path.
if [[ -n "$start" ]] && hook::telemetry_enabled; then
  if ((${#CHANNELS[@]})); then
    ch_json=$(printf '%s\n' "${CHANNELS[@]}" | jq -R . | jq -s . 2>/dev/null) || ch_json='[]'
    status="ok"
  else
    ch_json='[]'
    status="skipped"
  fi
  data_json=$(jq -nc --arg nt "$TYPE" --argjson channels "$ch_json" \
    '{notification_type:$nt,channels:$channels}' 2>/dev/null) \
    || data_json='{"notification_type":"","channels":[]}'
  hook::emit_telemetry "desktop-notification" "Notification" "$status" "$start" "$data_json" "$REPO_ROOT"
fi

# Emit terminalSequence LAST (final stdout write) and ONLY when non-empty: both
# terminal channels off → silent stdout, exit 0 — the same shape CC tolerates
# from the kill-switch path. jq -nc JSON-escapes the ESC/BEL control bytes; CC
# parses the JSON and emits the raw sequence for us.
if [[ -n "$SEQ" ]]; then
  jq -nc --arg seq "$SEQ" '{terminalSequence: $seq}'
fi
exit 0
