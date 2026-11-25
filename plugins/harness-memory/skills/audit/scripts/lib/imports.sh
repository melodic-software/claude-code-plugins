#!/usr/bin/env bash

il_imports_of() {
  local file="$1" dir
  [[ -f "$file" ]] || return 0
  dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || return 0
  tr -d '\r' <"$file" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)
      gsub(/\\ /, "\001", line)
      n = split(line, tok, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        if (substr(tok[i], 1, 1) == "@" && length(tok[i]) > 1) {
          t = substr(tok[i], 2)
          c = substr(t, 1, 1)
          if (c == "\"" || c == "'"'"'") continue
          sub(/[.,;:)]+$/, "", t)
          gsub(/\001/, " ", t)
          if (t != "") print t
        }
      }
    }
  ' | while IFS= read -r target; do
    case "$target" in
    /*) printf '%s\n' "$target" ;;
    "~"/*) printf '%s\n' "${HOME}/${target#\~/}" ;;
    *) printf '%s\n' "$dir/$target" ;;
    esac
  done
}

il_realpath() {
  local p="${1:-}" dir base target hops=0
  [[ -n "$p" ]] || return 0
  if [[ ! -e "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  if [[ -d "$p" ]]; then
    (cd -P "$p" 2>/dev/null && pwd -P) || printf '%s' "$p"
    return 0
  fi
  dir="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P)" || {
    printf '%s' "$p"
    return 0
  }
  base="$(basename "$p")"
  while [[ -L "$dir/$base" ]] && ((hops < 32)); do
    target="$(readlink "$dir/$base" 2>/dev/null)" || break
    [[ -n "$target" ]] || break
    case "$target" in
    /*) dir="$(cd -P "$(dirname "$target")" 2>/dev/null && pwd -P)" || break ;;
    *) dir="$(cd -P "$dir/$(dirname "$target")" 2>/dev/null && pwd -P)" || break ;;
    esac
    base="$(basename "$target")"
    hops=$((hops + 1))
  done
  printf '%s/%s' "$dir" "$base"
}

il_reaches() {
  local from="$1" want="$2" depth="${3:-0}" imported real
  [[ -f "$from" ]] || return 1
  [[ "$(il_realpath "$from")" == "$want" ]] && return 0
  ((depth >= 4)) && return 1
  while IFS= read -r imported; do
    [[ -z "$imported" ]] && continue
    real="$(il_realpath "$imported")"
    [[ "$real" == "$want" ]] && return 0
    if [[ -f "$real" ]] && il_reaches "$real" "$want" $((depth + 1)); then
      return 0
    fi
  done < <(il_imports_of "$from")
  return 1
}

il_walk() {
  local file="$1" depth="${2:-0}" real imported ireal
  real="$(il_realpath "$file")"
  if ((depth == 0)); then
    printf 'root\t%s\n' "$real"
    IL_SEEN="|$real|"
  fi
  while IFS= read -r imported; do
    [[ -z "$imported" ]] && continue
    ireal="$(il_realpath "$imported")"
    if [[ "$IL_SEEN" == *"|$ireal|"* ]]; then
      printf 'seen\t%s\n' "$ireal"
      continue
    fi
    IL_SEEN="$IL_SEEN$ireal|"
    if [[ ! -f "$ireal" ]]; then
      printf 'missing\t%s\n' "$ireal"
      continue
    fi
    if [[ -n "${IL_ROOT:-}" && "$ireal" != "$IL_ROOT" && "$ireal" != "$IL_ROOT"/* ]]; then
      printf 'external\t%s\n' "$ireal"
      continue
    fi
    if ((depth + 1 > 4)); then
      printf 'depth\t%s\n' "$ireal"
      continue
    fi
    printf 'import\t%s\n' "$ireal"
    il_walk "$ireal" $((depth + 1))
  done < <(il_imports_of "$real")
}
