#!/usr/bin/env bash
# shellcheck shell=bash

CONVENTION_KEY_YAML_REL="docs/conventions/source-control.yaml"
CONVENTION_KEY_LOCAL_REL="docs/conventions/source-control.local.yaml"
CONVENTION_KEY_OLD_LOCAL_REL=".claude/source-control.local.md"
CONVENTION_KEY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

convention_key_tracked() {
  git -C "$1" ls-files --error-unmatch -- "$2" >/dev/null 2>&1
}

convention_key_records() {
  local file="$1/${2:-$CONVENTION_KEY_YAML_REL}" text
  [[ -f "$file" ]] || return 0
  text="$(<"$file")"
  LC_ALL=C awk -v STRICT=1 -f "$CONVENTION_KEY_DIR/yaml-subset.awk" <<<"$text" 2>/dev/null || return 3
}

convention_key_yaml_value() {
  local records other_yaml_rel="${3:-}"
  records="$(convention_key_records "$1" "$other_yaml_rel")" || return 3
  PCV_KEY="$2" LC_ALL=C awk -F '\t' '$1 == ENVIRON["PCV_KEY"] && !seen++ { print substr($0, length($1) + 2) }' <<<"$records"
}

convention_key_yaml_list() {
  local records
  records="$(convention_key_records "$1" "${3:-}")" || return 3
  PCV_KEY="$2" LC_ALL=C awk -F '\t' 'index($1, ENVIRON["PCV_KEY"] ".") == 1 && substr($1, length(ENVIRON["PCV_KEY"]) + 2) ~ /^[0-9]+$/ { print substr($0, length($1) + 2) }' <<<"$records"
}

convention_key_old_files() {
  local repo_root_or_empty="$1" user="${HOME:-}/.claude/source-control.md"
  local root="$repo_root_or_empty"
  if [[ -n "$root" && -f "$root/$CONVENTION_KEY_OLD_LOCAL_REL" ]]; then
    printf '%s\t%s\n' "$root/$CONVENTION_KEY_OLD_LOCAL_REL" "$CONVENTION_KEY_LOCAL_REL"
  fi
  if [[ -n "${HOME:-}" && -f "$user" ]]; then
    printf '%s\t%s\n' "$user" "$CONVENTION_KEY_YAML_REL (team) or $CONVENTION_KEY_LOCAL_REL (personal), in each repository that needs it"
  fi
}

convention_key_yaml_has() {
  local root="$1" key="$2" scalar items
  scalar="$(convention_key_yaml_value "$root" "$key")" || return 3
  [[ -z "$scalar" ]] || return 0
  items="$(convention_key_yaml_list "$root" "$key")" || return 3
  [[ -n "$items" ]]
}

convention_key_layer() {
  convention_key_yaml_has "$1" "$2"
  case $? in
    0) echo yaml ;;
    3) return 3 ;;
    *) echo none ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    layer) convention_key_layer "${2:?root}" "${3:?key}" ;;
    value) convention_key_yaml_value "${2:?root}" "${3:?key}" ;;
    list) convention_key_yaml_list "${2:?root}" "${3:?key}" ;;
    local-value) convention_key_yaml_value "${2:?root}" "${3:?key}" "$CONVENTION_KEY_LOCAL_REL" ;;
    local-list) convention_key_yaml_list "${2:?root}" "${3:?key}" "$CONVENTION_KEY_LOCAL_REL" ;;
    old-files) convention_key_old_files "${2-}" ;;
    *)
      echo "usage: bash convention-key.sh layer|value|list|local-value|local-list ROOT KEY | old-files ROOT" >&2
      exit 2
      ;;
  esac
fi
