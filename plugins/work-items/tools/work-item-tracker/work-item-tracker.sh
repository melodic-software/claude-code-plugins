#!/usr/bin/env bash
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
readonly EX_AUTH=4
readonly EX_NOT_FOUND=5
readonly EX_CAPABILITY=6

readonly WIT_STATUS_FIELD="Work status"

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
  get-item <id> [--history]
  claim <id> [--ttl-hours <n>] [--ttl-minutes <n>] [--session-id <s>] [--holder <h>] [--lease-only]
        [--phase triage|discovery|implementation]
        --ttl-minutes (0-59) ADDS to --ttl-hours; for a sub-hour lease pass
        --ttl-hours 0 --ttl-minutes <n>
        --phase is github and local-markdown only; absent means implementation
  renew-lease <id> --lease-comment-id <n>
  release <id> --lease-comment-id <n> [--holder <h>]
  reclaim <id>
  link-blocks <id> --blocked-by <id>
  add-sub-item <id> --parent <id>
  list-sub-items <parent-id> [--state open|closed|all]
  list-items [--state open|closed|all] [--repo <owner>/<repo>] [--label <name>]
  list-frontier [--autonomous] [--parent <container-id>] [--repo <owner>/<repo>] [--label <name>]
  label-provenance <id> --label <name> [--label <name> ...]
  set-fields <id> --field <field-id>=<option-id> [--field <field-id>=<option-id> ...]
  get-field-options --field <name-or-id> [--repo <owner>/<repo>]
  get-statuses --field <name> <id>...
  status-storage [--repo <owner>/<repo>]
  change-link (<id> | --branch-ref <ref> | --branch <name>) [--repo <owner>/<repo>]
  add-recurrence <id> --source-link <url> --note <text>
  wayfind-labels
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

check_gh_present() {
  command -v gh >/dev/null 2>&1 ||
    fail_config "prerequisite missing: gh (GitHub CLI) — see CONTRACT.md Prerequisites"
}

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

wit_detect_status_storage() {
  local adapter_dir="$1" manifest="$2" fields_out fields_rc errfile refused
  shift 2
  WIT_STATUS_STORAGE="labels" WIT_STATUS_REASON="" WIT_STATUS_RC=0 WIT_STATUS_ERR=""
  if [[ "$(jq -r '.verbs["get-field-options"] // false' "$manifest")" != "true" ]]; then
    WIT_STATUS_REASON="adapter declares no get-field-options"
    return 0
  fi
  errfile="$(mktemp)"
  fields_out="$(bash "$adapter_dir/get-field-options.sh" --field "$WIT_STATUS_FIELD" "$@" 2>"$errfile")"
  fields_rc=$?
  WIT_STATUS_ERR="$(<"$errfile")"
  rm -f "$errfile"
  refused="false"
  case "$fields_rc" in
  "$EX_NOT_FOUND") refused="true" ;;
  "$EX_AUTH")
    [[ "$WIT_STATUS_ERR" == *"HTTP 403"* && "$WIT_STATUS_ERR" != *"rate limit"* ]] && refused="true"
    ;;
  *) ;;
  esac
  if ((fields_rc == 0)); then
    if jq -e '.options | length > 0' <<<"$fields_out" >/dev/null 2>&1; then
      WIT_STATUS_STORAGE="field"
      WIT_STATUS_REASON="'$WIT_STATUS_FIELD' issue field has options"
    else
      WIT_STATUS_REASON="no '$WIT_STATUS_FIELD' issue field with options"
    fi
  elif [[ "$refused" == "true" ]]; then
    WIT_STATUS_REASON="issue-field listing unreadable (exit $fields_rc)"
  else
    WIT_STATUS_RC="$fields_rc"
    return 1
  fi
  return 0
}

wit_attach_statuses() {
  local adapter_dir="$1" manifest="$2" envelope ids out errfile i n id statuses='{}' chunk=() rc
  shift 2
  envelope="$(cat)"
  if [[ "$(jq -r '.verbs["get-statuses"] // false' "$manifest")" != "true" ]]; then
    printf '%s\n' "$envelope"
    return 0
  fi
  if ! wit_detect_status_storage "$adapter_dir" "$manifest" "$@"; then
    printf 'work-item-tracker: status storage unread (exit %s): %s\n' \
      "$WIT_STATUS_RC" "$WIT_STATUS_ERR" >&2
    return "$WIT_STATUS_RC"
  fi
  if [[ "$WIT_STATUS_STORAGE" != "field" ]]; then
    printf '%s\n' "$envelope"
    return 0
  fi
  ids="$(jq -c '[.items[] | select(.state == "open" and .blocked_by_count == 0
    and ((.assignees // []) | length == 0)) | .id]' <<<"$envelope")"
  n="$(jq 'length' <<<"$ids")"
  for ((i = 0; i < n; i += 100)); do
    chunk=()
    while IFS= read -r id; do
      chunk+=("$id")
    done < <(jq -r --argjson i "$i" '.[$i:$i + 100][]' <<<"$ids")
    errfile="$(mktemp)"
    rc=0
    out="$(bash "$adapter_dir/get-statuses.sh" --field "$WIT_STATUS_FIELD" "${chunk[@]}" 2>"$errfile")" || rc=$?
    if ((rc == 0)); then
      out="$(jq -ce '.statuses | objects' <<<"$out" 2>/dev/null)" || rc=1
    fi
    if ((rc != 0)); then
      printf 'work-item-tracker: %s values unread: %s\n' \
        "$WIT_STATUS_FIELD" "$(<"$errfile")" >&2
      rm -f "$errfile"
      return "$rc"
    fi
    rm -f "$errfile"
    statuses="$(jq -cn --argjson acc "$statuses" --argjson page "$out" '$acc + $page')"
  done
  jq -c --argjson s "$statuses" '.items |= map(.id as $id | if ($id | type) == "string" and ($s | has($id)) then .status = $s[$id] else . end)' <<<"$envelope"
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

  if [[ "$verb" == "wayfind-labels" ]]; then
    (($# == 0)) || fail_usage
    local labels
    labels="$(wit_wayfind_labels)" || exit "$EX_CONFIG"
    jq -c --arg sv "$WIT_SCHEMA_VERSION" '{schema_version: $sv} + .' <<<"$labels"
    exit 0
  fi

  local binding_path
  binding_path="$(wit_find_binding)" ||
    fail_config "$(wit_no_binding_reason); see CONTRACT.md Setup"
  wit_read_binding "$binding_path" ||
    fail_config "invalid binding at $binding_path — run /work-items:setup check for the itemized breakdown; see CONTRACT.md Setup"

  local adapter_dir manifest
  adapter_dir="$(wit_resolve_adapter_dir "$WIT_PROVIDER")"
  if [[ ! -d "$adapter_dir" && -d "$SCRIPT_DIR/seeds/$WIT_PROVIDER" ]]; then
    fail_config "provider '$WIT_PROVIDER' ships as a seed the consuming repo owns; run /work-items:setup apply to copy it into tools/work-item-tracker/adapters/$WIT_PROVIDER/"
  fi
  [[ -d "$adapter_dir" ]] ||
    fail_config "no adapter for provider '$WIT_PROVIDER' (searched consumer-local then plugin-bundled) — last tried $adapter_dir"
  manifest="$adapter_dir/capabilities.json"
  [[ -f "$manifest" ]] ||
    fail_config "adapter '$WIT_PROVIDER' has no capabilities.json manifest"

  wit_check_contract_version "$WIT_PROVIDER" "$manifest" ||
    exit "$EX_CONFIG"

  export WIT_SEAM_LIB_DIR="$SCRIPT_DIR/lib"

  local adapter_verb="$verb"
  case "$verb" in
  create-item | get-item | claim | renew-lease | release | reclaim | link-blocks | add-sub-item | list-sub-items | label-provenance | set-fields | get-field-options | get-statuses | change-link | add-recurrence | capabilities) ;;
  list-items | status-storage) ;;
  list-frontier)
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

  if [[ "$WIT_PROVIDER" == "github" ]]; then
    case "$adapter_verb" in
    create-item)
      local gated_flag="" a
      for a in "$@"; do
        if [[ "$a" == "--parent" || "$a" == "--blocked-by" ]]; then
          gated_flag="$a"
          break
        fi
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
      if wit_gh_session_refuses_graphql; then
        check_gh_present
      else
        check_gh_version
      fi
      ;;
    capabilities | change-link)
      ;;
    *)
      check_gh_present
      ;;
    esac
  fi

  if [[ "$verb" == "status-storage" ]]; then
    local repo_args=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
      --repo)
        [[ $# -ge 2 && -n "$2" ]] || fail_usage
        repo_args=(--repo "$2")
        shift 2
        ;;
      *) fail_usage ;;
      esac
    done
    if ! wit_detect_status_storage "$adapter_dir" "$manifest" "${repo_args[@]+"${repo_args[@]}"}"; then
      printf '%s\n' "$WIT_STATUS_ERR" >&2
      exit "$WIT_STATUS_RC"
    fi
    jq -nc --arg sv "$WIT_SCHEMA_VERSION" --arg storage "$WIT_STATUS_STORAGE" --arg field "$WIT_STATUS_FIELD" \
      --arg reason "$WIT_STATUS_REASON" '{schema_version: $sv, storage: $storage,
        field: (if $storage == "field" then $field else null end), reason: $reason}'
    exit 0
  fi

  if [[ "$(jq -r --arg v "$adapter_verb" '.verbs[$v] // false' "$manifest")" != "true" ]]; then
    printf "work-item-tracker: verb '%s' unsupported by provider '%s' (capabilities.json)\n" \
      "$adapter_verb" "$WIT_PROVIDER" >&2
    exit "$EX_CAPABILITY"
  fi

  local out rc
  if [[ "$verb" == "list-frontier" || "$verb" == "list-items" ]]; then
    local autonomous="false" parent="" state="open" label="" list_args=() repo_args=()
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
        repo_args=(--repo "$2")
        shift 2
        ;;
      --label)
        [[ $# -ge 2 && -n "$2" ]] || fail_usage
        label="$2"
        shift 2
        ;;
      *) fail_usage ;;
      esac
    done
    if [[ -n "$parent" && ${#list_args[@]} -gt 0 ]]; then
      printf 'work-item-tracker: --repo is not valid with --parent (container id carries the repo)\n' >&2
      exit "$EX_USAGE"
    fi
    if [[ -n "$label" && -z "$parent" &&
      "$(jq -r '.features.list_items_label_filter // false' "$manifest")" == "true" ]]; then
      list_args+=(--label "$label")
    fi
    if [[ -n "$parent" ]]; then
      out="$(bash "$adapter_dir/list-sub-items.sh" "$parent" --state open)"
    else
      out="$(bash "$adapter_dir/list-items.sh" --state "$state" "${list_args[@]+"${list_args[@]}"}")"
    fi
    rc=$?
    ((rc == 0)) || exit "$rc"
    out="$(printf '%s\n' "$out" | wit_strip_cr)"
    if [[ -n "$label" ]]; then
      out="$(printf '%s\n' "$out" | wit_filter_label "$label")" || exit 1
    fi
    if [[ "$verb" == "list-items" ]]; then
      printf '%s\n' "$out"
      exit 0
    fi
    if [[ "$autonomous" == "true" ]]; then
      out="$(printf '%s\n' "$out" | wit_attach_statuses "$adapter_dir" "$manifest" "${repo_args[@]+"${repo_args[@]}"}")" || exit $?
    fi
    printf '%s\n' "$out" |
      wit_filter_frontier "$autonomous" "$WIT_HUMAN_GATED_LABEL" "$WIT_CONTAINER_LABEL"
    exit 0
  fi

  if [[ "$verb" == "change-link" ]]; then
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

  if [[ "$verb" == "get-item" ]] && [[ " $* " == *" --history "* ]]; then
    [[ $# -eq 2 && "$2" == "--history" ]] || fail_usage
    if [[ "$(jq -r '.features.state_history // false' "$manifest")" == "true" ]]; then
      out="$(bash "$adapter_dir/get-item.sh" "$1" --history)"
      rc=$?
    else
      out="$(bash "$adapter_dir/get-item.sh" "$1")"
      rc=$?
      if ((rc == 0)); then
        out="$(printf '%s\n' "$out" | wit_strip_cr | jq -c --arg reason "state history not available for provider '$WIT_PROVIDER'" \
          '.state_history = {available: false, events: null, reopen_count: null, reason: $reason}')" || exit 1
      fi
    fi
    [[ -z "$out" ]] || printf '%s\n' "$out" | wit_strip_cr
    exit "$rc"
  fi

  out="$(bash "$adapter_dir/$adapter_verb.sh" "$@")"
  rc=$?
  [[ -z "$out" ]] || printf '%s\n' "$out" | wit_strip_cr
  exit "$rc"
}

main "$@"
