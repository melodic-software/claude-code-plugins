#!/usr/bin/env bash

normalize_eol_read_supports_nchars() {
  ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1)))
}

normalize_eol_c_locale() {
  local had_lc=${LC_ALL+x} old_lc=${LC_ALL-} rc=0
  LC_ALL=C
  "$@" || rc=$?
  if [[ -n "$had_lc" ]]; then LC_ALL=$old_lc; else unset LC_ALL; fi
  return "$rc"
}

normalize_eol_read_window() {
  IFS= read -r -d '' -n 8000 chunk <"$1"
}

normalize_eol_is_binary() {
  local file="$1" nul_count chunk=""
  if normalize_eol_read_supports_nchars; then
    normalize_eol_c_locale normalize_eol_read_window "$file" && ((${#chunk} < 8000))
    return
  fi
  nul_count=$(head -c 8000 <"$file" | LC_ALL=C tr -dc '\0' | wc -c) || return 1
  [[ "$nul_count" -gt 0 ]]
}

normalize_eol_has_cr() {
  normalize_eol_read_supports_nchars || return 0
  normalize_eol_c_locale normalize_eol_scan_cr "$1"
}

normalize_eol_scan_cr() {
  local chunk=""
  while IFS= read -r -N 65536 chunk || [[ -n "$chunk" ]]; do
    [[ "$chunk" == *$'\r'* ]] && return 0
    [[ -n "$chunk" ]] || break
  done <"$1"
  return 1
}

normalize_eol_resolve_attrs() {
  NORMALIZE_EOL_ATTR_EOL=""
  NORMALIZE_EOL_ATTR_TEXT=""
  local raw line attr
  raw=$(git --no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$1" check-attr eol text -- "$2" 2>/dev/null) || return 0
  while IFS= read -r line; do
    attr="${line% *}"
    case "${attr##* }" in
    eol:) NORMALIZE_EOL_ATTR_EOL="${line##* }" ;;
    text:) NORMALIZE_EOL_ATTR_TEXT="${line##* }" ;;
    *) ;;
    esac
  done <<<"${raw//$'\r'/}"
  return 0
}

normalize_eol_plan() {
  local file="$2" action=skip needed=1
  if [[ -f "$file" ]]; then
    normalize_eol_resolve_attrs "$1" "$file"
    case "$NORMALIZE_EOL_ATTR_EOL" in
    lf | crlf)
      case "$NORMALIZE_EOL_ATTR_TEXT" in
      unset) ;;
      auto) normalize_eol_is_binary "$file" || action="$NORMALIZE_EOL_ATTR_EOL" ;;
      *) action="$NORMALIZE_EOL_ATTR_EOL" ;;
      esac
      ;;
    *) ;;
    esac
  fi
  case "$action" in
  lf) normalize_eol_has_cr "$file" || needed=0 ;;
  skip) needed=0 ;;
  *) ;;
  esac
  printf '%s %s' "$action" "$needed"
  return 0
}

normalize_eol_apply() {
  case "$1" in
  lf) normalize_eol_to_lf "$2" ;;
  crlf) normalize_eol_to_crlf "$2" ;;
  *) ;;
  esac
  return 0
}

normalize_eol_file() {
  local plan
  plan=$(normalize_eol_plan "$1" "$2")
  [[ "${plan##* }" == 1 ]] && normalize_eol_apply "${plan%% *}" "$2"
  printf '%s' "${plan%% *}"
  return 0
}

normalize_eol_rewrite_with() {
  local file="$1" tmp
  shift
  tmp=$(mktemp "${file}.XXXXXX") || return 0
  cp -p -- "$file" "$tmp" 2>/dev/null || true
  if "$@" <"$file" >"$tmp"; then
    mv -- "$tmp" "$file"
  else
    rm -f -- "$tmp"
  fi
}

normalize_eol_to_lf() {
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e 's/\r\n/\n/g' -- "$1"
  else
    normalize_eol_rewrite_with "$1" tr -d '\r'
  fi
}

normalize_eol_to_crlf() {
  if command -v perl >/dev/null 2>&1; then
    perl -pi -e 's/(?<!\r)\n/\r\n/g' -- "$1"
  else
    normalize_eol_rewrite_with "$1" awk 'BEGIN{RS="\r?\n"; ORS="\r\n"} {print}'
  fi
}
