# GENERATED from lib/managed-scope.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# shellcheck shell=bash

mscope::base_file() {
  local override="${1:-}"
  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  case "$OSTYPE" in
  darwin*) printf '%s\n' "/Library/Application Support/ClaudeCode/managed-settings.json" ;;
  msys* | cygwin*) printf '%s\n' "${PROGRAMFILES:-C:\\Program Files}\\ClaudeCode\\managed-settings.json" ;;
  *) printf '%s\n' "/etc/claude-code/managed-settings.json" ;;
  esac
}

mscope::dropin_dir() {
  local base
  base="$(mscope::base_file "${1:-}")"
  printf '%s\n' "${base%managed-settings.json}managed-settings.d"
}

mscope::remote_cache_file() {
  local root="${1:-}"
  [[ -n "$root" ]] || return 0
  root="${root%/}"
  printf '%s\n' "$root/remote-settings.json"
}

mscope::registry_keys() {
  case "$OSTYPE" in
  msys* | cygwin*)
    # portability-ok: the `\S` here is the literal first character of SOFTWARE in
    printf '%s\n' 'HKLM\SOFTWARE\Policies\ClaudeCode' 'HKCU\SOFTWARE\Policies\ClaudeCode'
    ;;
  *) ;;
  esac
}

mscope::plist_domain() {
  case "$OSTYPE" in
  darwin*) printf '%s\n' "com.anthropic.claudecode" ;;
  *) ;;
  esac
}
