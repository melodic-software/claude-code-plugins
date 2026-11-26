#!/usr/bin/env bash
cg::read_payload_to() {
  local __cg_dest="$1"
  case $__cg_dest in
    __cg_dest | __cg_input | __cg_chunk)
      printf 'cg::read_payload_to: destination %s is a reserved internal name\n' \
        "$__cg_dest" >&2
      return 2
      ;;
    *) ;;
  esac
  local __cg_input="" __cg_chunk=""
  if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))); then
    # read -N needs bash 4.1.
    # https://cgit.git.savannah.gnu.org/cgit/bash.git/plain/NEWS
    while IFS= read -r -N 1048576 -t 5 __cg_chunk; do
      __cg_input+="$__cg_chunk"
      __cg_chunk=""
    done
    __cg_input+="$__cg_chunk"
  else
    IFS= read -r -d '' -t 5 __cg_input || true
  fi
  __cg_input=${__cg_input//$'\r'/}
  [[ -n "$__cg_input" ]] || return 1
  printf -v "$__cg_dest" '%s' "$__cg_input"
}

cg::read_payload() {
  local __cg_buf=""
  cg::read_payload_to __cg_buf || return 1
  printf '%s' "$__cg_buf"
}
