#!/usr/bin/env bash
# Binding discovery + validation for the work-item tracker seam (CONTRACT.md "Setup
# (binding file)"). Sourced — callers map failures to exit 3.

[[ -n "${_WIT_BINDING_LOADED:-}" ]] && return 0
readonly _WIT_BINDING_LOADED=1

# shellcheck source=labels.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/labels.sh"

# wit_project_root: the one repo-root anchor every seam resolution uses (CONTRACT.md
# "Setup (binding file)"). Fails outside a git repo with no CLAUDE_PROJECT_DIR.
wit_project_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null
}

# wit_find_binding: echo the binding file path. Never a CWD-upward climb: a stray
# ancestor or home binding would silently capture every repo beneath it (#2941).
wit_find_binding() {
  if [[ -n "${WORK_ITEM_TRACKER_BINDING:-}" ]]; then
    [[ -f "$WORK_ITEM_TRACKER_BINDING" ]] || return 1
    printf '%s\n' "$WORK_ITEM_TRACKER_BINDING"
    return 0
  fi
  local root
  root="$(wit_project_root)" || return 1
  [[ -f "$root/.work-item-tracker.json" ]] || return 1
  printf '%s\n' "$root/.work-item-tracker.json"
}

# The only keys the per-user overlay may refine; any other overlay key is a config
# error, never a merge (CONTRACT.md "Setup (binding file)").
readonly WIT_OVERLAY_ALLOWED_PATHS='[["config","lease_ttl_hours"],["config","lease_ttl_minutes"],["config","jira","auth_email"],["config","jira","auth_env"],["config","linear","auth_env"],["config","gitea","auth_env"],["docs"]]'

# wit_find_overlay <binding-path>: echo the overlay path beside whatever binding
# resolved, or fail when none exists.
wit_find_overlay() {
  local dir
  dir="$(cd "$(dirname "$1")" && pwd)" || return 1
  [[ -f "$dir/.work-item-tracker.local.json" ]] || return 1
  printf '%s\n' "$dir/.work-item-tracker.local.json"
}

# wit_effective_binding_json <binding-path>: the team file merged with allowlisted
# overlay keys. A bad overlay fails loudly: it must never silently reshape team state.
wit_effective_binding_json() {
  local path="$1" overlay bad
  jq -e . "$path" >/dev/null 2>&1 || return 1
  if ! overlay="$(wit_find_overlay "$path")"; then
    jq -c . "$path"
    return 0
  fi
  if ! jq -e . "$overlay" >/dev/null 2>&1; then
    printf 'work-item-tracker: overlay %s is not valid JSON\n' "$overlay" >&2
    return 1
  fi
  # Each path must be an allowlisted SCALAR or an object prefix of one; a leaf-only check
  # lets {"provider":{}} through. Use any() equality: index() on an array is a subsequence search.
  bad="$(jq -c --argjson allowed "$WIT_OVERLAY_ALLOWED_PATHS" '
    . as $o
    | [paths]
    | map(select(. as $p
        | ((($o | getpath($p)) | type) as $t
           | ((any($allowed[]; . == $p) and $t != "object" and $t != "array")
              or ($t == "object"
                  and any($allowed[]; (length > ($p | length)) and (.[:($p | length)] == $p)))))
        | not))' "$overlay")"
  if [[ "$bad" != "[]" ]]; then
    printf 'work-item-tracker: overlay %s sets non-overlayable key(s) %s — only lease TTL and per-provider auth identity (jira, linear, gitea) may be personal; see CONTRACT.md "Setup (binding file)"\n' \
      "$overlay" "$bad" >&2
    return 1
  fi
  # Merge by PRESENCE, not non-null value: an explicit null merges and faces normal
  # validation, never a silent fallback to the team value.
  jq -c -s --argjson allowed "$WIT_OVERLAY_ALLOWED_PATHS" '
    .[0] as $team | .[1] as $o
    | [$o | paths(type != "object")] as $present
    | reduce ($allowed[] | . as $p | select(any($present[]; . == $p))) as $p
        ($team; setpath($p; $o | getpath($p)))' "$path" "$overlay"
}

# wit_role_label <path> <role> <default>: the configured label, or <default> when absent
# OR empty (jq's `//` alone would let a configured empty string win).
wit_role_label() {
  local configured
  configured="$(jq -r --arg role "$2" '.config.role_labels[$role] // empty' "$1")"
  printf '%s\n' "${configured:-$3}"
}

# wit_read_binding <path>: validate shape and export the WIT_* binding values.
# lease_ttl_hours is REQUIRED: defaults live in the binding, never in code.
wit_read_binding() {
  local path="$1" json version provider ttl storage human_gated autonomous_eligible recurring_maintenance container container_type minutes
  json="$(wit_effective_binding_json "$path")" || return 1
  version="$(jq -r '.schema_version // empty' <<<"$json")"
  [[ "$version" == 1.* ]] || return 1
  provider="$(jq -r '.provider // empty' <<<"$json")"
  [[ -n "$provider" ]] || return 1
  # The provider name becomes an adapter directory path: a bare segment only, so a
  # binding value can never traverse outside adapters/<provider>.
  [[ "$provider" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
  ttl="$(jq -r '.config.lease_ttl_hours // empty' <<<"$json")"
  [[ "$ttl" =~ ^[0-9]+$ ]] || return 1
  minutes="$(jq -r '.config.lease_ttl_minutes // 0' <<<"$json")"
  [[ "$minutes" =~ ^[0-9]+$ && "$minutes" -le 59 ]] || return 1
  storage="$(jq -r '.config.storage_dir // empty' <<<"$json")"
  if [[ "$provider" == "local-markdown" && -z "$storage" ]]; then
    return 1
  fi
  # A relative storage_dir is rooted at the binding's directory, never the caller's
  # CWD, so a verb run from a subdirectory reads the same store.
  if [[ -n "$storage" && "$storage" != /* ]]; then
    storage="$(cd "$(dirname "$path")" && pwd)/$storage"
  fi
  human_gated="$(wit_role_label "$path" "human-gated" "$WIT_DEFAULT_HUMAN_GATED_LABEL")"
  autonomous_eligible="$(wit_role_label "$path" "autonomous-eligible" "$WIT_DEFAULT_AUTONOMOUS_ELIGIBLE_LABEL")"
  recurring_maintenance="$(wit_role_label "$path" "recurring-maintenance" "$WIT_DEFAULT_RECURRING_MAINTENANCE_LABEL")"
  # A present non-string container_label is a config error, not a fallback: jq -r would
  # stringify it into a label no item carries, letting containers onto the frontier.
  container_type="$(jq -r '.config.container_label | type' "$path")"
  [[ "$container_type" == "null" || "$container_type" == "string" ]] || return 1
  container="$(jq -r '.config.container_label // empty' "$path")"
  container="${container:-$WIT_DEFAULT_CONTAINER_LABEL}"
  WIT_PROVIDER="$provider"
  WIT_LEASE_TTL_HOURS="$ttl"
  WIT_LEASE_TTL_MINUTES="$minutes"
  WIT_STORAGE_DIR="$storage"
  WIT_HUMAN_GATED_LABEL="$human_gated"
  WIT_AUTONOMOUS_ELIGIBLE_LABEL="$autonomous_eligible"
  WIT_RECURRING_MAINTENANCE_LABEL="$recurring_maintenance"
  WIT_CONTAINER_LABEL="$container"
  export WIT_PROVIDER WIT_LEASE_TTL_HOURS WIT_LEASE_TTL_MINUTES WIT_STORAGE_DIR WIT_HUMAN_GATED_LABEL \
    WIT_AUTONOMOUS_ELIGIBLE_LABEL WIT_RECURRING_MAINTENANCE_LABEL WIT_CONTAINER_LABEL
}
