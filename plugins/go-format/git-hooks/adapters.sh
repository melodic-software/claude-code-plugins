#!/bin/sh
# shellcheck shell=bash
# goimports -format-only: https://github.com/golang/tools/blob/master/cmd/goimports/goimports.go

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=go-format
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=go
GF_INSTALL='go install golang.org/x/tools/cmd/goimports@latest (needs a Go toolchain: https://go.dev/dl/)'
GF_LIST="${GF_LIST:-}"
GF_DETAIL='no config gate: formats every Go file'

rt_wants() {
  case "$1" in
  .githooks/*) return 1 ;;
  *.go) return 0 ;;
  *) return 1 ;;
  esac
}

gf_generated() {
  local line rest in_block=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    rest="${line#$'\xEF\xBB\xBF'}"
    while :; do
      if ((in_block)); then
        [[ "$rest" == *'*/'* ]] || continue 2
        rest="${rest#*\*/}"
        in_block=0
      fi
      rest="${rest#"${rest%%[![:space:]]*}"}"
      [[ -n "$rest" ]] || continue 2
      if [[ "$rest" == //* ]]; then
        [[ "$rest" =~ ^//\ Code\ generated\ .*\ DO\ NOT\ EDIT\.$ ]] && return 0
        continue 2
      fi
      [[ "$rest" == /\** ]] || return 1
      rest="${rest#/\*}"
      in_block=1
    done
  done <"$1"
  return 1
}

GF_PREFIX_DIRS=$'\n'
GF_PREFIX_VALS=()
gf__prefix() {
  local i=0 rest="${GF_PREFIX_DIRS#$'\n'}" mod=""
  while [[ -n "$rest" ]]; do
    if [[ "${rest%%$'\n'*}" == "$1" ]]; then
      GF_LOCAL="${GF_PREFIX_VALS[i]}"
      return 0
    fi
    rest="${rest#*$'\n'}"
    i=$((i + 1))
  done
  if command -v go >/dev/null 2>&1; then
    mod="$(cd "$1" 2>/dev/null && go list -m 2>/dev/null)" || mod=""
  fi
  [[ "$mod" == command-line-arguments || ! "$mod" =~ ^[A-Za-z0-9._~/+-]+$ ]] && mod=""
  GF_PREFIX_DIRS+="$1"$'\n'
  GF_PREFIX_VALS+=("$mod")
  GF_LOCAL="$mod"
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entry
rt_adapter() {
  [[ "$1" == format ]] || return 1
  local f="$2" dir
  [[ "$f" == /* || "$f" == [A-Za-z]:[\\/]* ]] || f="$3/$f"
  if [[ -f "$f" ]] && gf_generated "$f"; then
    RT_DETAIL="generated file"
    return 1
  fi
  dir="${f%/*}"
  gf__prefix "$dir"
  RT_ADAPTER=goimports RT_TOOL=goimports RT_BIN=goimports RT_DIR="$3" RT_INSTALL="$GF_INSTALL"
  RT_DETAIL="$GF_DETAIL"
  local mode=-w local=""
  [[ -n "$GF_LIST" ]] && mode=-l
  [[ -n "$GF_LOCAL" ]] && local=" -local '$GF_LOCAL'"
  # shellcheck disable=SC2016 # the command text sh -c expands, with RT_BIN and the files
  RT_SCRIPT='"$RT_BIN" -format-only '"$mode$local"' -- "$@"'
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() {
  [[ "$1" == format ]] || {
    RT_DETAIL="no shipped lint adapter"
    return 1
  }
  RT_ADAPTER=goimports RT_TOOL=goimports RT_BIN=goimports RT_DETAIL="$GF_DETAIL"
}
