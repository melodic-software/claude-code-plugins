# shellcheck shell=bash
# Operator-notification primitive for the autonomy plugin's lane hooks. Sourced
# (not executed): defines lane::notify, which alerts a HUMAN at the current
# machine that a lane needs attention.
#
# Reach is deliberately local-only — an OS-native toast (macOS/Linux), plus a
# best-effort terminal bell + OSC 9 written straight to the controlling TTY. It
# reaches an operator AT THIS MACHINE. Off-machine transport does exist as
# first-party mechanisms, but its home is the consuming repo's settings, not
# this shell library — the loop-lane convention
# (docs/conventions/loop-lane/README.md in this plugin's marketplace repository)
# owns that seam and its verified grounding in §2. This primitive stays the local
# channel, and no hook-borne channel covers a closed laptop or a dead process —
# those emit no hook event at all.
#
# Why this reimplements — rather than sources — the desktop-notification
# plugin's script:
#   1. Emission mechanism differs by hook event. desktop-notification.sh is a
#      Notification-event hook: it returns its escape sequence in the
#      `terminalSequence` stdout field and relies on Claude Code to emit it.
#      A Stop hook's stdout is parsed for `decision`/`reason` — `terminalSequence`
#      is NOT part of the Stop output contract — so a Stop-context notifier must
#      write the escape to /dev/tty itself. That is a genuinely different code
#      path, not a lazy copy.
#   2. Installed plugins are cache-isolated and self-contained; there is no
#      supported way for the autonomy plugin to locate and source another
#      plugin's script at runtime.
#   3. desktop-notification is under an in-flight change; coupling to its
#      internals would add a cross-plugin drift/collision hazard.
#
# Config (consumer settings `env` / userConfig mirror; all channels default ON):
#   CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false            disable entirely
#   CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_OS_TOAST_ENABLED=false   mute the OS toast
#   CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_TERMINAL_ENABLED=false   mute bell + OSC 9

# Guard against double-sourcing.
[[ -n "${_LANE_NOTIFY_LOADED:-}" ]] && return 0
readonly _LANE_NOTIFY_LOADED=1

# lane::notify <title> <body>
# Fire the operator alert across every enabled channel. Best-effort and
# non-fatal: a missing tool or absent TTY silences that channel only, never
# fails the caller. Both arguments are treated as UNTRUSTED (a git branch or cwd
# can carry arbitrary bytes): all C0 control bytes are stripped before any sink,
# so an embedded ESC/BEL cannot smuggle terminal escapes into the OSC 9 write
# and a newline cannot inject an osascript statement.
lane::notify() {
  [[ "${CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED:-true}" == "true" ]] || return 0

  local title="$1" body="$2"
  title=$(printf '%s' "$title" | tr -d '\000-\037')
  body=$(printf '%s' "$body" | tr -d '\000-\037')

  # Terminal channel: OSC 9 desktop notification + a standalone bell, written
  # DIRECTLY to the controlling terminal. A Stop hook's stdout is captured and
  # parsed as JSON, so the escape cannot ride stdout — /dev/tty is the only
  # channel that reaches the user's terminal. Guarded on a writable /dev/tty: a
  # headless lane with no controlling terminal simply skips this channel. The
  # OSC 9 sequence is terminated by BEL (\007); a second BEL is the audible bell.
  if [[ "${CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_TERMINAL_ENABLED:-true}" == "true" ]] &&
    [[ -w /dev/tty ]]; then
    printf '\033]9;%s\007\007' "$title: $body" >/dev/tty 2>/dev/null || true
  fi

  # OS-native toast: self-backgrounded so the hook returns at once. CRITICAL:
  # each child's stdout is redirected off the hook's captured pipe
  # (>/dev/null 2>&1 &) — a bare `&` child inherits fd1, so Claude Code would
  # block for EOF until the spawn's timeout and the hook would hang.
  if [[ "${CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_OS_TOAST_ENABLED:-true}" == "true" ]]; then
    case "$(uname -s)" in
    Darwin)
      if command -v osascript >/dev/null 2>&1; then
        # Text passed via argv, NEVER interpolated into the AppleScript source:
        # `osascript -` reads the program from the quoted heredoc (nothing
        # expands); the trailing args populate `on run argv`.
        osascript - "$title" "$body" >/dev/null 2>&1 <<'OSA' &
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
OSA
      fi
      ;;
    Linux)
      if command -v notify-send >/dev/null 2>&1; then
        # `--` terminates option parsing so a title/body starting with `-` is a
        # positional, never an option flag.
        notify-send -- "$title" "$body" >/dev/null 2>&1 &
      fi
      ;;
    *) : ;; # Windows / unknown — no OS toast branch (a fire-and-forget process
      # leaves no live activator host for a WinRT toast); the terminal channel
      # above carries the attention (Windows Terminal honors OSC 9).
    esac
  fi

  return 0
}
