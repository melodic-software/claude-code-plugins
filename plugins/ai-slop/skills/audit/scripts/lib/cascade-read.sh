# shellcheck shell=bash
# One reader for the three config-cascade key shapes detect.sh uses.
# Sourceable; not invoked directly. A layer is a YAML file (*.yaml, *.yml; read
# with lib/parse-concern-value.sh and its yaml-subset.awk parser) or a legacy
# JSON file (read with jq, which is then required). A layer its parser refuses
# (nonzero, including trailing bytes after a valid JSON value, or a YAML
# document outside the subset) is skipped whole.
#
# Every reader records the layer that supplied the value it returns, so a
# resolver can report it: cascade_scalar_layer, cascade_list_layer and
# cascade_slug_layer[<slug>] are the last layer that defined the key (empty
# when none did).

_CASCADE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../lib" 2>/dev/null && pwd)"
_CASCADE_PCV="$_CASCADE_LIB/parse-concern-value.sh"
_CASCADE_AWK="$_CASCADE_LIB/yaml-subset.awk"

declare -gA cascade_slug_layer=()
cascade_scalar_layer=""
cascade_list_layer=""

_cascade_is_yaml() { [[ "$1" == *.yaml || "$1" == *.yml ]]; }

# _cascade_usable <layer>: the layer can be parsed at all. A YAML layer must be
# inside the parser's subset; a JSON layer needs jq and a single valid value.
_cascade_usable() {
  if _cascade_is_yaml "$1"; then
    [[ -f "$_CASCADE_PCV" ]] && bash "$_CASCADE_PCV" --strict "$1" __probe__ >/dev/null 2>&1
  else
    command -v jq >/dev/null 2>&1 && jq -e . "$1" >/dev/null 2>&1
  fi
}

# cascade::scalar <dest> <jq-filter> <layer>...
# Last layer whose filter yields a non-empty value wins. A missing key or an
# empty value leaves the earlier value standing. The filter is a jq path
# (`.thresholds.ai_vocabulary`); a YAML layer reads the same dotted key.
cascade::scalar() {
  local -n dest_ref="$1"
  local filter="$2"
  shift 2
  local layer value out="" out_layer=""
  for layer in "$@"; do
    if _cascade_is_yaml "$layer"; then
      _cascade_usable "$layer" || continue
      value="$(bash "$_CASCADE_PCV" "$layer" "${filter#.}" 2>/dev/null)" || continue
    else
      command -v jq >/dev/null 2>&1 || continue
      value="$(jq -r "${filter} // empty" "$layer" 2>/dev/null)" || continue
    fi
    value="${value//$'\r'/}"
    if [[ -n "$value" ]]; then
      out="$value"
      out_layer="$layer"
    fi
  done
  # shellcheck disable=SC2034  # caller reads the winning layer after return
  cascade_scalar_layer="$out_layer"
  # shellcheck disable=SC2034  # nameref: writes the caller's variable
  dest_ref="$out"
}

# _cascade_yaml_key_present <layer> <key>: a top-level `key:` line exists, even
# with an empty value (`key: []` or a bare `key:`), which the flattener prints
# nothing for.
_cascade_yaml_key_present() {
  grep -Eq "^$2[[:space:]]*:" "$1" 2>/dev/null
}

# cascade::list <dest-array> <key> <layer>...
# Wholesale replace, presence-keyed: a layer that has the key replaces the
# list, and an explicit empty array clears it. A layer that lacks the key, or
# that its parser refuses, leaves the list standing. Sets cascade_list_layer to
# the last layer that defined the key (empty when none did). Elements keep their
# internal spaces; one output line is one element.
cascade::list() {
  local dest="$1" key="$2"
  shift 2
  local -n dest_ref="$dest"
  local layer v
  cascade_list_layer=""
  for layer in "$@"; do
    if _cascade_is_yaml "$layer"; then
      _cascade_usable "$layer" || continue
      _cascade_yaml_key_present "$layer" "$key" || continue
      v="$(bash "$_CASCADE_PCV" --list "$layer" "$key" 2>/dev/null)" || continue
    else
      command -v jq >/dev/null 2>&1 || continue
      jq -e --arg k "$key" 'has($k)' "$layer" >/dev/null 2>&1 || continue
      v="$(jq -r --arg k "$key" '.[$k][]' "$layer" 2>/dev/null)" || continue
    fi
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

# _cascade_yaml_slug_rows <layer> <key>: print `slug<TAB>globs` for each entry of
# the mapping at <key>; globs are space-joined and empty for `slug: []`.
_cascade_yaml_slug_rows() {
  local layer="$1" key="$2" records
  records="$(LC_ALL=C awk -f "$_CASCADE_AWK" "$layer" 2>/dev/null)" || return 1
  records="${records//$'\r'/}"
  # Slugs the layer names without an inline list (`slug: []`, or a bare `slug:`
  # whose items follow) come first: the rows below then re-set every slug that
  # does have items, so only a slug with an empty list stays cleared.
  KEY="$key" LC_ALL=C awk '
    /^[^[:space:]#]/ { inb = ($0 ~ ("^" ENVIRON["KEY"] "[[:space:]]*:")); next }
    inb && /^[[:space:]]+[A-Za-z0-9_-]+[[:space:]]*:[[:space:]]*(\[[[:space:]]*\])?[[:space:]]*(#.*)?$/ {
      s = $0; sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]*:.*/, "", s); print s "\t"
    }
  ' "$layer"
  KEY="$key" LC_ALL=C awk -F '\t' '
    BEGIN { k = ENVIRON["KEY"] "." ; n = length(k) }
    index($1, k) == 1 {
      rest = substr($1, n + 1)
      if (match(rest, /\.[0-9]+$/) == 0) next
      slug = substr(rest, 1, RSTART - 1)
      val = substr($0, length($1) + 2)
      if (!(slug in seen)) { seen[slug] = 1; order[++cnt] = slug }
      globs[slug] = (slug in globs && globs[slug] != "") ? globs[slug] " " val : val
    }
    END { for (i = 1; i <= cnt; i++) print order[i] "\t" globs[order[i]] }
  ' <<<"$records"
}

# cascade::slug_map <dest-assoc> <key> <layer>...
# Per-slug replace. A later layer's entry for a slug replaces that slug only.
# An explicit empty array clears the slug. A layer its parser refuses is skipped
# whole, so a truncated object cannot apply the entries jq printed before
# failing. Sets cascade_slug_layer[<slug>] to the layer that supplied the slug.
cascade::slug_map() {
  local dest="$1" key="$2"
  shift 2
  local -n map_ref="$dest"
  local layer raw slug globs
  cascade_slug_layer=()
  for layer in "$@"; do
    if _cascade_is_yaml "$layer"; then
      _cascade_usable "$layer" || continue
      raw="$(_cascade_yaml_slug_rows "$layer" "$key")" || continue
    else
      command -v jq >/dev/null 2>&1 || continue
      raw="$(jq -r --arg k "$key" '
        if has($k) then
          (.[$k] | to_entries[] | [.key, (.value | join(" "))] | @tsv)
        else
          empty
        end
      ' "$layer" 2>/dev/null)" || continue
    fi
    raw="${raw//$'\r'/}"
    [[ -z "$raw" ]] && continue
    while IFS=$'\t' read -r slug globs; do
      [[ -z "$slug" ]] && continue
      if [[ -z "${globs//[[:space:]]/}" ]]; then
        # Single quotes: unset expands a double-quoted subscript a second
        # time, so a config slug spelled $(cmd) would run.
        unset 'map_ref[$slug]'
        unset 'cascade_slug_layer[$slug]'
      else
        # shellcheck disable=SC2034  # nameref: writes the caller's associative array
        map_ref["$slug"]="$globs"
        # shellcheck disable=SC2034  # caller reads the supplying layer after return
        cascade_slug_layer["$slug"]="$layer"
      fi
    done <<<"$raw"
  done
}
