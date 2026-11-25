# shellcheck shell=bash

# Read by both sourcing scripts, which is why shellcheck sees no use here.
# shellcheck disable=SC2034
CFV_CACHE_WINDOW_MIN=1440

cfv_cache_dir_to() {
  if [[ -n "${LOCALAPPDATA:-}" ]]; then
    printf -v "$1" '%s' "${LOCALAPPDATA//\\//}/guardrails/cli-flag-cache"
  else
    printf -v "$1" '%s' "${XDG_CACHE_HOME:-$HOME/.cache}/guardrails/cli-flag-cache"
  fi
}

cfv_cache_key_to() {
  local cfv__var="$1" cfv__key="$2" cfv__s
  shift 2
  for cfv__s in "$@"; do
    cfv__key="${cfv__key}__${cfv__s}"
  done
  printf -v "$cfv__var" '%s' "${cfv__key//[^a-zA-Z0-9_-]/_}"
}

cfv_global_chain_to() {
  case "$2" in
  az) printf -v "$1" '%s' version ;;
  *) printf -v "$1" '%s' "" ;;
  esac
}

cfv_flag_pattern_to() {
  printf -v "$1" '%s' "(^|[^a-zA-Z0-9_-])${2}([][:space:]=,|)[]|\$)"
}

cfv_flag_in_help() {
  local cfv__pat
  cfv_flag_pattern_to cfv__pat "$2"
  [[ "$1" =~ $cfv__pat ]]
}
