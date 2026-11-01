# shellcheck shell=bash
# The recurrence marker the add-recurrence verb writes (CONTRACT.md "Verbs (core public
# surface)"). One marker line records one sighting of a signal, keyed by its source link;
# add-recurrence writes nothing when the item already carries a marker for that link.

readonly WIT_RECURRENCE_MARKER='<!-- work-item-recurrence v1 '

# wit_recurrence_link_ok <link>: 0 when the link is an http(s) URL with no whitespace.
wit_recurrence_link_ok() {
  [[ "$1" =~ ^https?://[^[:space:]]+$ ]]
}

# wit_recurrence_marker <source-link> <note>: the marker line for one sighting. Every `>` in
# the JSON is written as the escape backslash-u003e, so a link or note holding ` -->` cannot
# end the comment early.
wit_recurrence_marker() {
  local json
  json="$(jq -cn --arg link "$1" --arg note "$2" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{source_link: $link, note: $note, recorded_at: $at}' | sed 's/>/\\u003e/g')" || return 1
  printf '%s%s -->\n' "$WIT_RECURRENCE_MARKER" "$json"
}

# wit_recurrence_source_link <line>: the source link a marker line records; empty when the
# line is not a recurrence marker or its JSON does not parse.
wit_recurrence_source_link() {
  local line="$1"
  case "$line" in
  "$WIT_RECURRENCE_MARKER"*" -->"*)
    line="${line#"$WIT_RECURRENCE_MARKER"}"
    jq -r '.source_link // empty' <<<"${line%% -->*}" 2>/dev/null || true
    ;;
  *) ;;
  esac
}

# wit_recurrence_has_link <link> <marker-lines>: 0 when one of the newline-separated lines
# is a marker recording exactly that link.
wit_recurrence_has_link() {
  local link="$1" line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$(wit_recurrence_source_link "$line")" == "$link" ]] && return 0
  done <<<"$2"
  return 1
}
