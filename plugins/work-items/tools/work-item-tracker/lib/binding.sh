#!/usr/bin/env bash
# Binding discovery + validation for the work-item tracker seam (CONTRACT.md "Setup
# (binding file)"). Sourced — callers map failures to exit 3.

[[ -n "${_WIT_BINDING_LOADED:-}" ]] && return 0
readonly _WIT_BINDING_LOADED=1

# wit_find_binding — echo the binding file path.
# Precedence: WORK_ITEM_TRACKER_BINDING env override, else climb from CWD toward the
# filesystem root and take the first .work-item-tracker.json.
wit_find_binding() {
  if [[ -n "${WORK_ITEM_TRACKER_BINDING:-}" ]]; then
    [[ -f "$WORK_ITEM_TRACKER_BINDING" ]] || return 1
    printf '%s\n' "$WORK_ITEM_TRACKER_BINDING"
    return 0
  fi
  local dir parent
  dir="$(pwd)"
  while :; do
    if [[ -f "$dir/.work-item-tracker.json" ]]; then
      printf '%s\n' "$dir/.work-item-tracker.json"
      return 0
    fi
    parent="$(dirname "$dir")"
    [[ "$parent" == "$dir" ]] && return 1
    dir="$parent"
  done
}

# wit_read_binding <path> — validate shape and export WIT_PROVIDER,
# WIT_LEASE_TTL_HOURS, WIT_STORAGE_DIR. lease_ttl_hours is REQUIRED (all defaults
# live in the binding, never in code). storage_dir is required only for
# provider local-markdown.
wit_read_binding() {
  local path="$1" version provider ttl storage
  jq -e . "$path" >/dev/null 2>&1 || return 1
  version="$(jq -r '.schema_version // empty' "$path")"
  [[ "$version" == 1.* ]] || return 1
  provider="$(jq -r '.provider // empty' "$path")"
  [[ -n "$provider" ]] || return 1
  ttl="$(jq -r '.config.lease_ttl_hours // empty' "$path")"
  [[ "$ttl" =~ ^[0-9]+$ ]] || return 1
  storage="$(jq -r '.config.storage_dir // empty' "$path")"
  if [[ "$provider" == "local-markdown" && -z "$storage" ]]; then
    return 1
  fi
  WIT_PROVIDER="$provider"
  WIT_LEASE_TTL_HOURS="$ttl"
  WIT_STORAGE_DIR="$storage"
  export WIT_PROVIDER WIT_LEASE_TTL_HOURS WIT_STORAGE_DIR
}
