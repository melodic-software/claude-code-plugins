#!/usr/bin/env bash
# shellcheck shell=bash
# Shared config-root resolver for the layered `.claude/<surface>` cascade.
# Sourced by scripts; run directly for the model-run skills:
#
#   bash config-root.sh resolve            print the resolved root (empty when none)
#   bash config-root.sh classify [ROOT]    print repo | non-repo | home
#   bash config-root.sh same A B           exit 0 when A and B name one file or directory
#
# The root is CLAUDE_PROJECT_DIR, else `git rev-parse --show-toplevel`. The class:
#   home      the root is $HOME or an ancestor of it. A session started there
#             (machine maintenance, user-scope config) must not read
#             ~/.claude/<surface> as the team layer.
#   non-repo  no root, or a root outside any git working tree.
#   repo      anything else.
# Team and overlay layers apply only to `repo`. `home` wins over `repo`: a
# dotfiles checkout at $HOME is still home.

# Lowercase without `${x,,}`, which Bash 3.2 (stock macOS) rejects.
config_root_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# True when two paths name the same file or directory. Paths with one inode
# (a symlinked file or directory) match first. Existing directories
# compare via `pwd -P` (case-folded) so a native `C:/Users/<user>` and an MSYS
# `/c/Users/<user>` of the same home still match. Existing files compare by that
# physical parent plus the leaf. Missing paths compare after slash-folding,
# trailing-slash strip, and case-fold. Empty is never equal to anything.
# Never `cd` a file: that prints "Not a directory" on stderr.
config_root_paths_same() {
  local a="$1" b="$2" ap bp ad bd al bl
  [[ -n "$a" && -n "$b" ]] || return 1
  [[ "$a" -ef "$b" ]] && return 0
  if [[ -d "$a" && -d "$b" ]]; then
    if ap=$(cd "$a" 2>/dev/null && pwd -P) && bp=$(cd "$b" 2>/dev/null && pwd -P); then
      [[ "$(config_root_lower "$ap")" == "$(config_root_lower "$bp")" ]] && return 0
    fi
  elif [[ -f "$a" || -f "$b" ]]; then
    ad=$(cd "$(dirname -- "$a")" 2>/dev/null && pwd -P) || ad=""
    bd=$(cd "$(dirname -- "$b")" 2>/dev/null && pwd -P) || bd=""
    al=$(config_root_lower "${a##*/}")
    bl=$(config_root_lower "${b##*/}")
    [[ -n "$ad" && -n "$bd" && "$(config_root_lower "$ad")" == "$(config_root_lower "$bd")" && "$al" == "$bl" ]] && return 0
  fi
  a="${a//\\//}"; a=$(config_root_lower "${a%/}")
  b="${b//\\//}"; b=$(config_root_lower "${b%/}")
  [[ "$a" == "$b" ]]
}

# Print the resolved root: CLAUDE_PROJECT_DIR, else the git toplevel, else nothing.
config_root_resolve() {
  local root="${CLAUDE_PROJECT_DIR:-}"
  [[ -n "$root" ]] || root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  printf '%s\n' "$root"
}

# True when ROOT is $HOME or an ancestor of $HOME.
config_root_is_home_or_ancestor() {
  local root="$1" home="${HOME:-}" rp hp
  [[ -n "$root" && -n "$home" ]] || return 1
  config_root_paths_same "$root" "$home" && return 0
  rp=$(cd "$root" 2>/dev/null && pwd -P) || rp="$root"
  hp=$(cd "$home" 2>/dev/null && pwd -P) || hp="$home"
  rp="${rp//\\//}"; rp=$(config_root_lower "${rp%/}")
  hp="${hp//\\//}"; hp=$(config_root_lower "${hp%/}")
  [[ "$hp" == "$rp"/* ]]
}

# Print repo | non-repo | home for ROOT (default: the resolved root).
config_root_classify() {
  local root="${1:-}"
  [[ -n "$root" ]] || root="$(config_root_resolve)"
  if [[ -z "$root" ]]; then
    echo non-repo
  elif config_root_is_home_or_ancestor "$root"; then
    echo home
  elif [[ "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null)" == true ]]; then
    echo repo
  else
    echo non-repo
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    resolve) config_root_resolve ;;
    classify) config_root_classify "${2:-}" ;;
    same) config_root_paths_same "${2:-}" "${3:-}" ;;
    *)
      echo "usage: bash config-root.sh resolve | classify [ROOT] | same A B" >&2
      exit 2
      ;;
  esac
fi
