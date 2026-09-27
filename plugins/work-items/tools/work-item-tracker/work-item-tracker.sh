#!/usr/bin/env bash
# Core dispatcher for the work-item tracker seam. Contract: CONTRACT.md (verbs, JSON
# shapes, exit codes).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/binding.sh
source "$SCRIPT_DIR/lib/binding.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/lib/json.sh"
# shellcheck source=lib/frontier.sh
source "$SCRIPT_DIR/lib/frontier.sh"
# shellcheck source=lib/gh-version.sh
source "$SCRIPT_DIR/lib/gh-version.sh"

readonly EX_USAGE=2
readonly EX_CONFIG=3
readonly EX_CAPABILITY=6

# wit_resolve_adapter_dir <provider>: CONTRACT.md "Adapter resolution". When none
# exists the bundled path is echoed so the caller emits one not-found error.
wit_resolve_adapter_dir() {
  local provider="$1" root
  if [[ -n "${WIT_ADAPTERS_DIR:-}" ]]; then
    printf '%s\n' "$WIT_ADAPTERS_DIR/$provider"
    return 0
  fi
  if root="$(wit_project_root)"; then
    local local_dir="$root/tools/work-item-tracker/adapters/$provider"
    if [[ -d "$local_dir" ]]; then
      printf '%s\n' "$local_dir"
      return 0
    fi
  fi
  printf '%s\n' "$SCRIPT_DIR/adapters/$provider"
}

usage() {
  cat >&2 <<'EOF'
Usage: work-item-tracker.sh <verb> [args]
Verbs:
  create-item --title <t> [--body <b>] [--labels a,b] [--type <name>]
              [--parent <id>] [--blocked-by <id>[,<id>]] [--repo <owner>/<repo>]
  get-item <id>
  claim <id> [--ttl-hours <n>] [--session-id <s>]
  renew-lease <id> --lease-comment-id <n>
  reclaim <id>
  link-blocks <id> --blocked-by <id>
  add-sub-item <id> --parent <id>
  list-sub-items <parent-id> [--state open|closed|all]
  list-frontier [--autonomous] [--parent <container-id>] [--repo <owner>/<repo>]
  capabilities
Contract: tools/work-item-tracker/CONTRACT.md
EOF
}

fail_usage() {
  usage
  exit "$EX_USAGE"
}

fail_config() {
  printf 'work-item-tracker: %s\n' "$1" >&2
  exit "$EX_CONFIG"
}

# Presence is checked apart from version so a gh-less session gets a clean exit 3
# (CONTRACT.md "Degradation without gh"), not `gh: command not found` in an adapter.
check_gh_present() {
  command -v gh >/dev/null 2>&1 ||
    fail_config "prerequisite missing: gh (GitHub CLI) — see CONTRACT.md Prerequisites"
}

# check_gh_version [feature]: the flag or verb that needs 2.94, named in the exit-3
# message; the default covers verbs with no user-facing flag.
check_gh_version() {
  check_gh_present
  local feature="${1:-native sub-issue/dependency flags}"
  wit_gh_has_native_surface && return 0
  local raw
  raw="$(wit_gh_version_raw)"
  fail_config "gh >= ${WIT_GH_NATIVE_SURFACE_MAJOR}.${WIT_GH_NATIVE_SURFACE_MINOR} required for ${feature} (found: ${raw:-unknown})"
}

main() {
  local verb="${1:-}"
  if [[ "$verb" == "--help" || "$verb" == "-h" ]]; then
    usage 2>&1
    exit 0
  fi
  [[ -n "$verb" ]] || fail_usage
  shift

  command -v jq >/dev/null 2>&1 ||
    fail_config "prerequisite missing: jq — see CONTRACT.md Prerequisites"

  local binding_path
  binding_path="$(wit_find_binding)" ||
    fail_config "no binding found (.work-item-tracker.json) — see CONTRACT.md Setup"
  wit_read_binding "$binding_path" ||
    fail_config "invalid binding at $binding_path — run /work-items:setup check for the itemized breakdown; see CONTRACT.md Setup"

  local adapter_dir manifest
  adapter_dir="$(wit_resolve_adapter_dir "$WIT_PROVIDER")"
  [[ -d "$adapter_dir" ]] ||
    fail_config "no adapter for provider '$WIT_PROVIDER' (searched consumer-local then plugin-bundled) — last tried $adapter_dir"
  manifest="$adapter_dir/capabilities.json"
  [[ -f "$manifest" ]] ||
    fail_config "adapter '$WIT_PROVIDER' has no capabilities.json manifest"

  wit_check_contract_version "$WIT_PROVIDER" "$manifest" ||
    exit "$EX_CONFIG"

  # A consumer-local adapter's own ../../lib may not exist, so export THIS engine's
  # lib dir; only exported vars cross into `bash <verb>.sh`. Bundled adapters ignore it.
  export WIT_SEAM_LIB_DIR="$SCRIPT_DIR/lib"

  local adapter_verb="$verb"
  case "$verb" in
  create-item | get-item | claim | renew-lease | reclaim | link-blocks | add-sub-item | list-sub-items | capabilities) ;;
  list-frontier)
    # Chosen BEFORE the capability gate, so an adapter without list-sub-items
    # degrades with exit 6 on --parent instead of failing the scoped call.
    adapter_verb="list-items"
    local a
    for a in "$@"; do
      if [[ "$a" == "--parent" ]]; then
        adapter_verb="list-sub-items"
        break
      fi
    done
    ;;
  *) fail_usage ;;
  esac

  # Gate only paths that pass gh 2.94 native flags or read its fields, so plain creates
  # work on older gh. list-items stays gated: silent blockedBy zeros would unblock items.
  if [[ "$WIT_PROVIDER" == "github" ]]; then
    case "$adapter_verb" in
    create-item)
      local gated_flag="" a
      for a in "$@"; do
        case "$a" in
        --parent | --blocked-by)
          gated_flag="$a"
          break
          ;;
        *) ;;
        esac
      done
      if [[ -n "$gated_flag" ]]; then
        check_gh_version "$gated_flag"
      else
        check_gh_present
      fi
      ;;
    list-sub-items)
      check_gh_version "list-sub-items"
      ;;
    link-blocks)
      check_gh_version "--blocked-by"
      ;;
    add-sub-item)
      check_gh_version "--parent"
      ;;
    list-items)
      check_gh_version
      ;;
    capabilities)
      # Reads the JSON manifest only; never shells out to gh.
      ;;
    *)
      check_gh_present
      ;;
    esac
  fi

  if [[ "$(jq -r --arg v "$adapter_verb" '.verbs[$v] // false' "$manifest")" != "true" ]]; then
    printf "work-item-tracker: verb '%s' unsupported by provider '%s' (capabilities.json)\n" \
      "$adapter_verb" "$WIT_PROVIDER" >&2
    exit "$EX_CAPABILITY"
  fi

  local out rc
  if [[ "$verb" == "list-frontier" ]]; then
    local autonomous="false" parent="" list_args=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
      --autonomous)
        autonomous="true"
        shift
        ;;
      --parent)
        [[ $# -ge 2 ]] || fail_usage
        parent="$2"
        shift 2
        ;;
      --repo)
        [[ $# -ge 2 ]] || fail_usage
        list_args+=(--repo "$2")
        shift 2
        ;;
      *) fail_usage ;;
      esac
    done
    if [[ -n "$parent" && ${#list_args[@]} -gt 0 ]]; then
      # Rejected loudly: accepting --repo here would silently discard it.
      printf 'work-item-tracker: --repo is not valid with --parent (container id carries the repo)\n' >&2
      exit "$EX_USAGE"
    fi
    if [[ -n "$parent" ]]; then
      # The same filter's container exclusion keeps a nested sub-map among the
      # children from being a frontier item itself.
      out="$(bash "$adapter_dir/list-sub-items.sh" "$parent" --state open)"
    else
      out="$(bash "$adapter_dir/list-items.sh" --state open "${list_args[@]+"${list_args[@]}"}")"
    fi
    rc=$?
    if ((rc != 0)); then
      exit "$rc"
    fi
    # wit_read_binding above guarantees both labels; no inline defaults here.
    printf '%s\n' "$out" | wit_strip_cr |
      wit_filter_frontier "$autonomous" "$WIT_HUMAN_GATED_LABEL" "$WIT_CONTAINER_LABEL"
    exit 0
  fi

  out="$(bash "$adapter_dir/$adapter_verb.sh" "$@")"
  rc=$?
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out" | wit_strip_cr
  fi
  exit "$rc"
}

main "$@"
