#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH_DOCS="$SCRIPT_DIR/fetch-docs.sh"
DOCS_CACHE="$SCRIPT_DIR/docs-cache.sh"
SOURCES="$SCRIPT_DIR/../context/mechanics-sources.tsv"

usage() {
  cat <<'EOF'
quote-check.sh: check each mechanics quote against its live docs section.

Usage: quote-check.sh

Reads context/mechanics-sources.tsv and takes no arguments. Prints one line per
record: verified <id>; drift <id> <url> with the stored and fetched sentences on
the next two lines; or unverified <id> as of <as_of> when the page is unread.

Exit: 0 whatever the results; 2 for an argument or an unreadable list.
EOF
}

if [[ $# -eq 1 && ("$1" == -h || "$1" == --help) ]]; then
  usage
  exit 0
fi
if [[ $# -gt 0 ]]; then
  echo "quote-check: takes no arguments (got: $*)" >&2
  usage >&2
  exit 2
fi

FIXTURE_SET=0
[[ -z "${QUOTE_CHECK_FIXTURE_DIR+x}" ]] || FIXTURE_SET=1
if [[ $FIXTURE_SET -eq 1 && -n "${QUOTE_CHECK_SOURCES:-}" ]]; then
  SOURCES="$QUOTE_CHECK_SOURCES"
fi
[[ -f "$SOURCES" && -r "$SOURCES" ]] || {
  echo "quote-check: cannot read the source list: $SOURCES" >&2
  exit 2
}

WORK="$(mktemp -d)" || {
  echo "quote-check: could not create a temp directory" >&2
  exit 2
}
trap 'rm -rf "$WORK"' EXIT

IDS=() URLS=() QUOTES=() AS_OF=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ -n "$line" ]] || continue
  f=()
  while [[ "$line" == *$'\t'* ]]; do
    f+=("${line%%$'\t'*}")
    line="${line#*$'\t'}"
  done
  f+=("$line")
  [[ "${f[0]}" != id ]] || continue
  if [[ ${#f[@]} -ne 4 || -z "${f[0]}" || -z "${f[1]}" || -z "${f[2]}" ]]; then
    echo "quote-check: skipped a record that is not id, url, quote, as_of: ${f[0]}" >&2
    continue
  fi
  IDS+=("${f[0]}") URLS+=("${f[1]}") QUOTES+=("${f[2]}") AS_OF+=("${f[3]}")
done <"$SOURCES"
[[ ${#IDS[@]} -gt 0 ]] || exit 0

FETCH_ARGS=(--cache --max-age 0 --out "$WORK/docs")
if [[ $FIXTURE_SET -eq 1 ]]; then
  export FETCH_DOCS_FIXTURE_DIR="$QUOTE_CHECK_FIXTURE_DIR"
  FETCH_ARGS+=(--cache-dir "$WORK/cache")
fi
FETCH_DOCS_CLAUDE_BIN='' bash "$FETCH_DOCS" "${FETCH_ARGS[@]}" "${URLS[@]}" >/dev/null 2>&1
MANIFEST="$WORK/docs/manifest.json"

# shellcheck disable=SC2016 # awk source, not shell
COMPARE_AWK='
function rendered(s,   p, o, k, c, n, seg, i) {
  sub(/\r$/, "", s)
  # [text](target) becomes text. Found by index, not by a bracket regex, which
  # mawk and gawk read differently.
  while ((p = index(s, "](")) > 0) {
    o = 0
    for (k = p - 1; k >= 1; k--) if (substr(s, k, 1) == "[") { o = k; break }
    c = index(substr(s, p + 2), ")")
    if (!o || !c) break
    s = substr(s, 1, o - 1) substr(s, o + 1, p - o - 1) substr(s, p + 2 + c)
  }
  # Bold markers go only outside code spans: the odd pieces between backticks.
  n = split(s, seg, "`")
  s = ""
  for (i = 1; i <= n; i++) {
    if (i % 2) gsub(/\*\*/, "", seg[i])
    s = s (i > 1 ? "`" : "") seg[i]
  }
  if (s ~ /^[ \t]*\|/) {
    if (s ~ /^[ \t|:-]+$/) return ""
    sub(/^[ \t]*\|/, "", s)
    sub(/\|[ \t]*$/, "", s)
    gsub(/[ \t]*\|[ \t]*/, " | ", s)
  }
  gsub(/[ \t]+/, " ", s)
  sub(/^ /, "", s)
  sub(/ $/, "", s)
  return s
}
function words(s, set,   n, i, w, t) {
  n = split(tolower(s), w, /[^a-z0-9]+/)
  t = 0
  for (i = 1; i <= n; i++) if (w[i] != "" && !(w[i] in set)) { set[w[i]] = 1; t++ }
  return t
}
{
  line = rendered($0)
  if (line == "") next
  lines[++nl] = line
  joined = joined (joined == "" ? "" : " ") line
}
END {
  quote = ENVIRON["QC_QUOTE"]
  gsub(/[ \t\r\n]+/, " ", quote)
  sub(/^ /, "", quote)
  sub(/ $/, "", quote)
  if (quote != "" && index(joined, quote)) { print "verified"; exit }
  words(quote, want)
  best = ""
  top = 0
  for (i = 1; i <= nl; i++) {
    rest = lines[i]
    while (rest != "") {
      if (match(rest, /[.!?] /)) {
        sentence = substr(rest, 1, RSTART)
        rest = substr(rest, RSTART + 2)
      } else {
        sentence = rest
        rest = ""
      }
      delete got
      words(sentence, got)
      score = 0
      for (w in got) if (w in want) score++
      if (score > top) { top = score; best = sentence }
    }
  }
  if (best == "") best = "(no sentence in the section shares a word with the quote)"
  print "drift\t" best
}'

# shellcheck disable=SC2016 # awk source, not shell
SECTION_AWK='
function squash(s) { s = tolower(s); gsub(/[^a-z0-9]/, "", s); return s }
{ n = split($7, part, " > "); if (squash(part[n]) == squash(anchor)) { print $1; exit } }'

unverified() { printf 'unverified %s as of %s\n' "$1" "${2:-unknown}"; }
drift() { printf 'drift %s %s\n  stored:  %s\n  fetched: %s\n' "$1" "$2" "$3" "$4"; }

for i in "${!IDS[@]}"; do
  id="${IDS[$i]}" url="${URLS[$i]}" quote="${QUOTES[$i]}"
  page="${url%%#*}"
  anchor=""
  [[ "$url" != *#* ]] || anchor="${url#*#}"
  rec="$(jq -r --arg u "${page%/}.md" \
    '.pages[] | select(.url == $u) | [.state, (.stale | tostring), (.file // "")] | join("\t")' \
    "$MANIFEST" 2>/dev/null | head -n 1)"
  IFS=$'\t' read -r state stale file <<<"${rec%$'\r'}"
  if [[ "${state:-}" != read || "${stale:-}" == true || -z "${file:-}" || ! -s "$file" ]]; then
    unverified "$id" "${AS_OF[$i]}"
    continue
  fi
  if [[ -z "$anchor" ]]; then
    section="$(cat "$file")"
  else
    sid="$(bash "$DOCS_CACHE" map --file "$file" 2>/dev/null | awk -F'\t' -v anchor="$anchor" "$SECTION_AWK")"
    if [[ -z "$sid" ]]; then
      drift "$id" "$url" "$quote" "(the page has no section #$anchor)"
      continue
    fi
    section="$(bash "$DOCS_CACHE" --escalate-percent 100 --escalate-bytes 999999999999999999 \
      slice --file "$file" "$sid" 2>/dev/null)"
  fi
  result="$(printf '%s\n' "$section" | QC_QUOTE="$quote" awk "$COMPARE_AWK")"
  case "$result" in
  verified) printf 'verified %s\n' "$id" ;;
  drift$'\t'*) drift "$id" "$url" "$quote" "${result#drift$'\t'}" ;;
  *) unverified "$id" "${AS_OF[$i]}" ;;
  esac
done
exit 0
