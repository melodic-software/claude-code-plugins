#!/bin/sh
# shellcheck shell=bash
# python-format's side of lib/git-hooks/resolve-tool.sh: the ecosystem id it
# binds, the files it acts on, and its Ruff adapter. Sourced by the batch hook
# and both git-hook entries.
#
# The adapter governs a file only when a Ruff configuration sits in its
# directory or above it, up to the repository root (.ruff.toml, ruff.toml, or a
# pyproject.toml with a [tool.ruff] section). Ruff comes from a .venv the
# repository does not commit, walking up from the file, else PATH. Format sorts
# imports only where the repository's own lint config selects the import rules,
# then formats; lint reports and fixes nothing.

# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_PLUGIN=python-format
# shellcheck disable=SC2034 # read by resolve-tool.sh
RT_IDS=python
# shellcheck disable=SC2034 # read by the entries: the config names whose drift refuses a commit
RT_DRIFT_CONFIGS=".ruff.toml ruff.toml pyproject.toml"
PF_RUFF_SECTION='^[[:space:]]*\[tool\.ruff(\]|[.])'
PF_INSTALL='pip install ruff, or another method at https://docs.astral.sh/ruff/installation/'

rt_wants() {
  case "$1" in
  .githooks/* | */.githooks/*) return 1 ;;
  *.py | *.pyi) return 0 ;;
  *) return 1 ;;
  esac
}

pf__config_here() {
  [[ -f "$1/.ruff.toml" || -f "$1/ruff.toml" ]] && return 0
  [[ -f "$1/pyproject.toml" ]] && grep -qE "$PF_RUFF_SECTION" "$1/pyproject.toml" 2>/dev/null
}

# pf__walk <dir> <root> <predicate>: 0 when the predicate holds at <dir> or a
# directory above it, up to <root>.
pf__walk() {
  local dir="$1"
  while :; do
    "$3" "$dir" "$2" && return 0
    [[ "$dir" == "$2" || "$dir" != */* ]] && return 1
    dir="${dir%/*}"
    [[ -n "$dir" ]] || return 1
  done
}

# A .venv the repository commits is its code, not the user's install.
pf__venv_here() {
  local cand
  for cand in "$1/.venv/bin/ruff" "$1/.venv/Scripts/ruff.exe"; do
    if [[ -x "$cand" ]]; then
      [[ -z "$(git -C "$1" ls-files -- ':(literal).venv' 2>/dev/null)" ]] || return 1
      PF_BIN="$cand"
      return 0
    fi
  done
  return 1
}

pf__dir() { # <file> <root>: the file's directory, absolute
  local f="$1"
  [[ "$f" == /* || "$f" == [A-Za-z]:[\\/]* ]] || f="$2/$f"
  [[ "$f" == */* ]] && f="${f%/*}"
  printf '%s' "$f"
}

# pf__ruff <dir> <root>: sets RT_BIN, the venv ruff walking up from <dir>, else
# ruff on PATH. Cached per root.
pf__ruff() {
  if [[ "${PF_BIN_ROOT:-}" != "$2" ]]; then
    PF_BIN=ruff
    pf__walk "$1" "$2" pf__venv_here || PF_BIN=ruff
    PF_BIN_ROOT="$2"
  fi
  RT_BIN="$PF_BIN"
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh and the entries
rt_adapter() { # <concern> <file> <root>
  local dir
  dir="$(pf__dir "$2" "$3")"
  pf__walk "$dir" "$3" pf__config_here || return 1
  pf__ruff "$dir" "$3"
  RT_ADAPTER=ruff RT_TOOL=ruff RT_DIR="$3" RT_INSTALL="$PF_INSTALL"
  RT_CONFIGS=".ruff.toml ruff.toml pyproject.toml"
  case "$1" in
  format)
    RT_SCRIPT='"$RT_BIN" check --fix-only --fixable I --no-unsafe-fixes --force-exclude --no-cache --quiet -- "$@"; "$RT_BIN" format --force-exclude --no-cache --quiet -- "$@"'
    ;;
  *) RT_SCRIPT='"$RT_BIN" check --no-fix --output-format concise --force-exclude --no-cache --quiet -- "$@"' ;;
  esac
}

# shellcheck disable=SC2034 # RT_* are read by resolve-tool.sh
rt_adapter_in_repo() { # <concern> <root>
  local f
  if ! pf__config_here "$2"; then
    while IFS= read -r f; do
      [[ "${f##*/}" != pyproject.toml ]] && break
      grep -qE "$PF_RUFF_SECTION" "$2/$f" 2>/dev/null && break
      f=""
    done < <(git -C "$2" ls-files -- ':(glob)**/.ruff.toml' ':(glob)**/ruff.toml' ':(glob)**/pyproject.toml' 2>/dev/null)
    [[ -n "${f:-}" ]] || return 1
  fi
  pf__ruff "$2" "$2"
  RT_ADAPTER=ruff RT_TOOL=ruff
}

# rt_config_counts <config path>: 0 unless it is a pyproject.toml with no
# [tool.ruff] section in the work tree or the index, which Ruff does not read.
rt_config_counts() {
  [[ "${1##*/}" == pyproject.toml ]] || return 0
  grep -qE "$PF_RUFF_SECTION" "$1" 2>/dev/null && return 0
  grep -qE "$PF_RUFF_SECTION" < <(git show ":$1" 2>/dev/null)
}

# rt_lint_index <path>: lint the staged copy of a file gone from the work
# tree; --stdin-filename keeps the config and its excludes for that path.
rt_lint_index() {
  git show ":$1" 2>/dev/null |
    (cd "$RT_DIR" && "$RT_BIN" check --no-fix --output-format concise --force-exclude --no-cache --quiet --stdin-filename "$1" -)
  return "${PIPESTATUS[1]}"
}
