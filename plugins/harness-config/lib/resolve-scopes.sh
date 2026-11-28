# shellcheck shell=bash

# printf -v, not a `local -n` nameref: namerefs need bash 4.3, and macOS ships bash 3.2.
# https://tiswww.case.edu/php/chet/bash/NEWS
scopes::project_root_to() {
  local _scopes_root
  if [[ -n "${2:-}" ]]; then
    printf -v "$1" '%s' "$2"
    return 0
  fi
  _scopes_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  _scopes_root="${_scopes_root//$'\r'/}"
  printf -v "$1" '%s' "${_scopes_root:-${CLAUDE_PROJECT_DIR:-$PWD}}"
}

scopes::user_dir_to() {
  printf -v "$1" '%s' "${2:-${CLAUDE_CONFIG_DIR:-${HOME:+$HOME/.claude}}}"
}

scopes::installed_registry_to() {
  printf -v "$1" '%s' "${2:-${3:+$3/plugins/installed_plugins.json}}"
}
