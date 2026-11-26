#!/bin/sh
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
      mkdir "$latch/$session" 2>/dev/null || exit 0
    }
  fi
  owner="${check#/}"
  owner="${owner%%:*}"
  case "$0" in
  */*) manifest="${0%/*}/../.claude-plugin/plugin.json" ;;
  *) manifest=../.claude-plugin/plugin.json ;;
  esac
  plugin=""
  [ -f "$manifest" ] && plugin=$(sed -n 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | sed -n 1p)
  plugin="${plugin:-$owner}"
  run="${check:-the plugin check skill}"
  [ -n "$owner" ] && [ "$owner" != "$plugin" ] && run="$run when $owner is enabled"
  msg="${plugin:-plugin}: node is not on PATH, so hooks that launch through node (this plugin's and others') do not run. Install Node.js (https://nodejs.org/en/download), restart Claude Code, then run ${run}."
  printf '{"systemMessage":"%s"}\n' "$msg"
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
