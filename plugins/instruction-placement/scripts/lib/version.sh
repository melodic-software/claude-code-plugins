#!/usr/bin/env bash
ip_ver_ge() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ && "$2" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 2
  local -a a b
  local i x y
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  for i in 0 1 2; do
    x="${a[i]:-0}"
    y="${b[i]:-0}"
    ((10#$x > 10#$y)) && return 0
    ((10#$x < 10#$y)) && return 1
  done
  return 0
}

ip_ver_gt() {
  ip_ver_ge "$1" "$2" || return
  ! ip_ver_ge "$2" "$1"
}

ip_version_in() {
  [[ "$1" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && printf '%s' "${BASH_REMATCH[1]}"
  return 0
}

ip_mechanics_measured_max() {
  local file="$1" max="" marker rest v
  [[ -r "$file" ]] || return 0
  while IFS= read -r marker; do
    [[ "$marker" =~ (^|[^[:alnum:]-])measured([^,]*) ]] || continue
    rest="${BASH_REMATCH[2]}"
    while [[ "$rest" =~ ([0-9]+\.[0-9]+\.[0-9]+)(.*) ]]; do
      v="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
      if [[ -z "$max" ]] || ip_ver_gt "$v" "$max"; then max="$v"; fi
    done
  done < <(grep -oE '\*\([^)]*\)\*' "$file" 2>/dev/null)
  printf '%s' "$max"
}
