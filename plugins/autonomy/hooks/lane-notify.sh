# shellcheck shell=bash

[[ -n "${_LANE_NOTIFY_LOADED:-}" ]] && return 0
readonly _LANE_NOTIFY_LOADED=1

lane::notify() {
  [[ "${CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED:-true}" == "true" ]] || return 0

  local title body
  title=$(printf '%s' "$1" | tr -d '\000-\037')
  body=$(printf '%s' "$2" | tr -d '\000-\037')

  if [[ "${CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_TERMINAL_ENABLED:-true}" == "true" ]] &&
    [[ -w /dev/tty ]]; then
    printf '\033]9;%s\007\007' "$title: $body" >/dev/tty 2>/dev/null || true
  fi

  if [[ "${CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_OS_TOAST_ENABLED:-true}" == "true" ]]; then
    case "$(uname -s)" in
    Darwin)
      if command -v osascript >/dev/null 2>&1; then
        osascript - "$title" "$body" >/dev/null 2>&1 <<'OSA' &
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
OSA
      fi
      ;;
    Linux)
      if command -v notify-send >/dev/null 2>&1; then
        # An unredirected background child keeps the hook running up to 10 seconds after it exits.
        # https://code.claude.com/docs/en/hooks
        notify-send -- "$title" "$body" >/dev/null 2>&1 &
      fi
      ;;
    *) : ;;
    esac
  fi

  return 0
}
