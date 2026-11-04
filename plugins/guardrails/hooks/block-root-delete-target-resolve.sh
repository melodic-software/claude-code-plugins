#!/usr/bin/env bash
# Helpers for block-root-delete-target.sh that start no process of their own
# beyond the command they run. No call into the guard, so its test can source
# this file alone.

# rdt_bounded_to <var> <seconds> <command...>: run one external command with its
# stderr dropped and bound its whole life. <var> gets what `$(command)` would
# give, with every CR removed. Returns the command's exit status, 127 when there
# is no such command, or 124 when the time ran out, with the command killed.
# RDT_BOUND_UNSET, when the caller sets it, names variables the command starts
# without.
#
# The bound runs inside the command substitution, so output is read the way
# `$(...)` reads it. The command writes stdout to the substitution and holds a
# spare descriptor on a process substitution, which reaches end of file only
# when the command exits, closing its stdout or not; `read -t` on it is the
# bound. The process substitution execs the command, so `$!` is the command
# itself and the kill reaches it. A `wait` that cannot find the process answers
# 127, which must not read as a missing command, so it refuses as 124.
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
      kill -KILL "$__bt_pid" 2>/dev/null
      wait "$__bt_pid" 2>/dev/null
      exit 124
    }
    wait "$__bt_pid" || exit "$(($? == 127 ? 124 : $?))"
  ) || __bt_rc=$?
  printf -v "$__bt_dest" '%s' "${__bt_out//$'\r'/}"
  return "$__bt_rc"
}

# On Windows the guard resolves most paths with no process: rdt_phys_to stands
# in for `realpath -m` and rdt_win_to for `cygpath -l -m`. Each answers only
# where its answer is the process's answer, in the spelling the guard compares
# (rdt_canon_to), and returns 1 for everything else, which then takes the
# process. block-root-delete-target-resolve.test.sh compares the two on Git Bash.
# Both refuse: a backslash, a `~` (an 8.3 name the processes expand), a
# non-ASCII byte, a component ending in `.` or a space (names Windows folds),
# a UNC path, and a relative one.
rdt_cdp_plain() {
  local __cp_p="$1/" __cp_c
  [[ "$1" != *\\* && "$1" != *'~'* && "$1" != *[![:ascii:]]* && "$1" != //* ]] || return 1
  [[ "$1" == /* || "$1" =~ ^[A-Za-z]:/ ]] || return 1
  while [[ "$__cp_p" == */* ]]; do
    __cp_c="${__cp_p%%/*}"
    __cp_p="${__cp_p#*/}"
    [[ "$__cp_c" == . || "$__cp_c" == .. || "$__cp_c" != *[.\ ] ]] || return 1
  done
}

# rdt_phys_to <var> <absolute path>: what `realpath -m` prints for it on Git
# Bash, which keeps the spelling it is given and resolves only symlinks: the
# path collapsed lexically. That holds only while no part of the path is a
# symlink (MSYS reports a junction as one too), checked component by component
# as `realpath -m` walks it, so a `..` is never applied after a link. A `..`
# below a part that does not exist returns 1 as well.
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

# RDT_FIXED_DRIVES: the drive letters /proc/mounts lists as local NTFS or ReFS,
# read once. A network drive is left out, so no path on it is entered in the
# guard's own shell, where a stall would have no bound.
declare -A RDT_FIXED_DRIVES=()
RDT_FIXED_READ=0
rdt_fixed_drive() {
  local __fd_src __fd_mnt __fd_type __fd_rest
  if ((! RDT_FIXED_READ)); then
    RDT_FIXED_READ=1
    if [[ -r /proc/mounts ]]; then
      while read -r __fd_src __fd_mnt __fd_type __fd_rest; do
        [[ "$__fd_type" == ntfs || "$__fd_type" == refs ]] && [[ "$__fd_mnt" =~ ^/([a-z])$ ]] &&
          RDT_FIXED_DRIVES[${BASH_REMATCH[1]}]=1
      done </proc/mounts
    fi
  fi
  [[ -n "${RDT_FIXED_DRIVES[$1]+x}" ]]
}

# rdt_win_to <var> <absolute path>: what `cygpath -l -m` gives for the path's
# nearest existing ancestor, with the rest appended, as the guard maps it. One
# `cd -P` into that ancestor answers it, following a mount such as /tmp. It
# would follow a symlink or junction too, which cygpath does not, so a path
# rdt_phys_to declines (any link on it) is declined here as well. The ancestor
# is reached by an absolute path, so neither CDPATH nor a directory named `-`
# can redirect it, and the shell returns to where it was. Also returns 1 for an
# ancestor not on a local fixed drive and for a drive root.
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
