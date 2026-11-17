#!/bin/sh
# shellcheck shell=bash

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=bash-format
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=bash
BF_SHFMT_INSTALL='see https://github.com/mvdan/sh#shfmt'
BF_SC_INSTALL='see https://github.com/koalaman/shellcheck#installing'

rt_wants() {
  case "$1" in
  .githooks/* | */.githooks/*) return 1 ;;
  *.sh | *.bash) return 0 ;;
  *) return 1 ;;
  esac
}

bf__shellcheckrc_here() {
  [[ -e "$1/.shellcheckrc" || -e "$1/shellcheckrc" ]]
}

bf__walk() {
  local dir="$1" rc
  while :; do
    BF_WALK_DIR="$dir"
    "$3" "$dir"
    rc=$?
    ((rc == 0)) && return 0
    ((rc == 2)) && return 1
    [[ "$dir" == "$2" || "$dir" != */* ]] && return 1
    dir="${dir%/*}"
    [[ -n "$dir" ]] || return 1
  done
}

bf__dir() {
  local f="$1"
  [[ "$f" == /* || "$f" == [A-Za-z]:[\\/]* ]] || f="$2/$f"
  [[ "$f" == */* ]] && f="${f%/*}"
  BF_DIR="$f"
}

# bf__set <concern> <config path, repo-relative> <root>: the adapter's RT_*.
# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entries
bf__set() {
  RT_DIR="$3"
  case "$1" in
  format)
    RT_ADAPTER=shfmt RT_TOOL=shfmt RT_BIN=shfmt RT_INSTALL="$BF_SHFMT_INSTALL"
    RT_CONFIGS=.editorconfig RT_SCRIPT=""
    RT_DETAIL="config $2; binary shfmt on PATH"
    ;;
  *)
    RT_ADAPTER=shellcheck RT_TOOL=shellcheck RT_BIN=shellcheck RT_INSTALL="$BF_SC_INSTALL"
    RT_CONFIGS=".shellcheckrc shellcheckrc"
    # shellcheck disable=SC2016 # the command text sh -c expands, with RT_BIN and the files
    RT_SCRIPT='"$RT_BIN" -x -f gcc -S warning -- "$@"'
    RT_DETAIL="config $2; binary shellcheck on PATH"
    ;;
  esac
}

bf__rel() {
  local rel="${1#"$2"}"
  rel="${rel#/}"
  BF_REL="${rel:+$rel/}$3"
}

rt_adapter() {
  bf__dir "$2" "$3"
  if [[ "$1" == format ]]; then
    bf__walk "$BF_DIR" "$3" editorconfig_shell_section_here || return 1
    bf__rel "$BF_WALK_DIR" "$3" .editorconfig
  elif bf__walk "$BF_DIR" "$3" bf__shellcheckrc_here; then
    bf__rel "$BF_WALK_DIR" "$3" .shellcheckrc
    [[ -e "$BF_WALK_DIR/.shellcheckrc" ]] || bf__rel "$BF_WALK_DIR" "$3" shellcheckrc
  else
    BF_REL="none (ShellCheck defaults)"
  fi
  bf__set "$1" "$BF_REL" "$3"
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() {
  local f=""
  if [[ "$1" == format ]]; then
    if editorconfig_shell_section_here "$2"; then
      f=.editorconfig
    else
      while IFS= read -r f; do
        [[ "$f" == */* ]] && editorconfig_shell_section_here "$2/${f%/*}" && break
        f=""
      done < <(git -C "$2" ls-files -- ':(glob)**/.editorconfig' 2>/dev/null)
    fi
    if [[ -z "$f" ]]; then
      RT_DETAIL="no .editorconfig section names shell files"
      return 1
    fi
  else
    if [[ -e "$2/.shellcheckrc" ]]; then
      f=.shellcheckrc
    elif [[ -e "$2/shellcheckrc" ]]; then
      f=shellcheckrc
    else
      f="$(git -C "$2" ls-files -- ':(glob)**/.shellcheckrc' ':(glob)**/shellcheckrc' 2>/dev/null | head -n 1)"
    fi
    [[ -n "$f" ]] || f="none (ShellCheck defaults)"
  fi
  bf__set "$1" "$f" "$2"
}
