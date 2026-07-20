# shellcheck shell=bash
# Shared helpers for the local-markdown adapter — sourced by every verb script.
# Storage model (CONTRACT.md "local-markdown adapter"): one markdown file per item
# at <storage_dir>/<number>.md. Frontmatter carries id/state/assignees/labels/parent
# as one-line JSON values (YAML-flow-compatible, robust to special chars, trivially
# bash-parseable). Edges are structured "Blocked by:" body lines. The lease is an
# inline HTML-comment marker identical in shape to the GitHub adapter's, plus a
# provider-specific numeric handle (lease_comment_id) so renew-lease can address a
# lease the way it addresses a GitHub comment id.
#
# Offline-only: this adapter never invokes gh, curl, or any network tool — it is the
# conformance reference + degraded-offline surface, NEVER a coordination surface.

[[ -n "${_WIT_LOCAL_COMMON_LOADED:-}" ]] && return 0
readonly _WIT_LOCAL_COMMON_LOADED=1

WIT_LOCAL_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WIT_LOCAL_ADAPTER_DIR

# A consumer may shadow this adapter with a local copy (CONTRACT.md "Adapter
# resolution") while still running the bundled dispatcher; the shared seam libs
# below then resolve relative to that copy and can be absent. A missing required
# lib must hard-fail with a clear diagnostic (exit 3 — setup/config error), never
# let sourcing fail silently and leave a verb emitting a malformed (e.g. empty-id)
# record. Runs before the EX_* constants below exist, so it uses the literal.
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
wit_local_require_seam_lib "$WIT_LOCAL_ADAPTER_DIR/../../lib/lease.sh"
# shellcheck source=../../lib/lease.sh
source "$WIT_LOCAL_ADAPTER_DIR/../../lib/lease.sh"

readonly WIT_LOCAL_DEFAULT_NS='local/markdown'

readonly EX_USAGE=2
readonly EX_CONFIG=3
readonly EX_NOT_FOUND=5
readonly EX_CONFLICT=7
# The default namespace and the verb-referenced exit codes are consumed by the
# sourcing verb scripts; export so a standalone lint of this sourced-only file sees
# them as intentionally external (mirrors lib/json.sh exporting WIT_SCHEMA_VERSION).
export WIT_LOCAL_DEFAULT_NS EX_NOT_FOUND EX_CONFLICT

wit_usage_error() {
  printf '%s: %s\n' "$(basename "${BASH_SOURCE[1]}")" "$1" >&2
  exit "$EX_USAGE"
}

# wit_help_if_requested <usage-text> <args…> — print usage + exit 0 on --help.
wit_help_if_requested() {
  local usage="$1"
  shift
  if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' "$usage"
    exit 0
  fi
}

# wit_require_local_id <id> — parse an ID and require its provider be
# `local-markdown`. The shared grammar accepts any provider; this adapter rejects
# foreign-provider IDs so a `github:…#N` never operates on a local item. Sets the
# WIT_ID_* globals on success.
wit_require_local_id() {
  wit_parse_id "$1" || return 1
  [[ "$WIT_ID_PROVIDER" == "local-markdown" ]] || return 1
}

# wit_need_storage — the store directory is required at runtime; verbs call this
# after arg parsing so --help / usage errors stay offline. Exits 3 (config) when
# the binding did not supply config.storage_dir.
wit_need_storage() {
  [[ -n "${WIT_STORAGE_DIR:-}" ]] ||
    {
      printf '%s: config.storage_dir is required for provider local-markdown — see CONTRACT.md Setup\n' \
        "$(basename "${BASH_SOURCE[1]}")" >&2
      exit "$EX_CONFIG"
    }
  mkdir -p "$WIT_STORAGE_DIR"
}

wit_item_file() {
  printf '%s/%s.md\n' "$WIT_STORAGE_DIR" "$1"
}

# wit_item_exists <number> — 0 when the item file exists. Edge verbs use this to
# reject a reference to a non-existent item (parity with the GitHub adapter, whose
# gh call rejects an unknown parent/blocker) instead of writing a dead edge.
wit_item_exists() {
  [[ -f "$(wit_item_file "$1")" ]]
}

# wit_next_number — max existing item file number + 1 (single-writer store).
wit_next_number() {
  local max=0 f base n
  shopt -s nullglob
  for f in "$WIT_STORAGE_DIR"/*.md; do
    base="$(basename "$f" .md)"
    [[ "$base" =~ ^[0-9]+$ ]] || continue
    n="$base"
    ((n > max)) && max="$n"
  done
  printf '%s\n' "$((max + 1))"
}

# wit_fm_field <file> <key> — echo the raw one-line JSON value of a frontmatter
# field (between the opening and closing `---`). Empty when absent.
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

# wit_fm_set <file> <key> <json-value> — replace an existing frontmatter field
# line in place (all fields are written at create time, so this only replaces).
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

# wit_blocked_by_ids <file> — one blocker ID per line from "Blocked by:" lines.
wit_blocked_by_ids() {
  sed -n 's/^Blocked by: //p' "$1"
}

# wit_claim_write <file> <marker-line> <assignees-json> — append the inline lease
# marker, then record the assignee, keeping the two writes consistent. A live lease
# marker paired with an empty assignees would present the item as available (the
# frontier filter keys on assignees) while the lease is live, letting a later claim
# race the live lease until it expires. If the assignee write fails (store full or
# unwritable), best-effort roll the just-appended marker back and return 1 so the
# caller fails the claim instead of recording a half-applied success.
wit_claim_write() {
  local file="$1" marker_line="$2" assignees="$3" tmp
  printf '%s\n' "$marker_line" >>"$file"
  if wit_fm_set "$file" assignees "$assignees"; then
    return 0
  fi
  # Compensate for the partial write by dropping the marker just appended. The
  # marker line is unique in the file (lease_comment_id is store-monotonic), so
  # removing every exact match removes only this one — grep has no portable
  # "remove the last matching line" primitive. The rollback is best-effort: it can
  # fail under the same store condition that failed the assignee write, so on that
  # path warn about the orphaned marker rather than leave it silently stranded.
  if tmp="$(mktemp)" && grep -vxF -- "$marker_line" "$file" >"$tmp" && mv "$tmp" "$file" 2>/dev/null; then
    return 1
  fi
  [[ -n "${tmp:-}" ]] && rm -f "$tmp"
  printf 'wit_claim_write: rollback of the lease marker failed — the store may hold an orphaned lease marker\n' >&2
  return 1
}

# wit_lease_lines <file> — the raw lease marker lines of an item, in file order.
wit_lease_lines() {
  grep -F "$WIT_LEASE_MARKER" "$1" 2>/dev/null || true
}

# wit_active_lease_json <file> — the newest non-superseded lease JSON, or empty.
# "Newest" = last in file order (leases are appended). A back-off never appends on
# this single-writer adapter (claim checks before writing), so file order suffices.
wit_active_lease_json() {
  local file="$1" line json active="" lines
  lines="$(wit_lease_lines "$file")" # capture, not `< <()` — MSYS process-sub hangs (see wit_emit_local_item)
  while IFS= read -r line; do
    json="$(wit_lease_json "$line")"
    [[ -n "$json" ]] || continue
    [[ "$(jq -r '.superseded_at // empty' <<<"$json")" == "" ]] || continue
    active="$json"
  done <<<"$lines"
  printf '%s\n' "$active"
}

# wit_next_lease_id — max lease_comment_id across the store + 1 (store-global
# handle, mirroring GitHub's store-wide comment ids).
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

# wit_find_lease_file <lease-comment-id> — echo "<number>\t<marker-line>" for the
# item whose file carries a lease with the given handle; exit 1 when none.
wit_find_lease_file() {
  local target="$1" f base line json lid flines
  shopt -s nullglob
  for f in "$WIT_STORAGE_DIR"/*.md; do
    base="$(basename "$f" .md)"
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

# wit_emit_local_item <number> [<unassign-expired:true|false>] — emit the
# normalized item object (CONTRACT.md "JSON output contract") for an existing item
# file. Returns 1 when the file is absent (caller maps to exit 5). blocked_by_count
# counts only blockers whose file exists and is open, mirroring the GitHub adapter's
# OPEN-only count. With unassign-expired=true the effective assignee of an item
# whose lease has expired is projected empty (see the projection note below); the
# default (false) reports the stored assignee verbatim.
wit_emit_local_item() {
  local number="$1" unassign_expired="${2:-false}" file
  file="$(wit_item_file "$number")"
  [[ -f "$file" ]] || return 1
  local id title state assignees labels type parent url
  id="$(wit_fm_field "$file" id)"
  title="$(wit_fm_field "$file" title)"
  state="$(wit_fm_field "$file" state)"
  assignees="$(wit_fm_field "$file" assignees)"
  # An expired lease is an abandoned claim. This offline adapter has no reclaim to
  # clear the assignee (CONTRACT.md local-markdown "Degradation"), so for frontier/
  # list derivation the effective assignee is empty and the item returns to the
  # frontier (the core filter keys on assignees). get-item keeps the stored
  # assignee raw — parity with the GitHub adapter, whose assignee persists until
  # reclaim — so this projection is opt-in per caller, never a stored mutation.
  if [[ "$unassign_expired" == "true" && "$assignees" != "[]" ]]; then
    local active_lease
    active_lease="$(wit_active_lease_json "$file")"
    if [[ -n "$active_lease" ]] && ! wit_lease_is_live "$active_lease" "$(date -u +%s)"; then
      assignees='[]'
    fi
  fi
  labels="$(wit_fm_field "$file" labels)"
  # `type` is additive — items created before the field existed have none, so an
  # empty read projects as JSON null (parity with the GitHub adapter's untyped case).
  type="$(wit_fm_field "$file" type)"
  [[ -n "$type" ]] || type="null"
  parent="$(wit_fm_field "$file" parent)"
  url="$(wit_fm_field "$file" url)"
  # Capture then iterate via here-string — a `< <(cmd)` process substitution whose
  # loop body itself forks (wit_item_file, wit_fm_field) intermittently deadlocks on
  # Git Bash/MSYS (bash/conventions.md gotchas: "Process substitution partial").
  local count=0 bid bnum bstate bfile blockers
  blockers="$(wit_blocked_by_ids "$file")"
  while IFS= read -r bid; do
    [[ -n "$bid" ]] || continue
    bnum="${bid##*#}"
    [[ "$bnum" =~ ^[0-9]+$ ]] || continue
    bfile="$(wit_item_file "$bnum")"
    [[ -f "$bfile" ]] || continue
    bstate="$(wit_fm_field "$bfile" state)"
    [[ "$bstate" == '"open"' ]] && count=$((count + 1))
  done <<<"$blockers"
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" \
    --argjson id "$id" --argjson title "$title" --argjson state "$state" \
    --argjson assignees "$assignees" --argjson labels "$labels" \
    --argjson type "$type" \
    --argjson parent "$parent" --argjson count "$count" --argjson url "$url" \
    '{schema_version: $sv, id: $id, title: $title, state: $state,
      assignees: $assignees, labels: $labels, type: $type, blocked_by_count: $count,
      parent_id: $parent, url: $url}'
}
