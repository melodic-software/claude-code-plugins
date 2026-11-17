#!/bin/sh
# shellcheck shell=bash
# spelling's side of lib/git-hooks/resolve-tool.sh: the ecosystem id whose
# record setup reports (hooks never run it), the files it acts on, and its
# typos adapter. Sourced by the lint git-hook entry.
#
# The adapter governs a file only when a typos config sits in its directory or
# above it, up to the repository root: typos.toml, _typos.toml, .typos.toml, a
# pyproject.toml with a [tool.typos] section, or a Cargo.toml with a
# [workspace.metadata.typos] or [package.metadata.typos] section, the files
# typos itself reads. typos comes from PATH. Lint reports and writes nothing.

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=spelling
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=spelling
SP_PYPROJECT='^[[:space:]]*\[tool\.typos(\]|[.])'
SP_CARGO='^[[:space:]]*\[(workspace|package)\.metadata\.typos(\]|[.])'
SP_INSTALL='cargo install typos-cli, or another method at https://github.com/crate-ci/typos#install'

# The plugin's bundled typos config, passed with -c so SHA-shaped hex is not
# read as a misspelling: beside an installed copy (an entry asset), or under
# config/ when run from the plugin itself. Exported: the adapter's command
# reads it.
SP_CONFIG="${here:-.}/default-typos.toml"
[[ -f "$SP_CONFIG" ]] || SP_CONFIG="${here:-.}/../config/default-typos.toml"
if [[ -f "$SP_CONFIG" ]]; then
  SP_CONFIG="$(cd "${SP_CONFIG%/*}" && pwd)/${SP_CONFIG##*/}"
else
  SP_CONFIG=""
fi
export SP_CONFIG

rt_wants() {
  case "$1" in
  .githooks/* | */.githooks/*) return 1 ;;
  *) return 0 ;;
  esac
}

# sp__config_name <dir>: 0 when a typos config is in <dir>; SP_NAME names it,
# in the order typos lists them.
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

# sp__walk <dir> <root>: 0 when a typos config is at <dir> or above it, up to
# <root>; SP_WALK_DIR is where it was found.
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

sp__dir() { # <file> <root>: the file's directory, absolute
  local f="$1"
  [[ "$f" == /* || "$f" == [A-Za-z]:[\\/]* ]] || f="$2/$f"
  [[ "$f" == */* ]] && f="${f%/*}"
  printf '%s' "$f"
}

sp__detail() { # <config dir> <root>
  local rel="${1#"$2"}"
  rel="${rel#/}"
  RT_DETAIL="config ${rel:+$rel/}$SP_NAME; binary typos on PATH"
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entry
rt_adapter() { # <concern> <file> <root>
  [[ "$1" == lint ]] || return 1
  sp__walk "$(sp__dir "$2" "$3")" "$3" || return 1
  sp__detail "$SP_WALK_DIR" "$3"
  RT_ADAPTER=typos RT_TOOL=typos RT_BIN=typos RT_DIR="$3" RT_INSTALL="$SP_INSTALL"
  RT_CONFIGS="typos.toml _typos.toml .typos.toml Cargo.toml pyproject.toml"
  # shellcheck disable=SC2016 # the command text sh -c expands, with RT_BIN, SP_CONFIG and the files
  RT_SCRIPT='"$RT_BIN" ${SP_CONFIG:+-c "$SP_CONFIG"} --force-exclude --format brief --color never -- "$@"'
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() { # <concern> <root>
  local f config_dir="$2"
  if [[ "$1" != lint ]]; then
    RT_DETAIL="spelling ships no $1 adapter"
    return 1
  fi
  if ! sp__config_name "$2"; then
    while IFS= read -r f; do
      config_dir="$2/${f%/*}"
      [[ "$f" == */* ]] || config_dir="$2"
      sp__config_name "$config_dir" && break
      f=""
    done < <(git -C "$2" ls-files -- ':(glob)**/typos.toml' ':(glob)**/_typos.toml' ':(glob)**/.typos.toml' \
      ':(glob)**/Cargo.toml' ':(glob)**/pyproject.toml' 2>/dev/null)
    if [[ -z "${f:-}" ]]; then
      RT_DETAIL="no typos config"
      return 1
    fi
  fi
  RT_ADAPTER=typos RT_TOOL=typos RT_BIN=typos
  sp__detail "$config_dir" "$2"
}

# sp_mirror <path>: a scratch tree holding the index copy of <path> at its own
# path, beside every typos config file on the way down from the top level, so
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

# rt_lint_index <path>: lint the staged copy of a partly staged file, or of
# one gone from the work tree, in a mirror tree that keeps the configs
# governing that path. Prints typos' output; returns its status.
rt_lint_index() {
  sp_mirror "$1"
  (cd "$CHECKS_TMP/mirror" && typos ${SP_CONFIG:+-c "$SP_CONFIG"} --force-exclude --format brief --color never -- "$1")
}
