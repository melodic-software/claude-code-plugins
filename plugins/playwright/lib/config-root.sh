#!/usr/bin/env bash
# GENERATED from lib/config-root.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# shellcheck shell=bash

# tr, not ${x,,}: case-modifying expansions need bash 4.0, and these scripts support 3.2:
# https://tiswww.case.edu/php/chet/bash/NEWS
config_root_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

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

config_root_resolve() {
  local root="${CLAUDE_PROJECT_DIR:-}"
  [[ -n "$root" ]] || root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  printf '%s\n' "$root"
}

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
