#!/usr/bin/env bash
# Core dispatcher for the work-item tracker seam. Contract: CONTRACT.md (verbs, JSON
# shapes, exit codes). Resolves the repo binding, resolves the bound provider's
# adapter consumer-local-first (CONTRACT.md "Adapter resolution"), gates on
# prerequisites and adapter capabilities, dispatches to adapters/<provider>/<verb>.sh,
# and derives list-frontier core-side. WIT_ADAPTERS_DIR overrides the adapter root
# with a single explicit root (tests/conformance).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/binding.sh
source "$SCRIPT_DIR/lib/binding.sh"
# shellcheck source=lib/json.sh
source "$SCRIPT_DIR/lib/json.sh"
# shellcheck source=lib/frontier.sh
source "$SCRIPT_DIR/lib/frontier.sh"

readonly EX_USAGE=2
readonly EX_CONFIG=3
readonly EX_CAPABILITY=6

# wit_resolve_adapter_dir <provider> — echo the bound provider's adapter directory
# using the two-root adapter resolution (CONTRACT.md "Adapter resolution"), first
# existing match wins:
#   1. WIT_ADAPTERS_DIR override — a single explicit adapter root, no search
#      (tests/conformance).
#   2. Consumer-local — ${CLAUDE_PROJECT_DIR}/tools/work-item-tracker/adapters/<provider>:
#      lets a consuming repo add an unshipped provider or shadow a bundled one.
#   3. Plugin-bundled fallback — <seam-dir>/adapters/<provider> (the shipped set).
# When none exists the bundled path is echoed so the caller emits one not-found error.
wit_resolve_adapter_dir() {
  local provider="$1"
  if [[ -n "${WIT_ADAPTERS_DIR:-}" ]]; then
    printf '%s\n' "$WIT_ADAPTERS_DIR/$provider"
    return 0
  fi
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    local local_dir="$CLAUDE_PROJECT_DIR/tools/work-item-tracker/adapters/$provider"
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

fail_config() {
  printf 'work-item-tracker: %s\n' "$1" >&2
  exit "$EX_CONFIG"
}

check_gh_version() {
  command -v gh >/dev/null 2>&1 ||
    fail_config "prerequisite missing: gh (GitHub CLI) >= 2.94 — see CONTRACT.md Prerequisites"
  local raw major minor
  raw="$(gh --version 2>/dev/null | head -n1 | sed -E 's/^gh version ([0-9]+\.[0-9]+).*/\1/')"
  major="${raw%%.*}"
  minor="${raw#*.}"
  if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] ||
    ((major < 2 || (major == 2 && minor < 94))); then
    fail_config "gh >= 2.94 required for native sub-issue/dependency flags (found: ${raw:-unknown})"
  fi
}

main() {
  local verb="${1:-}"
  if [[ "$verb" == "--help" || "$verb" == "-h" ]]; then
    usage 2>&1
    exit 0
  fi
  if [[ -z "$verb" ]]; then
    usage
    exit "$EX_USAGE"
  fi
  shift

  command -v jq >/dev/null 2>&1 ||
    fail_config "prerequisite missing: jq — see CONTRACT.md Prerequisites"

  local binding_path
  binding_path="$(wit_find_binding)" ||
    fail_config "no binding found (.work-item-tracker.json) — see CONTRACT.md Setup"
  wit_read_binding "$binding_path" ||
    fail_config "invalid binding at $binding_path — see CONTRACT.md Setup"

  local adapter_dir manifest
  adapter_dir="$(wit_resolve_adapter_dir "$WIT_PROVIDER")"
  [[ -d "$adapter_dir" ]] ||
    fail_config "no adapter for provider '$WIT_PROVIDER' (searched consumer-local then plugin-bundled) — last tried $adapter_dir"
  manifest="$adapter_dir/capabilities.json"
  [[ -f "$manifest" ]] ||
    fail_config "adapter '$WIT_PROVIDER' has no capabilities.json manifest"

  [[ "$WIT_PROVIDER" == "github" ]] && check_gh_version

  local adapter_verb="$verb"
  case "$verb" in
  create-item | get-item | claim | renew-lease | reclaim | link-blocks | add-sub-item | list-sub-items | capabilities) ;;
  list-frontier)
    # Frontier is a core-side derivation over the adapter's list surface: the
    # global frontier reads list-items; a container-scoped frontier (--parent)
    # reads list-sub-items. The scoped verb is chosen HERE, before the capability
    # gate below, so an adapter that supports list-items but not list-sub-items
    # degrades explicitly (exit 6) instead of passing the gate then failing the
    # scoped call.
    adapter_verb="list-items"
    local a
    for a in "$@"; do
      if [[ "$a" == "--parent" ]]; then
        adapter_verb="list-sub-items"
        break
      fi
    done
    ;;
  *)
    usage
    exit "$EX_USAGE"
    ;;
  esac

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
        [[ $# -ge 2 ]] || {
          usage
          exit "$EX_USAGE"
        }
        parent="$2"
        shift 2
        ;;
      --repo)
        [[ $# -ge 2 ]] || {
          usage
          exit "$EX_USAGE"
        }
        list_args+=(--repo "$2")
        shift 2
        ;;
      *)
        usage
        exit "$EX_USAGE"
        ;;
      esac
    done
    if [[ -n "$parent" ]]; then
      # Container-scoped frontier: enumerate the container's children (the
      # container's own repo is carried by its qualified id, so --repo does not
      # re-target here) and apply the same filter — including container exclusion,
      # so a nested sub-map among the children is never itself a frontier item.
      out="$(bash "$adapter_dir/list-sub-items.sh" "$parent" --state open)"
    else
      out="$(bash "$adapter_dir/list-items.sh" --state open "${list_args[@]+"${list_args[@]}"}")"
    fi
    rc=$?
    if ((rc != 0)); then
      exit "$rc"
    fi
    printf '%s\n' "$out" | wit_strip_cr |
      wit_filter_frontier "$autonomous" "${WIT_HUMAN_GATED_LABEL:-needs-human}" "$WIT_CONTAINER_LABEL"
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
