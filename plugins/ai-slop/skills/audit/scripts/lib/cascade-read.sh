# shellcheck shell=bash
# One reader for the three config-cascade key shapes detect.sh uses.
# Sourceable; not invoked directly. jq is required; a layer jq refuses
# (nonzero, including trailing bytes after a valid value) is skipped whole.

# cascade::scalar <dest> <jq-filter> <layer>...
# Last layer whose filter yields a non-empty value wins. A missing key or an
# empty value leaves the earlier value standing.
cascade::scalar() {
  local -n dest_ref="$1"
  local filter="$2"
  shift 2
  local layer value out=""
  for layer in "$@"; do
    value="$(jq -r "${filter} // empty" "$layer" 2>/dev/null)" || continue
    value="${value//$'\r'/}"
    [[ -n "$value" ]] && out="$value"
  done
  # shellcheck disable=SC2034  # nameref: writes the caller's variable
  dest_ref="$out"
}

# cascade::list <dest-array> <key> <layer>...
# Wholesale replace, presence-keyed: a layer that has the key replaces the
# list, and an explicit empty array clears it. A layer that lacks the key, or
# that jq refuses, leaves the list standing. Sets cascade_list_layer to the
# last layer that defined the key (empty when none did). Elements keep their
# internal spaces; one jq output line is one element.
cascade::list() {
  local dest="$1" key="$2"
  shift 2
  local -n dest_ref="$dest"
  local layer v
  cascade_list_layer=""
  for layer in "$@"; do
    jq -e --arg k "$key" 'has($k)' "$layer" >/dev/null 2>&1 || continue
    v="$(jq -r --arg k "$key" '.[$k][]' "$layer" 2>/dev/null)" || continue
    v="${v//$'\r'/}"
    # shellcheck disable=SC2034  # caller reads the winning layer after return
    cascade_list_layer="$layer"
    if [[ -n "${v//[[:space:]]/}" ]]; then
      mapfile -t dest_ref <<<"$v"
    else
      # shellcheck disable=SC2034  # nameref: clears the caller's array
      dest_ref=()
    fi
  done
}

# cascade::slug_map <dest-assoc> <key> <layer>...
# Per-slug replace. A later layer's entry for a slug replaces that slug only.
# An explicit empty array clears the slug. A layer jq refuses is skipped whole,
# so a truncated object cannot apply the entries jq printed before failing.
cascade::slug_map() {
  local dest="$1" key="$2"
  shift 2
  local -n map_ref="$dest"
  local layer raw slug globs
  for layer in "$@"; do
    raw="$(jq -r --arg k "$key" '
      if has($k) then
        (.[$k] | to_entries[] | [.key, (.value | join(" "))] | @tsv)
      else
        empty
      end
    ' "$layer" 2>/dev/null)" || continue
    raw="${raw//$'\r'/}"
    [[ -z "$raw" ]] && continue
    while IFS=$'\t' read -r slug globs; do
      [[ -z "$slug" ]] && continue
      if [[ -z "${globs//[[:space:]]/}" ]]; then
        unset "map_ref[$slug]"
      else
        # shellcheck disable=SC2034  # nameref: writes the caller's associative array
        map_ref["$slug"]="$globs"
      fi
    done <<<"$raw"
  done
}
