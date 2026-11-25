#!/usr/bin/env bash

set -uo pipefail
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

[[ "${CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED:-true}" == "true" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

# EPOCHREALTIME needs bash 5.0; it is unset on older bash.
# https://cgit.git.savannah.gnu.org/cgit/bash.git/plain/NEWS
start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT \
  '.notification_type // "unknown"' \
  '.message // "Needs your attention"' \
  '.title // ""' || exit 0

command -v jq >/dev/null 2>&1 || exit 0

strip_c0_to() {
  local __s="$2"
  if [[ "$__s" == *[[:cntrl:]]* ]]; then
    __s="${__s//[$'\001'-$'\037']/}"
  fi
  printf -v "$1" '%s' "$__s"
}

TYPE="${HOOK_JQ_FIELDS[0]:-}"
MESSAGE="${HOOK_JQ_FIELDS[1]:-}"
TITLE="${HOOK_JQ_FIELDS[2]:-}"
strip_c0_to TYPE "$TYPE"
strip_c0_to MESSAGE "$MESSAGE"
[[ -n "$TYPE" ]] || TYPE="unknown"
[[ -n "$MESSAGE" ]] || MESSAGE="Needs your attention"

case "$TYPE" in
permission_prompt)
  HEADLINE="Permission Required"
  DEFAULT_MSG="Needs your approval to continue"
  ;;
idle_prompt)
  HEADLINE="Input Needed"
  DEFAULT_MSG="Waiting for your input"
  ;;
plugin_notification)
  [[ "$TITLE" == "desktop-notification" ]] || exit 0
  HEADLINE="Claude Code"
  DEFAULT_MSG="Needs your attention"
  ;;
*) exit 0 ;;
esac

[[ "$MESSAGE" == "Needs your attention" ]] && MESSAGE="$DEFAULT_MSG"

REPO_ROOT=""
hook::repo_root_to REPO_ROOT "${CLAUDE_PROJECT_DIR:-.}"

CHANNELS=()

SEQ=""
if [[ "${CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED:-true}" == "true" ]]; then
  printf -v SEQ '\033]9;%s\007' "$HEADLINE: $MESSAGE"
  CHANNELS+=("terminal_notify")
fi
if [[ "${CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED:-true}" == "true" ]]; then
  SEQ+=$'\007'
  CHANNELS+=("bell")
fi

if [[ "${CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED:-true}" == "true" ]]; then
  BRANCH=$(hook::git_untrusted -C "$REPO_ROOT" branch --show-current 2>/dev/null) || BRANCH=""
  strip_c0_to BRANCH "$BRANCH"
  BODY="$MESSAGE"
  [[ -n "$BRANCH" ]] && BODY="$MESSAGE — $BRANCH"
  case "$(uname -s)" in
  Darwin)
    osascript - "$HEADLINE" "$BODY" >/dev/null 2>&1 <<'OSA' &
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
OSA
    CHANNELS+=("os_toast")
    ;;
  Linux)
    if command -v notify-send >/dev/null 2>&1; then
      # An unredirected background child keeps the hook running up to 10 seconds after it exits.
      # https://code.claude.com/docs/en/hooks
      notify-send -- "$HEADLINE" "$BODY" >/dev/null 2>&1 &
      CHANNELS+=("os_toast")
    elif [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v powershell.exe >/dev/null 2>&1; then
      T64=$(printf '%s' "$HEADLINE" | base64 -w0)
      B64=$(printf '%s' "$BODY" | base64 -w0)
      PS="\$d={param(\$s)[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(\$s))}
[Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime]|Out-Null
\$x=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
\$n=\$x.GetElementsByTagName('text')
\$n.Item(0).InnerText=(& \$d '$T64')
\$n.Item(1).InnerText=(& \$d '$B64')
\$app=('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}','WindowsPowerShell','v1.0','powershell.exe') -join [char]92
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$app).Show([Windows.UI.Notifications.ToastNotification]::new(\$x))"
      ENC=$(printf '%s' "$PS" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
      powershell.exe -NoProfile -NonInteractive -EncodedCommand "$ENC" </dev/null >/dev/null 2>&1 &
      CHANNELS+=("os_toast")
    fi
    ;;
  *) ;; # Windows / unknown — no OS toast; terminal channels carry attention.
  esac
fi

if [[ -n "$start" ]] && hook::telemetry_enabled; then
  ch_json=""
  status="skipped"
  if ((${#CHANNELS[@]})); then
    printf -v ch_json '"%s",' "${CHANNELS[@]}"
    status="ok"
  fi
  ch_json="[${ch_json%,}]"
  __nt=""
  hook::json_escape_jq_to __nt "$TYPE"
  data_json="{\"notification_type\":\"$__nt\",\"channels\":$ch_json}"
  hook::emit_telemetry "desktop-notification" "Notification" "$status" "$start" "$data_json" "$REPO_ROOT"
fi

if [[ -n "$SEQ" ]]; then
  __seq=""
  hook::json_escape_jq_to __seq "$SEQ"
  printf '{"terminalSequence":"%s"}\n' "$__seq"
fi
exit 0
