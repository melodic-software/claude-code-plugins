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
readonly EX_NOT_FOUND=5
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
  create-item --title <t> [--body <b> | --body-file <path>] [--labels a,b]
              [--type <name>] [--parent <id>] [--blocked-by <id>[,<id>]] [--repo <owner>/<repo>]
  get-item <id>
  claim <id> [--ttl-hours <n>] [--ttl-minutes <n>] [--session-id <s>]
        --ttl-minutes (0-59) ADDS to --ttl-hours; for a sub-hour lease pass
        --ttl-hours 0 --ttl-minutes <n>
  renew-lease <id> --lease-comment-id <n>
  release <id> --lease-comment-id <n>
  reclaim <id>
  link-blocks <id> --blocked-by <id>
  add-sub-item <id> --parent <id>
  list-sub-items <parent-id> [--state open|closed|all]
  list-items [--state open|closed|all] [--repo <owner>/<repo>] [--label <name>]
  list-frontier [--autonomous] [--parent <container-id>] [--repo <owner>/<repo>] [--label <name>]
  label-provenance <id> --label <name> [--label <name> ...]
  set-fields <id> --field <field-id>=<option-id> [--field <field-id>=<option-id> ...]
  change-link (<id> | --branch-ref <ref> | --branch <name>) [--repo <owner>/<repo>]
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
  if wit_gh_session_refuses_graphql; then
    fail_config "${feature} is unavailable in this Claude Code cloud session: its GitHub proxy refuses GraphQL and this has no REST form"
  fi
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
  create-item | get-item | claim | renew-lease | release | reclaim | link-blocks | add-sub-item | list-sub-items | label-provenance | set-fields | change-link | capabilities) ;;
  list-items) ;;
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
    capabilities | change-link)
      # Read the JSON manifest or format text only; never shell out to gh.
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
  if [[ "$verb" == "list-frontier" || "$verb" == "list-items" ]]; then
    local autonomous="false" parent="" state="open" label="" has_label="false" list_args=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
      --autonomous)
        [[ "$verb" == "list-frontier" ]] || fail_usage
        autonomous="true"
        shift
        ;;
      --parent)
        [[ "$verb" == "list-frontier" && $# -ge 2 ]] || fail_usage
        parent="$2"
        shift 2
        ;;
      --state)
        [[ "$verb" == "list-items" && $# -ge 2 ]] || fail_usage
        state="$2"
        shift 2
        ;;
      --repo)
        [[ $# -ge 2 ]] || fail_usage
        list_args+=(--repo "$2")
        shift 2
        ;;
      --label)
        [[ $# -ge 2 && -n "$2" ]] || fail_usage
        label="$2"
        has_label="true"
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
    # CONTRACT.md "Adapter contract": an adapter that declares the label filter narrows
    # its provider query, so list_items_max counts only matching items. Any other adapter
    # gets no --label (it would be a usage error there) and lists unfiltered.
    if [[ "$has_label" == "true" && -z "$parent" &&
      "$(jq -r '.features.list_items_label_filter // false' "$manifest")" == "true" ]]; then
      list_args+=(--label "$label")
    fi
    if [[ -n "$parent" ]]; then
      # The same filter's container exclusion keeps a nested sub-map among the
      # children from being a frontier item itself.
      out="$(bash "$adapter_dir/list-sub-items.sh" "$parent" --state open)"
    else
      out="$(bash "$adapter_dir/list-items.sh" --state "$state" "${list_args[@]+"${list_args[@]}"}")"
    fi
    rc=$?
    if ((rc != 0)); then
      exit "$rc"
    fi
    out="$(printf '%s\n' "$out" | wit_strip_cr)"
    # Exact match core-side in every case: it is the whole filter for an adapter without
    # the provider filter, and the guard against a provider that matches loosely.
    if [[ "$has_label" == "true" ]]; then
      out="$(printf '%s\n' "$out" | wit_filter_label "$label")" || exit 1
    fi
    if [[ "$verb" == "list-items" ]]; then
      printf '%s\n' "$out"
      exit 0
    fi
    # wit_read_binding above guarantees both labels; no inline defaults here.
    printf '%s\n' "$out" |
      wit_filter_frontier "$autonomous" "$WIT_HUMAN_GATED_LABEL" "$WIT_CONTAINER_LABEL"
    exit 0
  fi

  if [[ "$verb" == "change-link" ]]; then
    # --branch <name> is core-side: apply the manifest's branch grammar (CONTRACT.md
    # "Change links") and hand the adapter the captured ref, so adapters only qualify refs.
    local cl_args=() branch="" pattern
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "--branch" ]]; then
        [[ $# -ge 2 && -n "$2" && -z "$branch" ]] || fail_usage
        branch="$2"
        shift 2
      else
        cl_args+=("$1")
        shift
      fi
    done
    if [[ -n "$branch" ]]; then
      pattern="$(jq -r '.change_link.branch_pattern // empty' "$manifest")"
      [[ -n "$pattern" ]] ||
        fail_config "adapter '$WIT_PROVIDER' declares change-link but no change_link.branch_pattern"
      if ! [[ "$branch" =~ $pattern ]] || ((${#BASH_REMATCH[@]} < 2)); then
        printf "work-item-tracker: branch '%s' carries no %s item reference\n" "$branch" "$WIT_PROVIDER" >&2
        exit "$EX_NOT_FOUND"
      fi
      cl_args+=(--branch-ref "${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}")
    fi
    set -- "${cl_args[@]+"${cl_args[@]}"}"
  fi

  if [[ "$verb" == "create-item" ]]; then
    # --body-file is core-side (CONTRACT.md "Verbs"): the file's content becomes --body, so
    # adapters see one flag and a caller passes the body with no command substitution.
    local ci_args=() body_file="" has_body="false"
    while [[ $# -gt 0 ]]; do
      case "$1" in
      --body-file)
        [[ $# -ge 2 && -n "$2" && -z "$body_file" ]] || fail_usage
        body_file="$2"
        shift 2
        ;;
      --title | --body | --labels | --type | --parent | --blocked-by | --repo)
        [[ "$1" == "--body" ]] && has_body="true"
        ci_args+=("$1")
        shift
        if [[ $# -gt 0 ]]; then
          ci_args+=("$1")
          shift
        fi
        ;;
      *)
        ci_args+=("$1")
        shift
        ;;
      esac
    done
    if [[ -n "$body_file" ]]; then
      if [[ "$has_body" == "true" ]]; then
        printf 'work-item-tracker: --body and --body-file are mutually exclusive\n' >&2
        exit "$EX_USAGE"
      fi
      if [[ ! -f "$body_file" || ! -r "$body_file" ]]; then
        printf "work-item-tracker: --body-file '%s' is not a readable file\n" "$body_file" >&2
        exit "$EX_USAGE"
      fi
      if [[ ! -s "$body_file" ]]; then
        printf "work-item-tracker: --body-file '%s' is empty; write the body to it before create-item\n" "$body_file" >&2
        exit "$EX_USAGE"
      fi
      ci_args+=(--body "$(<"$body_file")")
    fi
    set -- "${ci_args[@]+"${ci_args[@]}"}"
  fi

  out="$(bash "$adapter_dir/$adapter_verb.sh" "$@")"
  rc=$?
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out" | wit_strip_cr
  fi
  exit "$rc"
}

main "$@"
