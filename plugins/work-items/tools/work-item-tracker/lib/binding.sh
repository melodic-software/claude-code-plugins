#!/usr/bin/env bash
# Binding discovery + validation for the work-item tracker seam (CONTRACT.md "Setup
# (binding file)"). Sourced — callers map failures to exit 3.

[[ -n "${_WIT_BINDING_LOADED:-}" ]] && return 0
readonly _WIT_BINDING_LOADED=1

# shellcheck source=labels.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/labels.sh"

# wit_project_root — echo the single repo-root anchor every seam resolution uses
# (binding read, adapter-dir resolution; CONTRACT.md "Setup (binding file)"):
# CLAUDE_PROJECT_DIR when set, else the git toplevel. Fails (return 1) outside a
# git repo with no CLAUDE_PROJECT_DIR — there is no root to anchor at.
wit_project_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null
}

# wit_find_binding — echo the binding file path.
# Precedence: WORK_ITEM_TRACKER_BINDING env override (tests/conformance), else
# .work-item-tracker.json at the repo root (wit_project_root). Deliberately NOT a
# CWD-to-filesystem-root climb: a stray ancestor/home binding would silently
# capture every repo beneath it (#2941). Nested per-subdirectory bindings are
# unsupported until requested.
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

# Overlay key allowlist (jq path array). The gitignored per-user overlay
# (.work-item-tracker.local.json, beside the team binding) may refine ONLY these
# keys — values that are coherent per-user: lease TTL travels inside each lease
# record, and jira auth identity is per-account. Everything else (provider,
# role_labels, container_label, storage_dir, jira.site/project_keys, ...) is
# shared coordination state and stays team-layer-only; an overlay value for any
# such key is a configuration error, never a merge (deny-by-default; CONTRACT.md
# "Setup (binding file)"). "docs" is the optional self-describing pointer either
# layer may carry.
readonly WIT_OVERLAY_ALLOWED_PATHS='[["config","lease_ttl_hours"],["config","lease_ttl_minutes"],["config","jira","auth_email"],["config","jira","auth_env"],["docs"]]'

# wit_find_overlay <binding-path> — echo the overlay path beside the binding, or
# fail when none exists. The overlay always lives beside whatever binding file
# resolved (repo root normally; the env override's directory under tests).
wit_find_overlay() {
  local dir
  dir="$(cd "$(dirname "$1")" && pwd)" || return 1
  [[ -f "$dir/.work-item-tracker.local.json" ]] || return 1
  printf '%s\n' "$dir/.work-item-tracker.local.json"
}

# wit_effective_binding_json <binding-path> — echo the effective binding JSON:
# the team file merged per-key with the allowlisted overlay keys. Overlay
# problems (unparsable, or a key outside the allowlist) print a specific stderr
# diagnostic and fail — a personal file must never silently reshape team
# coordination state. A missing overlay is the normal case: team JSON verbatim.
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
  # Every overlay path must be either an allowlisted path holding a SCALAR
  # (every allowlisted key is scalar-valued; an object or array there — e.g.
  # "auth_email": {} — would either dodge the merge or flow to a downstream
  # surface with no type check, so it is a named config error, not a value), or
  # an object-valued strict prefix of an allowlisted path (scaffolding like
  # {"config":{}} or {"config":{"jira":{}}} is inert). Checking leaves alone
  # would let a non-allowlisted key smuggle through as an empty object
  # ({"provider":{}}, {"config":{"role_labels":{}}}) — silently accepted
  # instead of the required configuration error. Membership must be element
  # equality (any), never index(): jq's index() on an array argument is a
  # subsequence search and would miss every allowlisted path.
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
    printf 'work-item-tracker: overlay %s sets non-overlayable key(s) %s — only lease TTL and jira auth identity may be personal; see CONTRACT.md "Setup (binding file)"\n' \
      "$overlay" "$bad" >&2
    return 1
  fi
  # Merge by PRESENCE, not by non-null value: an explicitly null allowlisted key
  # merges and is then judged by normal binding validation, exactly as if the
  # team file carried it — never a silent fallback to the team value (the same
  # rationale as the jira done_category_keys presence-read).
  jq -c -s --argjson allowed "$WIT_OVERLAY_ALLOWED_PATHS" '
    .[0] as $team | .[1] as $o
    | [$o | paths(type != "object")] as $present
    | reduce ($allowed[] | . as $p | select(any($present[]; . == $p))) as $p
        ($team; setpath($p; $o | getpath($p)))' "$path" "$overlay"
}

# wit_role_label <path> <role> <default> — echo the binding's configured label for
# a canonical role, or <default> when the key is absent OR configured empty. jq's
# `//` cannot carry the default on its own: it falls back on null/false only, so a
# configured empty string would win over the shipped default.
wit_role_label() {
  local configured
  configured="$(jq -r --arg role "$2" '.config.role_labels[$role] // empty' "$1")"
  if [[ -n "$configured" ]]; then
    printf '%s\n' "$configured"
  else
    printf '%s\n' "$3"
  fi
}

# wit_read_binding <path> — validate shape and export WIT_PROVIDER,
# WIT_LEASE_TTL_HOURS, WIT_STORAGE_DIR, WIT_HUMAN_GATED_LABEL,
# WIT_AUTONOMOUS_ELIGIBLE_LABEL, WIT_RECURRING_MAINTENANCE_LABEL,
# WIT_CONTAINER_LABEL. lease_ttl_hours is
# REQUIRED (all defaults live in the binding, never in code). storage_dir is
# required only for provider local-markdown.
wit_read_binding() {
  local path="$1" json version provider ttl storage human_gated autonomous_eligible recurring_maintenance container minutes
  # The effective view: team file merged with the allowlisted overlay keys
  # (lease TTL, jira auth identity). Team-only keys read identically from either
  # view; the reads below use the merged JSON so overlayable keys resolve
  # per-user where an overlay exists.
  json="$(wit_effective_binding_json "$path")" || return 1
  version="$(jq -r '.schema_version // empty' <<<"$json")"
  [[ "$version" == 1.* ]] || return 1
  provider="$(jq -r '.provider // empty' <<<"$json")"
  [[ -n "$provider" ]] || return 1
  # Provider names route straight into an adapter directory path
  # (wit_resolve_adapter_dir); reject anything but a bare directory-segment
  # name so a binding value can never traverse outside adapters/<provider>.
  [[ "$provider" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
  ttl="$(jq -r '.config.lease_ttl_hours // empty' <<<"$json")"
  [[ "$ttl" =~ ^[0-9]+$ ]] || return 1
  minutes="$(jq -r '.config.lease_ttl_minutes // 0' <<<"$json")"
  [[ "$minutes" =~ ^[0-9]+$ && "$minutes" -le 59 ]] || return 1
  storage="$(jq -r '.config.storage_dir // empty' <<<"$json")"
  if [[ "$provider" == "local-markdown" && -z "$storage" ]]; then
    return 1
  fi
  # A relative storage_dir is rooted against the binding file's own directory —
  # the repo root wit_find_binding anchored at — never the caller's CWD.
  # Otherwise a verb invoked from a subdirectory reads/writes a different
  # store than the same verb invoked from the repo root.
  if [[ -n "$storage" && "$storage" != /* ]]; then
    storage="$(cd "$(dirname "$path")" && pwd)/$storage"
  fi
  # Canonical roles (label-taxonomy.md); config.role_labels lets a repo remap the
  # literal label strings. Absent keys fall back to the shipped defaults, defined
  # once in lib/labels.sh.
  human_gated="$(wit_role_label "$path" "human-gated" "$WIT_DEFAULT_HUMAN_GATED_LABEL")"
  autonomous_eligible="$(wit_role_label "$path" "autonomous-eligible" "$WIT_DEFAULT_AUTONOMOUS_ELIGIBLE_LABEL")"
  recurring_maintenance="$(wit_role_label "$path" "recurring-maintenance" "$WIT_DEFAULT_RECURRING_MAINTENANCE_LABEL")"
  # Container marker: config.container_label (a sibling of config.role_labels,
  # not inside it — the container label marks a graph root, not a worker role).
  # Same configured-over-default resolution: absent or empty falls to the
  # shipped default (lib/labels.sh). A present non-string value is a
  # configuration error, not a fallback: jq -r would stringify a number/bool/
  # object into a label no item carries, silently letting containers onto the
  # frontier (label-taxonomy.md: malformed entries stop, never default).
  local container_type
  container_type="$(jq -r '.config.container_label | type' "$path")"
  [[ "$container_type" == "null" || "$container_type" == "string" ]] || return 1
  container="$(jq -r '.config.container_label // empty' "$path")"
  [[ -n "$container" ]] || container="$WIT_DEFAULT_CONTAINER_LABEL"
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
