#!/usr/bin/env bash
rdt_bounded_to() {
  local __bt_dest="$1" __bt_limit="$2" __bt_out __bt_rc=0
  shift 2
  command -v "$1" >/dev/null 2>&1 || return 127
  __bt_out=$(
    exec 9>&1
    exec {__bt_fd}< <(
      # shellcheck disable=SC2154 # set by the caller, or not at all
      unset ${RDT_BOUND_UNSET[@]+"${RDT_BOUND_UNSET[@]}"}
      exec "$@" 2>/dev/null 3>&1 >&9 9>&-
    )
    __bt_pid=$!
    exec 9>&-
    IFS= read -r -t "$__bt_limit" -u "$__bt_fd" _ ||
      (($? <= 128)) || {
      rdt_kill_tree "$__bt_pid"
      wait "$__bt_pid" 2>/dev/null
      exit 124
    }
    wait "$__bt_pid" || exit "$(($? == 127 ? 124 : $?))"
  ) || __bt_rc=$?
  printf -v "$__bt_dest" '%s' "${__bt_out//$'\r'/}"
  return "$__bt_rc"
}

rdt_kill_tree() {
  local __kt_f __kt_l __kt_pid __kt_pp __kt_i=0
  local -a __kt_all=("$1")
  local -A __kt_kids=()
  kill -STOP "$1" 2>/dev/null
  for __kt_f in /proc/[0-9]*/stat; do
    IFS= read -r __kt_l 2>/dev/null <"$__kt_f" || continue
    __kt_pid="${__kt_l%% *}"
    __kt_l="${__kt_l##*) }"
    read -r _ __kt_pp _ <<<"$__kt_l"
    [[ "$__kt_pp" =~ ^[0-9]+$ ]] && __kt_kids[$__kt_pp]+=" $__kt_pid"
  done
  while ((__kt_i < ${#__kt_all[@]})); do
    for __kt_pid in ${__kt_kids[${__kt_all[__kt_i]}]-}; do __kt_all+=("$__kt_pid"); done
    __kt_i=$((__kt_i + 1))
  done
  kill -KILL "${__kt_all[@]}" 2>/dev/null
}

rdt_cdp_plain() {
  local __cp_p="$1/" __cp_c
  [[ "$1" != *\\* && "$1" != *'~'* && "$1" != *[![:ascii:]]* && "$1" != //* ]] || return 1
  [[ "$1" == /* || "$1" =~ ^[A-Za-z]:/ ]] || return 1
  rdt_local_path "$1" || return 1
  while [[ "$__cp_p" == */* ]]; do
    __cp_c="${__cp_p%%/*}"
    __cp_p="${__cp_p#*/}"
    [[ "$__cp_c" == . || "$__cp_c" == .. || "$__cp_c" != *[.\ ] ]] || return 1
  done
}

rdt_phys_to() {
  local __pt_p="$2" __pt_pre="" __pt_c __pt_missing=0 __pt_top
  local -a __pt_st=()
  rdt_cdp_plain "$__pt_p" || return 1
  if [[ "$__pt_p" =~ ^([A-Za-z]:)(/.*)$ ]]; then
    __pt_pre="${BASH_REMATCH[1]}"
    __pt_p="${BASH_REMATCH[2]}"
  fi
  __pt_p="${__pt_p#/}/"
  while [[ "$__pt_p" == */* ]]; do
    __pt_c="${__pt_p%%/*}"
    __pt_p="${__pt_p#*/}"
    case "$__pt_c" in
      '' | .) ;;
      ..)
        ((! __pt_missing)) || return 1
        ((${#__pt_st[@]})) && unset '__pt_st[${#__pt_st[@]}-1]'
        ;;
      *)
        __pt_top="$__pt_pre"
        ((${#__pt_st[@]})) && __pt_top="${__pt_st[${#__pt_st[@]} - 1]}"
        __pt_st+=("$__pt_top/$__pt_c")
        ((__pt_missing)) && continue
        [[ -L "$__pt_top/$__pt_c" ]] && return 1
        [[ -e "$__pt_top/$__pt_c" ]] || __pt_missing=1
        ;;
    esac
  done
  __pt_top="$__pt_pre/"
  ((${#__pt_st[@]})) && __pt_top="${__pt_st[${#__pt_st[@]} - 1]}"
  printf -v "$1" '%s' "$__pt_top"
}

declare -A RDT_FIXED_DRIVES=() RDT_MOUNT_DRIVE=()
RDT_FIXED_READ=0
rdt_read_mounts() {
  local __rm_src __rm_mnt __rm_type __rm_rest
  RDT_FIXED_READ=1
  [[ -r /proc/mounts ]] || return 0
  while read -r __rm_src __rm_mnt __rm_type __rm_rest; do
    if [[ "$__rm_mnt" =~ ^/([a-z])$ ]]; then
      [[ "$__rm_type" == ntfs || "$__rm_type" == refs ]] && RDT_FIXED_DRIVES[${BASH_REMATCH[1]}]=1
    elif [[ "$__rm_src" =~ ^([A-Za-z]): ]]; then
      RDT_MOUNT_DRIVE[$__rm_mnt]="${BASH_REMATCH[1],,}"
    else
      RDT_MOUNT_DRIVE[$__rm_mnt]=""
    fi
  done </proc/mounts
}
rdt_fixed_drive() {
  ((RDT_FIXED_READ)) || rdt_read_mounts
  [[ -n "$1" && -n "${RDT_FIXED_DRIVES[$1]+x}" ]]
}

rdt_local_path() {
  local __lp_m __lp_best=""
  if [[ "$1" =~ ^/([a-z])(/|$) || "$1" =~ ^([A-Za-z]): ]]; then
    rdt_fixed_drive "${BASH_REMATCH[1],,}"
    return
  fi
  ((RDT_FIXED_READ)) || rdt_read_mounts
  for __lp_m in "${!RDT_MOUNT_DRIVE[@]}"; do
    [[ "$1/" == "${__lp_m%/}/"* && ${#__lp_m} -gt ${#__lp_best} ]] && __lp_best="$__lp_m"
  done
  [[ -n "$__lp_best" ]] && rdt_fixed_drive "${RDT_MOUNT_DRIVE[$__lp_best]}"
}

rdt_win_to() {
  local __wt_a="$2" __wt_rest="" __wt_here="$PWD" __wt_old="${OLDPWD-}" __wt_d
  rdt_phys_to __wt_d "$__wt_a" || return 1
  [[ "$__wt_a" == *[!/]/ ]] && __wt_a="${__wt_a%/}"
  while [[ ! -e "$__wt_a" ]]; do
    [[ "$__wt_a" == */?* ]] || return 1
    __wt_rest="/${__wt_a##*/}$__wt_rest"
    __wt_a="${__wt_a%/*}"
  done
  [[ "$__wt_rest" != */../* && "$__wt_rest/" != */../ && "$__wt_rest" != */./* ]] || return 1
  builtin cd -P -- "$__wt_a" 2>/dev/null || return 1
  __wt_d="$PWD"
  builtin cd -- "$__wt_here" 2>/dev/null || return 1
  OLDPWD="$__wt_old"
  [[ "$__wt_d" =~ ^/([a-z])(/.+)$ ]] || return 1
  __wt_d="${BASH_REMATCH[1]^^}:${BASH_REMATCH[2]}"
  rdt_fixed_drive "${BASH_REMATCH[1]}" || return 1
  printf -v "$1" '%s' "$__wt_d$__wt_rest"
}
