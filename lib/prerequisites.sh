#!/bin/sh
# Run prerequisites.mjs from this directory with the same arguments and exit code.
# Without node on PATH, print one fixed line and exit 1, because the checker
# cannot run and node is itself a missing required dependency.
#
#   sh prerequisites.sh check <plugin-root> [--for <scope>]
#
# node-notice is the one mode that never needs node. A SessionStart hook runs it
# so a machine without node still hears about it:
#
#   sh prerequisites.sh node-notice <check-command> [<enabled-option-name>]
#
# With node on PATH it exits 0 and prints nothing. Without node it prints one
# SessionStart notice on both hook channels, then exits 0, because Claude Code
# reads hook JSON only from a zero exit. Every plugin's notice shares one latch
# keyed by session id in the temp directory, so a session sees it once. A
# plugin's kill switch (CLAUDE_PLUGIN_OPTION_<name>) set to anything but true
# silences it.
# shellcheck shell=sh disable=SC2154
if [ "${1:-}" = node-notice ]; then
  command -v node >/dev/null 2>&1 && exit 0
  check="${2:-}"
  case "${3:-}" in
  "") ;;
  *[!A-Z0-9_]*) ;;
  *)
    eval "enabled=\${CLAUDE_PLUGIN_OPTION_$3:-true}"
    [ "$enabled" = true ] || exit 0
    ;;
  esac
  session=no-session
  if [ ! -t 0 ]; then
    input=$(cat)
    id=$(printf '%s' "$input" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | tr -c 'A-Za-z0-9_\n-' '-')
    [ -n "$id" ] && session=$id
  fi
  if [ "$session" != no-session ]; then
    latch="${TMPDIR:-/tmp}/claude-plugins-node-missing"
    mkdir -p "$latch" 2>/dev/null && {
      find "$latch" -mindepth 1 -maxdepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null
      mkdir "$latch/$session" 2>/dev/null || exit 0
    }
  fi
  plugin="${check#/}"
  plugin="${plugin%%:*}"
  msg="${plugin:-plugin}: node is not on PATH, so the hooks of this plugin and of every other plugin that launches through node cannot start and do nothing. Install Node.js from https://nodejs.org/en/download and restart Claude Code. Run ${check:-the plugin check skill} to verify. This notice shows once per session."
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"WARNING: %s Tell the user."}}\n' "$msg" "$msg"
  exit 0
fi
if command -v node >/dev/null 2>&1; then
  case "$0" in
  */*) here="${0%/*}" ;;
  *) here=. ;;
  esac
  exec node "$here/prerequisites.mjs" "$@"
fi
echo "prerequisites: node was not found on PATH, so no prerequisite was checked. Install Node.js from https://nodejs.org/en/download, then run this check again."
exit 1
