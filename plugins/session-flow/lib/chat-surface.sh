#!/usr/bin/env bash
# GENERATED from lib/chat-surface.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Prints the chat surface this session renders in, one of terminal, desktop, web or mobile, read
# from the names and values in chat-surface.env beside this file. Always exits 0; terminal when
# that file is missing or malformed.

unset CHAT_SURFACE_OVERRIDE_VAR CHAT_SURFACE_ENTRYPOINT_VAR CHAT_SURFACE_REMOTE_VAR \
  CHAT_SURFACE_REMOTE_VALUE CHAT_SURFACE_DESKTOP_ENTRYPOINTS CHAT_SURFACE_MOBILE_ENTRYPOINTS
# shellcheck source=/dev/null
. "${BASH_SOURCE[0]%/*}/chat-surface.env" 2>/dev/null || true

chat_surface::read() {
  local name="$1"
  [[ -n $name && $name != [0-9]* && $name != *[!A-Za-z0-9_]* ]] || return 0
  printf '%s' "${!name-}"
}

chat_surface::resolve() {
  local override entrypoint remote
  override="$(chat_surface::read "${CHAT_SURFACE_OVERRIDE_VAR-}")"
  case $override in
    terminal | desktop | web | mobile)
      printf '%s\n' "$override"
      return
      ;;
  esac
  entrypoint="$(chat_surface::read "${CHAT_SURFACE_ENTRYPOINT_VAR-}")"
  remote="$(chat_surface::read "${CHAT_SURFACE_REMOTE_VAR-}")"
  if [[ -n $entrypoint && " ${CHAT_SURFACE_DESKTOP_ENTRYPOINTS-} " == *" $entrypoint "* ]]; then
    printf 'desktop\n'
  elif [[ -n ${CHAT_SURFACE_REMOTE_VALUE-} && $remote == "$CHAT_SURFACE_REMOTE_VALUE" ]]; then
    if [[ -n $entrypoint && " ${CHAT_SURFACE_MOBILE_ENTRYPOINTS-} " == *" $entrypoint "* ]]; then
      printf 'mobile\n'
    else
      printf 'web\n'
    fi
  else
    printf 'terminal\n'
  fi
}

chat_surface::resolve
exit 0
