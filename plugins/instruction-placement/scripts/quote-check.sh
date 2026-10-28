#!/usr/bin/env bash
# quote-check.sh: are the mechanics quotes still on their docs pages?
#
# Reads the fixed list in ../context/mechanics-sources.tsv (id, url, quote,
# as_of), fetches each page once through fetch-docs.sh --cache, takes the
# section the URL's anchor names with docs-cache.sh slice, and prints one
# result per record:
#
#   verified <id>                  the quote is in that section
#   drift <id> <url>               it is not; the next two lines are the stored
#     stored:  <quote>             quote and the section's closest sentence
#     fetched: <sentence>
#   unverified <id> as of <as_of>  the page could not be read fresh
#
# It takes no URL or any other argument: what it fetches is the shipped list
# and nothing else. Every fetch goes through fetch-docs.sh, so this script
# makes no request of its own.
#
# Comparison follows the quote rule in ../context/verified-mechanics.md
# ("Pointer records"): the section is read as the page renders it, link markup
# and bold dropped, code spans kept, a table row's cells joined with ` | `, and
# every whitespace run read as one space.
#
# A section is the heading whose text, reduced to ASCII letters and digits,
# equals the anchor reduced the same way, so a docs slug rule that drops or
# keeps punctuation still matches. A page that no longer has the heading is
# drift: the page was read and the quote's section is gone. A URL with no
# anchor is checked against the whole page.
#
# Every page is asked of the server on every run. A page that is not read
# fresh, including cached bytes standing in for a failed fetch, is unverified:
# those bytes say what the page said, not what it says.
#
# Exit: 0 whatever the results are (the lines are the result); 2 for an
# argument or an unreadable list.
#
# Test seam:
#   QUOTE_CHECK_FIXTURE_DIR  a directory of page snapshots in fetch-docs.sh's
#       fixture layout (llms.txt and <slug>.md). Set means no network: it is
#       passed on as FETCH_DOCS_FIXTURE_DIR, and the cache is a temporary one.
#   QUOTE_CHECK_SOURCES      the list to read instead of the shipped one; read
#       only with QUOTE_CHECK_FIXTURE_DIR set, so a live run fetches only the
#       shipped list.

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

# Bash 3.2 has no mapfile: the records go into parallel arrays. Fields are
# split by hand: read with a tab IFS would merge an empty field into the next.
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

# One fetch for every page: fetch-docs.sh reads each slug once however many
# records cite it, and ignores the #fragment. --max-age 0 asks the server every
# time (a cached page costs a conditional request), so a page read within the
# cache's TTL is never taken as current, and a failed fetch is unread.
FETCH_ARGS=(--cache --max-age 0 --out "$WORK/docs")
if [[ $FIXTURE_SET -eq 1 ]]; then
  export FETCH_DOCS_FIXTURE_DIR="$QUOTE_CHECK_FIXTURE_DIR"
  FETCH_ARGS+=(--cache-dir "$WORK/cache")
fi
FETCH_DOCS_CLAUDE_BIN='' bash "$FETCH_DOCS" "${FETCH_ARGS[@]}" "${URLS[@]}" >/dev/null 2>&1
MANIFEST="$WORK/docs/manifest.json"

# Reads the section on stdin and the quote from QC_QUOTE. Prints `verified`, or
# `drift<TAB><the sentence sharing the most words with the quote>`.
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

# The heading the anchor names: its text and the anchor, each reduced to ASCII
# letters and digits, are equal.
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
    # A URL with no anchor names the whole page.
    section="$(cat "$file")"
  else
    sid="$(bash "$DOCS_CACHE" map --file "$file" 2>/dev/null | awk -F'\t' -v anchor="$anchor" "$SECTION_AWK")"
    if [[ -z "$sid" ]]; then
      drift "$id" "$url" "$quote" "(the page has no section #$anchor)"
      continue
    fi
    # The escalation limits are raised so a large section prints alone, never
    # the whole page: a quote that moved to another section is drift.
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
