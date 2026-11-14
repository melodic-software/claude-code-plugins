# shellcheck shell=bash
# shellcheck disable=SC2034 # False positive: the sourcing script reads the BASE_FILE_* results.
# Reads a file fetched from a repository's base branch: a `gh api -i` response
# or the file's own text, on stdin. Sourced by the readers of settings in
# docs/conventions/source-control.yaml, the path being CONVENTION_KEY_YAML_REL.
#
#   base_file_load (- | --http-response)
#       Sets BASE_FILE_STATE: ok (BASE_FILE_DOC holds the text), absent (a 404),
#       or failed (BASE_FILE_REASON says why: the input holds a NUL byte, no
#       response, no status line, any other status).
#   base_file_records
#       Parses BASE_FILE_DOC into BASE_FILE_RECORDS; returns 1 and sets
#       BASE_FILE_STATE=failed with the reason when the parser rejects it.
#   base_file_read_key (- | --http-response) <key>
#       Both of the above, then BASE_FILE_VALUE holds <key>'s value and
#       BASE_FILE_HAS is 1 when the file sets it. A key nested under <key> reads
#       as "(not a single value)".
#   base_file_list_check <key>
#       For a top-level list of mappings under <key>, sets BASE_FILE_BLOCK to the
#       list's own lines and compares its items and keys with the parsed
#       records, since the parser emits no record for an empty item or a key
#       with no value. Returns 1 with BASE_FILE_REASON set on a mismatch. Run
#       after base_file_records.

BASE_FILE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=convention-key.sh
source "$BASE_FILE_LIB_DIR/convention-key.sh"

base_file_load() {
  local mode="$1" input response status
  BASE_FILE_STATE=failed BASE_FILE_DOC="" BASE_FILE_REASON=""
  # A command substitution drops NUL bytes (`fal\0se` would read as `false`), so
  # stdin goes to a file and is checked before any variable holds it.
  input="$(mktemp)" || {
    BASE_FILE_REASON="no temporary file for the input"
    return 0
  }
  cat >"$input"
  if (($(tr -d '\000' <"$input" | wc -c) != $(wc -c <"$input"))); then
    rm -f "$input"
    BASE_FILE_REASON="the input holds a NUL byte"
    return 0
  fi
  response="$(cat "$input")"
  rm -f "$input"
  if [[ "$mode" == - ]]; then
    BASE_FILE_STATE=ok BASE_FILE_DOC="$response"
    return 0
  fi
  if [[ -z "$response" ]]; then
    BASE_FILE_REASON="the base read returned no response"
    return 0
  fi
  status="${response%%$'\n'*}"
  status="${status%$'\r'}"
  if [[ ! "$status" =~ ^HTTP/[0-9.]+\ ([0-9]{3}) ]]; then
    BASE_FILE_REASON="the base read returned no status line"
    return 0
  fi
  case "${BASH_REMATCH[1]}" in
    200)
      BASE_FILE_STATE=ok
      BASE_FILE_DOC="$(awk 'body { print; next } { sub(/\r$/, "") } $0 == "" { body = 1 }' <<<"$response")"
      ;;
    404) BASE_FILE_STATE=absent ;;
    *) BASE_FILE_REASON="the base read returned $status" ;;
  esac
}

base_file_records() {
  BASE_FILE_RECORDS=""
  if ! BASE_FILE_RECORDS="$(LC_ALL=C awk -f "$BASE_FILE_LIB_DIR/yaml-subset.awk" <<<"$BASE_FILE_DOC")"; then
    BASE_FILE_STATE=failed
    BASE_FILE_REASON="$CONVENTION_KEY_YAML_REL does not parse: $(awk -F '\t' '$1 == "error" { print "line " $2 ": " $3 }' <<<"$BASE_FILE_RECORDS")"
    return 1
  fi
}

base_file_list_check() {
  local key="$1" q="[\"']?" items=-1 keys records
  # The parser's own normalization: a CR before each line end, a byte-order
  # mark, and the base indent of the first content line.
  BASE_FILE_BLOCK=$(LC_ALL=C awk -v key="$key" -v q="$q" '
    { sub(/\r$/, "") }
    NR == 1 { sub(/^\357\273\277/, "") }
    /^[ \t]*(#.*)?$/ { if (inside) print; next }
    !based { match($0, /^[ \t]*/); base = substr($0, 1, RLENGTH); based = 1 }
    substr($0, 1, length(base)) == base { $0 = substr($0, length(base) + 1) }
    $0 ~ "^" q key q "[ \t]*:" { inside = 1; next }
    inside && /^[^ \t#-]/ { inside = 0 }
    inside' <<<"$BASE_FILE_DOC")
  records=$(awk -F '\t' -v key="$key" 'index($1, key ".") == 1 { n++ } END { print n + 0 }' <<<"$BASE_FILE_RECORDS")
  while IFS=$'\t' read -r k _; do
    [[ "$k" == "$key".* ]] || continue
    k="${k#"$key".}"
    k="${k%%.*}"
    [[ "$k" =~ ^[0-9]+$ ]] || continue
    ((k <= items)) || items=$k
  done <<<"$BASE_FILE_RECORDS"
  if (($(grep -cE '^[[:space:]]*-([[:space:]]|$)' <<<"$BASE_FILE_BLOCK") != items + 1)); then
    BASE_FILE_REASON="$key holds an empty item"
    return 1
  fi
  keys=$(grep -cE "^[[:space:]]*(-[[:space:]]+)?${q}[A-Za-z0-9_.-]+${q}[[:space:]]*:([[:space:]]|\$)" <<<"$BASE_FILE_BLOCK")
  if ((keys != records)); then
    BASE_FILE_REASON="$key item has a key with no value"
    return 1
  fi
}

base_file_read_key() {
  local mode="$1" key="$2" k v
  BASE_FILE_VALUE="" BASE_FILE_HAS=0
  base_file_load "$mode"
  [[ "$BASE_FILE_STATE" == ok ]] || return 0
  base_file_records || return 0
  while IFS=$'\t' read -r k v; do
    case "$k" in
      "$key") BASE_FILE_VALUE="$v" BASE_FILE_HAS=1 ;;
      "$key".*)
        BASE_FILE_VALUE="(not a single value)" BASE_FILE_HAS=1
        return 0
        ;;
      *) ;;
    esac
  done <<<"$BASE_FILE_RECORDS"
}
