#!/bin/sh
# shellcheck shell=bash
# go-format's side of lib/git-hooks/resolve-tool.sh: the ecosystem id whose
# record setup reports (hooks never run it), the files it acts on, and its
# goimports adapter. Sourced by the batch hook and the format git-hook entry.
#
# The adapter has no config gate: goimports documents itself as a replacement
# for an editor's gofmt-on-save, so it formats every Go file the hooks see,
# except one whose leading comment block carries Go's `// Code generated ... DO
# NOT EDIT.` marker. It runs with -format-only: gofmt formatting plus import
# grouping and ordering, never adding or removing an import, which is a lint
# fix. The -local grouping prefix is the module path of the module holding the
# file (`go list -m`), so a repository's own imports keep their own group;
# without go or a module the default grouping applies. goimports comes from
# PATH. There is no lint adapter: /toolchain:lint runs a go record's lint-cmd.

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=go-format
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=go
GF_INSTALL='go install golang.org/x/tools/cmd/goimports@latest (needs a Go toolchain: https://go.dev/dl/)'
# GF_LIST=1 makes the format command list differing files instead of writing
# them: the entry's --worktree mode parses without rewriting.
GF_LIST="${GF_LIST:-}"
GF_DETAIL='no config gate: formats every Go file'

rt_wants() {
  case "$1" in
  .githooks/* | */.githooks/*) return 1 ;;
  *.go) return 0 ;;
  *) return 1 ;;
  esac
}

# gf_generated <path>: 0 when the file's leading comment and blank-line run
# holds the generated-code marker. The scan is a stand-in for go/ast.IsGenerated:
# it tracks /* */ blocks, tolerates a BOM and CRLF, and stops at the first text
# that is neither blank nor a comment, even when it follows a comment on the
# same line, as `/* license */ package p` does.
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

# gf__prefix <dir>: sets GF_LOCAL to the module path of the module holding
# <dir>, or empty. Cached per directory. A path outside Go's module-path
# characters (a go.work listing several modules, say) gives no prefix, so it is
# safe to place inside single quotes in the command text.
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
rt_adapter() { # <concern> <file> <root>
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
rt_adapter_in_repo() { # <concern> <root>
  [[ "$1" == format ]] || {
    RT_DETAIL="no shipped lint adapter"
    return 1
  }
  RT_ADAPTER=goimports RT_TOOL=goimports RT_BIN=goimports RT_DETAIL="$GF_DETAIL"
}
