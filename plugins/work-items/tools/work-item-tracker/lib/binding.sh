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
# WIT_LEASE_TTL_HOURS, WIT_STORAGE_DIR, WIT_HUMAN_GATED_LABEL. lease_ttl_hours is
# REQUIRED (all defaults live in the binding, never in code). storage_dir is
# required only for provider local-markdown.
wit_read_binding() {
  local path="$1" version provider ttl storage human_gated
  jq -e . "$path" >/dev/null 2>&1 || return 1
  version="$(jq -r '.schema_version // empty' "$path")"
  [[ "$version" == 1.* ]] || return 1
  provider="$(jq -r '.provider // empty' "$path")"
  [[ -n "$provider" ]] || return 1
  # Provider names route straight into an adapter directory path
  # (wit_resolve_adapter_dir); reject anything but a bare directory-segment
  # name so a binding value can never traverse outside adapters/<provider>.
  [[ "$provider" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
  ttl="$(jq -r '.config.lease_ttl_hours // empty' "$path")"
  [[ "$ttl" =~ ^[0-9]+$ ]] || return 1
  storage="$(jq -r '.config.storage_dir // empty' "$path")"
  if [[ "$provider" == "local-markdown" && -z "$storage" ]]; then
    return 1
  fi
  # A relative storage_dir is rooted against the binding file's own directory —
  # the project root wit_find_binding's climb resolved — never the caller's
  # CWD. Otherwise a verb invoked from a subdirectory reads/writes a different
  # store than the same verb invoked from the repo root.
  if [[ -n "$storage" && "$storage" != /* ]]; then
    storage="$(cd "$(dirname "$path")" && pwd)/$storage"
  fi
  # Canonical role "human-gated" (label-taxonomy.md); config.role_labels lets a
  # repo remap the literal label string. Absent key or entry falls back to the
  # shipped default so an unmigrated binding keeps today's behavior.
  human_gated="$(jq -r '.config.role_labels["human-gated"] // empty' "$path")"
  [[ -n "$human_gated" ]] || human_gated="needs-human"
  WIT_PROVIDER="$provider"
  WIT_LEASE_TTL_HOURS="$ttl"
  WIT_STORAGE_DIR="$storage"
  WIT_HUMAN_GATED_LABEL="$human_gated"
  export WIT_PROVIDER WIT_LEASE_TTL_HOURS WIT_STORAGE_DIR WIT_HUMAN_GATED_LABEL
}
