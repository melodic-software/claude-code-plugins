#!/usr/bin/env bash
# Contract tests for datamuse.sh. Fully offline: `curl` is replaced by a
# PATH-stub that records the full request argv and serves a canned body, so
# nothing here reaches api.datamuse.com and the suite is deterministic on a
# laptop with no network.
#
# Coverage:
#   - argument validation (no mode, no word, unknown mode) exits 1, prints the
#     usage banner, and issues NO request
#   - the usage banner still spans the modes and the LIMIT override, so
#     truncating the `sed` range that prints it is caught
#   - curl is invoked with the flags the script documents (-sS), since silent
#     mode without -S swallows the transport error this suite relies on
#   - happy-path response parsing: one TSV row per result, four tab-separated
#     fields, tags joined with commas, missing score/numSyllables defaulting to
#     0 and missing tags to an empty field
#   - API result order is preserved (the non-family modes do not re-sort)
#   - the mode -> query-parameter table (rel_rhy, rel_nry, rel_cns, rel_syn,
#     rel_ant, rel_trg, rel_jja, rel_jjb, ml, sl, sp), which is where a typo
#     silently returns the wrong relation
#   - LIMIT default 25, LIMIT override, and `syllables` pinning max=5
#   - a multi-word argument reaching the query as '+'-joined
#   - empty results are exit 0 with no output, never an error
#   - a nonzero curl exit propagates through the pipe (pipefail) with no rows
#     on stdout
#   - malformed JSON fails loudly instead of emitting partial TSV
#   - `family` merges near-rhyme and consonance: two requests, EACH carrying
#     md=s, deduped by word rather than by whole object, re-sorted by score
#     across BOTH sources
#
# Prerequisite: jq, which datamuse.sh itself requires. Absent, this suite fails
# loudly rather than skipping, because every parsing assertion below would be
# vacuous without it.
#
# Self-contained assertion helpers, per
# docs/conventions/shell-test-helpers/README.md: per-plugin duplication of this
# shape is the accepted default, not an opt-in.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/datamuse.sh"

# The suite drives LIMIT explicitly per case; an inherited one would silently
# rewrite the default-limit assertions.
unset LIMIT

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s - expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }
assert_nonzero() { if [[ "$2" -ne 0 ]]; then pass "$1"; else fail "$1" "nonzero exit" "exit $2"; fi; }

if [[ ! -f "$SCRIPT" ]]; then
  printf 'FAIL: datamuse.sh not found at %s\n' "$SCRIPT" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'FAIL: jq is required to test datamuse.sh (the script itself depends on it)\n' >&2
  exit 1
fi

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

STUB_BIN="$TEST_TMPDIR/stub-bin"
STUB_DATA="$TEST_TMPDIR/stub-data"
REQUEST_LOG="$STUB_DATA/requests.log"
STDOUT_FILE="$TEST_TMPDIR/stdout"
STDERR_FILE="$TEST_TMPDIR/stderr"
mkdir -p "$STUB_BIN"

# --- curl stub -------------------------------------------------------------
# Logs one line per invocation carrying the WHOLE argv, flags included, so the
# suite can pin the flags as well as the URL; then serves a per-relation canned
# body. Selecting the body by relation (rather than by call order) is what lets
# `family`'s two calls return different payloads.
cat >"$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
  case "$arg" in
    http*) url="$arg" ;;
    *) ;;
  esac
done
printf '%s\n' "$*" >>"$DATAMUSE_STUB_DATA/requests.log"
if [[ "${DATAMUSE_STUB_EXIT:-0}" -ne 0 ]]; then
  printf 'curl: (%s) stubbed transport failure\n' "$DATAMUSE_STUB_EXIT" >&2
  exit "$DATAMUSE_STUB_EXIT"
fi
body="$DATAMUSE_STUB_DATA/default.json"
case "$url" in
  *rel_nry=*)
    if [[ -f "$DATAMUSE_STUB_DATA/near.json" ]]; then body="$DATAMUSE_STUB_DATA/near.json"; fi
    ;;
  *rel_cns=*)
    if [[ -f "$DATAMUSE_STUB_DATA/cons.json" ]]; then body="$DATAMUSE_STUB_DATA/cons.json"; fi
    ;;
  *) ;;
esac
cat "$body"
STUB
chmod +x "$STUB_BIN/curl"

if ! PATH="$STUB_BIN:$PATH" command -v curl | grep -q "^$STUB_BIN/curl$"; then
  printf 'FAIL: the curl stub does not shadow the real curl; the suite would hit the network\n' >&2
  exit 1
fi

STUB_EXIT=0

# reset_stub [default-body-json] - fresh request log and a fresh body set.
reset_stub() {
  rm -rf "$STUB_DATA"
  mkdir -p "$STUB_DATA"
  : >"$REQUEST_LOG"
  STUB_EXIT=0
  printf '%s' "${1:-[]}" >"$STUB_DATA/default.json"
}

# set_body <near|cons> <json>
set_body() { printf '%s' "$2" >"$STUB_DATA/$1.json"; }

RC=0
OUT=""
ERR=""

# run_datamuse <args...> - runs the script against the stub with LIMIT unset.
run_datamuse() {
  RC=0
  PATH="$STUB_BIN:$PATH" DATAMUSE_STUB_DATA="$STUB_DATA" DATAMUSE_STUB_EXIT="$STUB_EXIT" \
    bash "$SCRIPT" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE" || RC=$?
  OUT="$(cat "$STDOUT_FILE")"
  ERR="$(cat "$STDERR_FILE")"
}

# run_datamuse_limit <limit> <args...> - same, with LIMIT exported.
run_datamuse_limit() {
  local limit="$1"
  shift
  RC=0
  PATH="$STUB_BIN:$PATH" DATAMUSE_STUB_DATA="$STUB_DATA" DATAMUSE_STUB_EXIT="$STUB_EXIT" \
    LIMIT="$limit" bash "$SCRIPT" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE" || RC=$?
  OUT="$(cat "$STDOUT_FILE")"
  ERR="$(cat "$STDERR_FILE")"
}

requests() { cat "$REQUEST_LOG"; }
request_count() { grep -c . "$REQUEST_LOG"; }
# How many logged requests carry <fixed-string> individually. A substring check
# over the whole log is satisfied by ONE matching request, which is the wrong
# question when the script issues several.
requests_matching() { grep -c -F -e "$1" "$REQUEST_LOG"; }
row() { sed -n "${1}p" "$STDOUT_FILE"; }
row_count() { grep -c . "$STDOUT_FILE"; }
# Number of rows whose tab-separated field count is not 4.
malformed_rows() { awk -F'\t' 'NF != 4 { n++ } END { print n + 0 }' "$STDOUT_FILE"; }

TAB=$'\t'

# --- argument validation: no request may be issued --------------------------

reset_stub
run_datamuse
assert_eq "no arguments -> exit 1" "1" "$RC"
assert_contains "no arguments prints the usage banner" "$ERR" "datamuse.sh rhyme"
assert_contains "usage banner names the API" "$ERR" "https://www.datamuse.com/api/"
# The banner is a line RANGE out of the script's own header, so it is pinned at
# both ends: `family` is the last mode listed and the LIMIT note sits below it.
# Narrowing the range drops one or both.
assert_contains "usage banner reaches the last mode listed" "$ERR" "datamuse.sh family"
assert_contains "usage banner documents the LIMIT override" "$ERR" "LIMIT=<n>"
assert_eq "no arguments issues no request" "0" "$(request_count)"
assert_eq "no arguments writes nothing to stdout" "" "$OUT"

reset_stub
run_datamuse rhyme
assert_eq "mode without a word -> exit 1" "1" "$RC"
assert_contains "mode without a word prints the usage banner" "$ERR" "datamuse.sh rhyme"
assert_eq "mode without a word issues no request" "0" "$(request_count)"

reset_stub
run_datamuse rhyme ""
assert_eq "mode with an empty word -> exit 1" "1" "$RC"
assert_eq "empty word issues no request" "0" "$(request_count)"

reset_stub
run_datamuse bogus lonely
assert_eq "unknown mode -> exit 1" "1" "$RC"
assert_contains "unknown mode names the mode" "$ERR" "unknown mode: bogus"
assert_contains "unknown mode also prints the usage banner" "$ERR" "datamuse.sh rhyme"
assert_eq "unknown mode issues no request" "0" "$(request_count)"

# --- happy path: response parsing and TSV shape -----------------------------

# Realistic md=s payload, plus one sparse entry: Datamuse omits `tags` for some
# results, and the script's own contract is to default the numeric fields to 0
# and the tag field to empty rather than to emit `null`.
RHYME_JSON='[
  {"word":"only","score":1097,"numSyllables":2,"tags":["adv","adj"]},
  {"word":"solely","score":1074,"numSyllables":2,"tags":["adv"]},
  {"word":"slowly"}
]'

reset_stub "$RHYME_JSON"
run_datamuse rhyme lonely
assert_eq "rhyme -> exit 0" "0" "$RC"
assert_eq "one row per result" "3" "$(row_count)"
assert_eq "every row has four tab-separated fields" "0" "$(malformed_rows)"
assert_eq "row 1 carries word, score, syllables, comma-joined tags" \
  "only${TAB}1097${TAB}2${TAB}adv,adj" "$(row 1)"
assert_eq "row 2 keeps a single tag unjoined" \
  "solely${TAB}1074${TAB}2${TAB}adv" "$(row 2)"
assert_eq "a sparse entry defaults score and syllables to 0 and tags to empty" \
  "slowly${TAB}0${TAB}0${TAB}" "$(row 3)"
assert_not_contains "no JSON null leaks into the TSV" "$OUT" "null"
assert_eq "one request per invocation" "1" "$(request_count)"
# -sS, not -s: silent WITHOUT show-error swallows the transport diagnostic the
# caller needs, and this suite asserts that diagnostic further down.
assert_eq "curl is invoked with -sS" "1" "$(requests_matching '-sS')"
assert_contains "the rhyme relation is requested" "$(requests)" "rel_rhy=lonely"
assert_contains "metadata flag md=s is requested" "$(requests)" "md=s"
assert_contains "the default limit is 25" "$(requests)" "max=25"
assert_contains "the request targets the Datamuse words endpoint" \
  "$(requests)" "https://api.datamuse.com/words?"

# The API returns its own ranking; the non-family modes must not re-sort it.
# A score-ascending payload makes a stray sort_by visible.
reset_stub '[{"word":"beta","score":10,"numSyllables":2,"tags":["n"]},{"word":"alpha","score":900,"numSyllables":2,"tags":["n"]}]'
run_datamuse near lonely
assert_eq "API order is preserved, not re-sorted" "beta" "$(row 1 | cut -f1)"
assert_eq "and the second row is the higher-scoring one" "alpha" "$(row 2 | cut -f1)"

# --- mode -> query-parameter table ------------------------------------------

MODE_QUERIES=(
  "rhyme rel_rhy"
  "near rel_nry"
  "cons rel_cns"
  "syn rel_syn"
  "ant rel_ant"
  "trg rel_trg"
  "jja rel_jja"
  "jjb rel_jjb"
  "means ml"
  "sounds sl"
  "pattern sp"
)
for pair in "${MODE_QUERIES[@]}"; do
  read -r mode key <<<"$pair"
  reset_stub "$RHYME_JSON"
  run_datamuse "$mode" winter
  assert_eq "$mode -> exit 0" "0" "$RC"
  assert_contains "$mode requests $key" "$(requests)" "$key=winter"
done

# --- limits -----------------------------------------------------------------

reset_stub "$RHYME_JSON"
run_datamuse_limit 50 near grief
assert_eq "LIMIT override -> exit 0" "0" "$RC"
assert_contains "LIMIT=50 reaches the query" "$(requests)" "max=50"
assert_not_contains "and the default is not also sent" "$(requests)" "max=25"

reset_stub "$RHYME_JSON"
run_datamuse syllables disappointment
assert_contains "syllables pins max=5" "$(requests)" "max=5"
assert_contains "syllables searches by letter pattern" "$(requests)" "sp=disappointment"

reset_stub "$RHYME_JSON"
run_datamuse_limit 50 syllables disappointment
assert_contains "syllables pins max=5 even under a LIMIT override" "$(requests)" "max=5"

# --- multi-word arguments ---------------------------------------------------

reset_stub "$RHYME_JSON"
run_datamuse means cold winter morning
assert_eq "multi-word argument -> exit 0" "0" "$RC"
assert_contains "spaces are joined with '+' in the query" "$(requests)" "ml=cold+winter+morning"
assert_not_contains "no raw space survives into the URL" "$(requests)" "cold winter"

# --- empty results are not an error -----------------------------------------

reset_stub '[]'
run_datamuse rhyme zzzzz
assert_eq "empty result set -> exit 0" "0" "$RC"
assert_eq "empty result set writes no rows" "0" "$(row_count)"
assert_eq "empty result set writes nothing to stdout" "" "$OUT"

# --- transport failure ------------------------------------------------------

reset_stub "$RHYME_JSON"
STUB_EXIT=6
run_datamuse rhyme lonely
assert_eq "a nonzero curl exit propagates through the pipe" "6" "$RC"
assert_eq "and no rows reach stdout" "0" "$(row_count)"
assert_contains "the transport error reaches stderr" "$ERR" "stubbed transport failure"

reset_stub
STUB_EXIT=7
set_body near '[]'
set_body cons '[]'
run_datamuse family stranger
assert_nonzero "family fails when its first request fails" "$RC"
assert_eq "and family emits no rows" "0" "$(row_count)"

# --- malformed JSON ---------------------------------------------------------

reset_stub 'not json at all'
run_datamuse rhyme lonely
assert_nonzero "malformed JSON fails loudly" "$RC"
assert_eq "malformed JSON emits no partial TSV" "0" "$(row_count)"
assert_contains "the parser error reaches stderr" "$ERR" "jq"

reset_stub '{"word":"only","score":1097}'
run_datamuse rhyme lonely
assert_nonzero "a JSON object where an array is expected fails" "$RC"
assert_eq "and emits no rows" "0" "$(row_count)"

# --- family: merge, dedupe, re-sort -----------------------------------------

# The duplicate word carries a DIFFERENT score and tag set in each payload, so
# the two entries are distinct objects: deduping on the whole object would keep
# both and yield four rows, which is what separates unique_by(.word) from a
# plain unique. Interleaved scores are what proves the merge re-sorts across
# BOTH sources instead of concatenating them.
reset_stub
set_body near '[
  {"word":"stranger","score":900,"numSyllables":2,"tags":["n"]},
  {"word":"danger","score":500,"numSyllables":2,"tags":["n"]}
]'
set_body cons '[
  {"word":"stranger","score":850,"numSyllables":2,"tags":["n","adj"]},
  {"word":"stringer","score":700,"numSyllables":2,"tags":["n"]}
]'
run_datamuse family stranger
assert_eq "family -> exit 0" "0" "$RC"
assert_eq "family issues exactly two requests" "2" "$(request_count)"
assert_contains "family requests near rhymes" "$(requests)" "rel_nry=stranger"
assert_contains "family requests consonance" "$(requests)" "rel_cns=stranger"
assert_eq "EACH family request sends md=s" "2" "$(requests_matching 'md=s')"
assert_eq "family dedupes by word, not by whole object" "3" "$(row_count)"
assert_eq "the surviving duplicate is the near-rhyme copy" "900" "$(row 1 | cut -f2)"
assert_eq "family rows keep the four-field shape" "0" "$(malformed_rows)"
assert_eq "family sorts by score across both sources (1)" "stranger" "$(row 1 | cut -f1)"
assert_eq "family sorts by score across both sources (2)" "stringer" "$(row 2 | cut -f1)"
assert_eq "family sorts by score across both sources (3)" "danger" "$(row 3 | cut -f1)"
assert_eq "the deduped row keeps its tags" "n" "$(row 1 | cut -f4)"

reset_stub
set_body near '[]'
set_body cons '[]'
run_datamuse family nothingrhymeswiththis
assert_eq "family with two empty result sets -> exit 0" "0" "$RC"
assert_eq "family with two empty result sets writes no rows" "0" "$(row_count)"

reset_stub
set_body near '[{"word":"danger","score":500,"numSyllables":2,"tags":["n"]}]'
set_body cons '[]'
run_datamuse_limit 40 family stranger
assert_eq "family under a LIMIT override -> exit 0" "0" "$RC"
assert_contains "family passes LIMIT to the near-rhyme request" "$(requests)" "rel_nry=stranger&md=s&max=40"
assert_contains "family passes LIMIT to the consonance request" "$(requests)" "rel_cns=stranger&md=s&max=40"
assert_eq "one side empty still yields the other side's rows" "1" "$(row_count)"

[[ $FAILED -eq 0 ]] || exit 1
echo "All cases passed ($CASE_NUM)."
