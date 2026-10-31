# shellcheck shell=bash
# The stop message for a script that needs jq and cannot find it, with the
# install command for this platform. Library only: no top-level execution.
#
# Builtins only: it runs on the path where a required tool is already missing,
# so it must not depend on anything else on PATH either. The commands are the
# ones https://jqlang.org/download/ lists (as of 2026-10-31; recheck when that
# page changes a command); the brew, winget and apt ones also match the jq
# entry in ../prerequisites.json.

# jqhint::install_command <ostype>: print the command that installs jq on this
# platform, or nothing when no package manager the download page names is found.
# <ostype> is bash's OSTYPE, passed in so a caller's test seam can pin it.
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

# jqhint::missing_message <script-name> <ostype>: the full stop message,
# for the caller to print on stderr before it exits 2.
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
