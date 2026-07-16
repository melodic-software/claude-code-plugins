#!/usr/bin/env bash
# create-item — CONTRACT.md "Verbs (core public surface)". Writes one markdown file
# per item under storage_dir with JSON-valued frontmatter; --parent lands as a
# frontmatter field, --blocked-by ids as "Blocked by:" body lines.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: create-item --title <t> [--body <b>] [--labels a,b] [--type <name>] [--parent <id>] [--blocked-by <id>[,<id>]] [--repo <owner>/<repo>]" "$@"

title="" body="" labels="" type="" parent="" blocked_by="" repo_override=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      [[ $# -ge 2 ]] || wit_usage_error "--title needs a value"
      title="$2"
      shift 2
      ;;
    --type)
      [[ $# -ge 2 ]] || wit_usage_error "--type needs a value"
      type="$2"
      shift 2
      ;;
    --body)
      [[ $# -ge 2 ]] || wit_usage_error "--body needs a value"
      body="$2"
      shift 2
      ;;
    --labels)
      [[ $# -ge 2 ]] || wit_usage_error "--labels needs a value"
      labels="$2"
      shift 2
      ;;
    --parent)
      [[ $# -ge 2 ]] || wit_usage_error "--parent needs a value"
      parent="$2"
      shift 2
      ;;
    --blocked-by)
      [[ $# -ge 2 ]] || wit_usage_error "--blocked-by needs a value"
      blocked_by="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || wit_usage_error "--repo needs a value"
      repo_override="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
[[ -n "$title" ]] || wit_usage_error "--title is required"

parent_id="null"
if [[ -n "$parent" ]]; then
  wit_require_local_id "$parent" || wit_usage_error "malformed or non-local-markdown --parent id: $parent"
  parent_id="$(jq -cn --arg p "$parent" '$p')"
fi

blocker_ids=()
if [[ -n "$blocked_by" ]]; then
  IFS=',' read -ra blocker_list <<<"$blocked_by"
  for blocker in "${blocker_list[@]}"; do
    [[ -n "$blocker" ]] || continue
    wit_require_local_id "$blocker" || wit_usage_error "malformed or non-local-markdown --blocked-by id: $blocker"
    blocker_ids+=("$blocker")
  done
fi

wit_need_storage

# Referenced parent/blockers must exist (parity with the GitHub adapter, whose gh
# call rejects an unknown parent/blocker) — otherwise create-item would persist a
# dead edge that get-item/list-frontier silently ignore.
if [[ -n "$parent" ]]; then
  wit_item_exists "${parent##*#}" || {
    printf 'create-item: --parent %s not found\n' "$parent" >&2
    exit "$EX_NOT_FOUND"
  }
fi
for blocker in "${blocker_ids[@]+"${blocker_ids[@]}"}"; do
  wit_item_exists "${blocker##*#}" || {
    printf 'create-item: --blocked-by %s not found\n' "$blocker" >&2
    exit "$EX_NOT_FOUND"
  }
done

ns="${repo_override:-$WIT_LOCAL_DEFAULT_NS}"
# owner/repo must match the ID grammar's char class (lib/id.sh); an out-of-grammar
# --repo would otherwise mint an ID that get-item and later verbs cannot parse.
[[ "$ns" == */* && "${ns%%/*}" =~ ^[A-Za-z0-9_.-]+$ && "${ns##*/}" =~ ^[A-Za-z0-9_.-]+$ ]] \
  || wit_usage_error "--repo must be <owner>/<repo> matching [A-Za-z0-9_.-] (got: $ns)"

number="$(wit_next_number)"
id="$(wit_make_id local-markdown "${ns%%/*}" "${ns##*/}" "$number")"
file="$(wit_item_file "$number")"

labels_json="$(jq -cn --arg s "$labels" '$s | split(",") | map(select(length > 0))')"
# Type-axis parity with the GitHub adapter: an optional scalar (null when unset).
# This adapter is offline, so there is no native type registry to validate against.
type_json="$(jq -cn --arg s "$type" 'if $s == "" then null else $s end')"

{
  printf -- '---\n'
  printf 'id: %s\n' "$(jq -cn --arg s "$id" '$s')"
  printf 'number: %s\n' "$number"
  printf 'title: %s\n' "$(jq -cn --arg s "$title" '$s')"
  printf 'state: %s\n' '"open"'
  printf 'assignees: %s\n' '[]'
  printf 'labels: %s\n' "$labels_json"
  printf 'type: %s\n' "$type_json"
  printf 'parent: %s\n' "$parent_id"
  printf 'url: %s\n' "$(jq -cn --arg s "file://$file" '$s')"
  printf -- '---\n\n'
  [[ -n "$body" ]] && printf '%s\n\n' "$body"
  for blocker in "${blocker_ids[@]+"${blocker_ids[@]}"}"; do
    printf 'Blocked by: %s\n' "$blocker"
  done
} >"$file"

wit_emit_local_item "$number"
