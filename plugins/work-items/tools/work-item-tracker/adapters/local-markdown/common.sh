# shellcheck shell=bash

[[ -n "${_WIT_LOCAL_COMMON_LOADED:-}" ]] && return 0
readonly _WIT_LOCAL_COMMON_LOADED=1

WIT_LOCAL_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WIT_LOCAL_ADAPTER_DIR

wit_local_require_seam_lib() {
  [[ -f "$1" ]] && return 0
  printf 'work-item-tracker local-markdown adapter: required seam library not found: %s\n' "$1" >&2
  printf '  a shadowed consumer-local adapter must still resolve the bundled seam lib/ directory\n' >&2
  exit 3
}

wit_local_require_seam_lib "$WIT_LOCAL_ADAPTER_DIR/../../lib/id.sh"
# shellcheck source=../../lib/id.sh
source "$WIT_LOCAL_ADAPTER_DIR/../../lib/id.sh"
wit_local_require_seam_lib "$WIT_LOCAL_ADAPTER_DIR/../../lib/json.sh"
# shellcheck source=../../lib/json.sh
source "$WIT_LOCAL_ADAPTER_DIR/../../lib/json.sh"
wit_local_require_seam_lib "$WIT_LOCAL_ADAPTER_DIR/../../lib/verb-cli.sh"
# shellcheck source=../../lib/verb-cli.sh
source "$WIT_LOCAL_ADAPTER_DIR/../../lib/verb-cli.sh"
wit_local_require_seam_lib "$WIT_LOCAL_ADAPTER_DIR/../../lib/lease.sh"
# shellcheck source=../../lib/lease.sh
source "$WIT_LOCAL_ADAPTER_DIR/../../lib/lease.sh"

readonly WIT_LOCAL_DEFAULT_NS='local/markdown'

readonly EX_USAGE=2
readonly EX_CONFIG=3
readonly EX_NOT_FOUND=5
readonly EX_CONFLICT=7
export WIT_LOCAL_DEFAULT_NS EX_NOT_FOUND EX_CONFLICT

wit_require_local_id() {
  wit_parse_id "$1" || return 1
  [[ "$WIT_ID_PROVIDER" == "local-markdown" ]] || return 1
}

wit_need_storage() {
  [[ -n "${WIT_STORAGE_DIR:-}" ]] || {
    printf '%s: config.storage_dir is required for provider local-markdown — see CONTRACT.md Setup\n' \
      "$(basename "${BASH_SOURCE[1]}")" >&2
    exit "$EX_CONFIG"
  }
  mkdir -p "$WIT_STORAGE_DIR"
}

wit_item_file() {
  printf '%s/%s.md\n' "$WIT_STORAGE_DIR" "$1"
}

wit_item_exists() {
  [[ -f "$(wit_item_file "$1")" ]]
}

wit_item_numbers() {
  local f base
  shopt -s nullglob
  for f in "$WIT_STORAGE_DIR"/*.md; do
    base="${f##*/}"
    base="${base%.md}"
    [[ "$base" =~ ^[0-9]+$ ]] || continue
    printf '%s\n' "$base"
  done | sort -n
}

wit_state_matches() {
  case "$1" in
  open) [[ "$2" == '"open"' ]] ;;
  closed) [[ "$2" == '"closed"' ]] ;;
  *) return 0 ;;
  esac
}

wit_next_number() {
  local max
  max="$(wit_item_numbers | tail -n 1)"
  printf '%s\n' "$((10#${max:-0} + 1))"
}

wit_fm_field() {
  awk -v k="$2" '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---" { exit }
    infm {
      idx = index($0, ": ")
      if (idx > 0 && substr($0, 1, idx - 1) == k) { print substr($0, idx + 2); exit }
    }
  ' "$1"
}

wit_fm_set() {
  local file="$1" key="$2" val="$3" tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$val" '
    NR == 1 { infm = ($0 == "---") }
    infm && NR > 1 && $0 == "---" { infm = 0 }
    infm {
      idx = index($0, ": ")
      if (idx > 0 && substr($0, 1, idx - 1) == k) { print k ": " v; next }
    }
    { print }
  ' "$file" >"$tmp" && mv "$tmp" "$file"
}

wit_blocked_by_ids() {
  sed -n 's/^Blocked by: //p' "$1"
}

wit_claim_write() {
  local file="$1" marker_line="$2" assignees="$3" tmp
  printf '%s\n' "$marker_line" >>"$file"
  if wit_fm_set "$file" assignees "$assignees"; then
    return 0
  fi
  if tmp="$(mktemp)" && grep -vxF -- "$marker_line" "$file" >"$tmp" && mv "$tmp" "$file" 2>/dev/null; then
    return 1
  fi
  [[ -n "${tmp:-}" ]] && rm -f "$tmp"
  printf 'wit_claim_write: rollback of the lease marker failed — the store may hold an orphaned lease marker\n' >&2
  return 1
}

wit_lease_lines() {
  grep -F "$WIT_LEASE_MARKER" "$1" 2>/dev/null || true
}

wit_active_lease_json() {
  local file="$1" line json active="" lines
  lines="$(wit_lease_lines "$file")" # capture, not `< <()` — MSYS process-sub hangs (see wit_emit_local_item)
  while IFS= read -r line; do
    json="$(wit_lease_json "$line")"
    [[ -n "$json" ]] || continue
    [[ -z "$(jq -r '.superseded_at // empty' <<<"$json")" ]] || continue
    active="$json"
  done <<<"$lines"
  printf '%s\n' "$active"
}

wit_next_lease_id() {
  local max=0 f line json lid flines
  shopt -s nullglob
  for f in "$WIT_STORAGE_DIR"/*.md; do
    flines="$(wit_lease_lines "$f")" # capture, not `< <()` — MSYS process-sub hangs
    while IFS= read -r line; do
      json="$(wit_lease_json "$line")"
      [[ -n "$json" ]] || continue
      lid="$(jq -r '.lease_comment_id // 0' <<<"$json")"
      [[ "$lid" =~ ^[0-9]+$ ]] && ((lid > max)) && max="$lid"
    done <<<"$flines"
  done
  printf '%s\n' "$((max + 1))"
}

wit_find_lease_file() {
  local target="$1" f base line json lid flines
  shopt -s nullglob
  for f in "$WIT_STORAGE_DIR"/*.md; do
    base="${f##*/}"
    base="${base%.md}"
    [[ "$base" =~ ^[0-9]+$ ]] || continue
    flines="$(wit_lease_lines "$f")" # capture, not `< <()` — MSYS process-sub hangs
    while IFS= read -r line; do
      json="$(wit_lease_json "$line")"
      [[ -n "$json" ]] || continue
      lid="$(jq -r '.lease_comment_id // empty' <<<"$json")"
      if [[ "$lid" == "$target" ]]; then
        printf '%s\t%s\n' "$base" "$line"
        return 0
      fi
    done <<<"$flines"
  done
  return 1
}

wit_emit_local_item() {
  local number="$1" unassign_expired="${2:-false}" file
  file="$(wit_item_file "$number")"
  [[ -f "$file" ]] || return 1
  local id title state assignees labels type parent url created_at
  id="$(wit_fm_field "$file" id)"
  title="$(wit_fm_field "$file" title)"
  state="$(wit_fm_field "$file" state)"
  assignees="$(wit_fm_field "$file" assignees)"
  if [[ "$unassign_expired" == "true" && "$assignees" != "[]" ]]; then
    local active_lease
    active_lease="$(wit_active_lease_json "$file")"
    if [[ -n "$active_lease" ]] && ! wit_lease_is_live "$active_lease" "$(date -u +%s)"; then
      assignees='[]'
    fi
  fi
  labels="$(wit_fm_field "$file" labels)"
  type="$(wit_fm_field "$file" type)"
  [[ -n "$type" ]] || type="null"
  parent="$(wit_fm_field "$file" parent)"
  url="$(wit_fm_field "$file" url)"
  created_at="$(wit_fm_field "$file" created_at)"
  [[ -n "$created_at" ]] || created_at="null"
  local count=0 wont_do=0 bid bnum bstate breason bfile blockers
  blockers="$(wit_blocked_by_ids "$file")"
  while IFS= read -r bid; do
    [[ -n "$bid" ]] || continue
    bnum="${bid##*#}"
    [[ "$bnum" =~ ^[0-9]+$ ]] || continue
    bfile="$(wit_item_file "$bnum")"
    [[ -f "$bfile" ]] || continue
    bstate="$(wit_fm_field "$bfile" state)"
    if [[ "$bstate" == '"open"' ]]; then
      count=$((count + 1))
      continue
    fi
    breason="$(wit_fm_field "$bfile" state_reason)"
    if [[ -n "$breason" && "$breason" != null && "$breason" != '"completed"' ]]; then
      count=$((count + 1))
      wont_do=$((wont_do + 1))
    fi
  done <<<"$blockers"
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" \
    --argjson id "$id" --argjson title "$title" --argjson state "$state" \
    --argjson assignees "$assignees" --argjson labels "$labels" \
    --argjson type "$type" \
    --argjson parent "$parent" --argjson count "$count" --argjson wont_do "$wont_do" \
    --argjson url "$url" --argjson created_at "$created_at" \
    "$WIT_JQ_DEF_UTC_TS"'{schema_version: $sv, id: $id, title: $title, state: $state,
      assignees: $assignees, labels: $labels, type: $type, blocked_by_count: $count,
      blocked_by_wont_do_count: $wont_do, parent_id: $parent, url: $url,
      created_at: ($created_at | wit_utc_ts), milestone: null}'
}
