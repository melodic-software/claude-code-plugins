#!/bin/sh
# shellcheck shell=bash

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=spelling
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=spelling
SP_PYPROJECT='^[[:space:]]*\[tool\.typos(\]|[.])'
SP_CARGO='^[[:space:]]*\[(workspace|package)\.metadata\.typos(\]|[.])'
SP_INSTALL='cargo install typos-cli, or another method at https://github.com/crate-ci/typos#install'

SP_CONFIG="${here:-.}/default-typos.toml"
[[ -f "$SP_CONFIG" ]] || SP_CONFIG="${here:-.}/../config/default-typos.toml"
if [[ -f "$SP_CONFIG" ]]; then
  SP_CONFIG="$(cd "${SP_CONFIG%/*}" && pwd)/${SP_CONFIG##*/}"
else
  SP_CONFIG=""
fi
export SP_CONFIG

rt_wants() {
  return 0
}

sp__config_name() {
  for SP_NAME in typos.toml _typos.toml .typos.toml; do
    [[ -f "$1/$SP_NAME" ]] && return 0
  done
  SP_NAME=Cargo.toml
  [[ -f "$1/Cargo.toml" ]] && grep -qE "$SP_CARGO" "$1/Cargo.toml" 2>/dev/null && return 0
  SP_NAME=pyproject.toml
  [[ -f "$1/pyproject.toml" ]] && grep -qE "$SP_PYPROJECT" "$1/pyproject.toml" 2>/dev/null && return 0
  return 1
}

sp__walk() {
  local dir="$1"
  while :; do
    SP_WALK_DIR="$dir"
    sp__config_name "$dir" && return 0
    [[ "$dir" == "$2" || "$dir" != */* ]] && return 1
    dir="${dir%/*}"
    [[ -n "$dir" ]] || return 1
  done
}

sp__dir() {
  local f="$1"
  [[ "$f" == /* || "$f" == [A-Za-z]:[\\/]* ]] || f="$2/$f"
  [[ "$f" == */* ]] && f="${f%/*}"
  printf '%s' "$f"
}

sp__detail() {
  local rel="${1#"$2"}"
  rel="${rel#/}"
  RT_DETAIL="config ${rel:+$rel/}$SP_NAME; binary typos on PATH"
}
sp__detail_none() {
  RT_DETAIL="no typos config: typos defaults plus the bundled config; binary typos on PATH"
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entry
rt_adapter() {
  [[ "$1" == lint ]] || return 1
  if sp__walk "$(sp__dir "$2" "$3")" "$3"; then
    sp__detail "$SP_WALK_DIR" "$3"
  else
    sp__detail_none
  fi
  RT_ADAPTER=typos RT_TOOL=typos RT_BIN=typos RT_DIR="$3" RT_INSTALL="$SP_INSTALL"
  RT_CONFIGS="typos.toml _typos.toml .typos.toml Cargo.toml pyproject.toml"
  # shellcheck disable=SC2016 # the command text sh -c expands, with RT_BIN, SP_CONFIG and the files
  RT_SCRIPT='"$RT_BIN" ${SP_CONFIG:+-c "$SP_CONFIG"} --force-exclude --format brief --color never -- "$@"'
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() {
  local f found=1 config_dir="$2"
  if [[ "$1" != lint ]]; then
    RT_DETAIL="spelling ships no $1 adapter"
    return 1
  fi
  if ! sp__config_name "$2"; then
    found=0
    while IFS= read -r f; do
      config_dir="$2/${f%/*}"
      [[ "$f" == */* ]] || config_dir="$2"
      sp__config_name "$config_dir" && found=1 && break
    done < <(git -C "$2" ls-files -- ':(glob)**/typos.toml' ':(glob)**/_typos.toml' ':(glob)**/.typos.toml' \
      ':(glob)**/Cargo.toml' ':(glob)**/pyproject.toml' 2>/dev/null)
  fi
  RT_ADAPTER=typos RT_TOOL=typos RT_BIN=typos
  if ((found)); then
    sp__detail "$config_dir" "$2"
  else
    sp__detail_none
  fi
}

# the repository's excludes and nested configs govern it as they do the file.
# shellcheck disable=SC2154 # CHECKS_TMP is set by check-lib.sh's checks_init
sp_mirror() {
  local f="$1" root="$CHECKS_TMP/mirror" rel="." rest="$1" name
  rm -rf "${root:?}"
  mkdir -p "$root"
  while :; do
    for name in typos.toml _typos.toml .typos.toml Cargo.toml pyproject.toml; do
      [[ -f "$rel/$name" ]] && cp "$rel/$name" "$root/$rel/$name"
    done
    [[ "$rest" == */* ]] || break
    rel="$rel/${rest%%/*}"
    rest="${rest#*/}"
    mkdir -p "$root/$rel"
  done
  git show ":$f" >"$root/$f" 2>/dev/null
}

rt_lint_index() {
  sp_mirror "$1"
  (cd "$CHECKS_TMP/mirror" && typos ${SP_CONFIG:+-c "$SP_CONFIG"} --force-exclude --format brief --color never -- "$1")
}
