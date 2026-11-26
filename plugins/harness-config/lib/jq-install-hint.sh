# shellcheck shell=bash

jqhint::install_command() {
  case "${1:-}" in
  darwin*) printf 'brew install jq\n' ;;
  msys* | cygwin* | win32*) printf 'winget install jqlang.jq\n' ;;
  *)
    if command -v apt-get >/dev/null 2>&1; then
      printf 'sudo apt-get install jq\n'
    elif command -v dnf >/dev/null 2>&1; then
      printf 'sudo dnf install jq\n'
    elif command -v zypper >/dev/null 2>&1; then
      printf 'sudo zypper install jq\n'
    elif command -v pacman >/dev/null 2>&1; then
      printf 'sudo pacman -S jq\n'
    elif command -v brew >/dev/null 2>&1; then
      printf 'brew install jq\n'
    fi
    ;;
  esac
}

jqhint::missing_message() {
  local install
  install="$(jqhint::install_command "${2:-}")"
  printf 'ERROR: jq required. %s reads settings JSON with jq and stops without it.\n' "$1"
  if [[ -n "$install" ]]; then
    printf 'Install it: %s\n' "$install"
  fi
  printf 'Install commands for every platform: https://jqlang.org/download/\n'
  printf 'Then run /harness-ops:prerequisites to confirm the plugin prerequisites resolve.\n'
}
