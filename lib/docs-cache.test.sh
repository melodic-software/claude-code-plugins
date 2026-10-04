#!/usr/bin/env bash
# Self-contained tests for lib/docs-cache.sh (no external test lib; the copies ship with the plugins).
#
# Every case runs against a store under this suite's temp directory, never the
# user's cache. DOCS_CACHE_NOW pins the clock so timestamps are known values.
#
# Markdown with backticks must reach the files unexpanded, so single quotes are
# the correct spelling.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/docs-cache.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
unset DOCS_CACHE_DIR DOCS_CACHE_NOW

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

sha() { sha256sum | cut -d' ' -f1; }

# dc <store> <args...>: the CLI against one store.
dc() {
  local store="$1"
  shift
  bash "$SCRIPT" --cache-dir "$store" "$@"
}

URL='https://docs.test/docs/en/page.md'
T1=1000000000
T1_ISO='2001-09-09T01:46:40Z'
T2=1000000100
T3=1000086500
T3_ISO='2001-09-10T01:48:20Z'

# entries_for <store> <key>: how many entry directories the key has.
entries_for() {
  find "$1/entries" -mindepth 1 -maxdepth 1 -type d -name "$2-*" | wc -l | tr -d ' '
}
# leftovers <store>: temp names left in the store.
leftovers() {
  find "$1" -name '.tmp-*' | wc -l | tr -d ' '
}

# The page every map case starts from. Line numbers, hand-counted:
#  1 intro               (before any heading: no section)
#  2 # Top
#  3 top body
#  4 ## Child A
#  5 a body
#  6 ```
#  7 # not a heading     (inside a fence)
#  8 ```
#  9 ## Child B
# 10 b body
PAGE="$TEST_TMPDIR/page.md"
printf '%s\n' 'intro' '# Top' 'top body' '## Child A' 'a body' '```' '# not a heading' '```' '## Child B' 'b body' >"$PAGE"

# --- key: normalized URL plus format ---------------------------------------------
S="$TEST_TMPDIR/s-key"
want="$(printf '%s\n%s' 'https://docs.test/docs/en/page.md' markdown | sha)"
assert_eq "key: sha256 of the normalized URL, a newline and the format" "$want" "$(dc "$S" key "$URL" markdown)"
assert_eq "key: scheme and host case and a fragment do not change it" "$want" "$(dc "$S" key 'HTTPS://Docs.Test/docs/en/page.md#part' markdown)"
assert_eq "key: path case does" 0 "$([[ "$(dc "$S" key 'https://docs.test/docs/en/Page.md' markdown)" == "$want" ]] && echo 1 || echo 0)"
assert_eq "key: the format does" 0 "$([[ "$(dc "$S" key "$URL" html-converted)" == "$want" ]] && echo 1 || echo 0)"
assert_eq "key: reading a key creates no store" 0 "$([[ -e "$S" ]] && echo 1 || echo 0)"

# --- map: fence-aware, own-body hash ---------------------------------------------
S="$TEST_TMPDIR/s-map"
h1="$(printf 'top body\n' | sha)"
h2="$(printf 'a body\n```\n# not a heading\n```\n' | sha)"
h3="$(printf 'b body\n' | sha)"
want="$(printf '1\t1\t2\t10\t75\t%s\tTop\n2\t2\t4\t8\t42\t%s\tTop > Child A\n3\t2\t9\t10\t18\t%s\tTop > Child B' "$h1" "$h2" "$h3")"
assert_eq "map --file: id level start end bytes own-body sha256 heading_path, fence skipped" "$want" "$(dc "$S" map --file "$PAGE")"
KEY="$(DOCS_CACHE_NOW=$T1 dc "$S" put "$URL" markdown "$PAGE" 'text/markdown; charset=utf-8')"
assert_eq "put: prints the key" "$(dc "$S" key "$URL" markdown)" "$KEY"
assert_eq "map <key>: the stored map is the file map" "$want" "$(dc "$S" map "$KEY")"

renamed="$TEST_TMPDIR/renamed.md"
sed 's/^## Child A$/## Child Renamed/' "$PAGE" >"$renamed"
assert_eq "map: rename keeps the section hash" "$h2" "$(dc "$S" map --file "$renamed" | awk -F'\t' '$1 == 2 { print $6 }')"
assert_eq "map: rename changes the heading path" "Top > Child Renamed" "$(dc "$S" map --file "$renamed" | awk -F'\t' '$1 == 2 { print $7 }')"
child="$TEST_TMPDIR/child.md"
sed 's/^b body$/b body changed/' "$PAGE" >"$child"
assert_eq "map: child change does not change the parent hash" "$h1" "$(dc "$S" map --file "$child" | awk -F'\t' '$1 == 1 { print $6 }')"
assert_eq "map: the child's own hash does change" "$(printf 'b body changed\n' | sha)" "$(dc "$S" map --file "$child" | awk -F'\t' '$1 == 3 { print $6 }')"
parent="$TEST_TMPDIR/parent.md"
sed 's/^top body$/top body changed/' "$PAGE" >"$parent"
assert_eq "map: an own-body change changes the hash" "$(printf 'top body changed\n' | sha)" "$(dc "$S" map --file "$parent" | awk -F'\t' '$1 == 1 { print $6 }')"
nonl="$TEST_TMPDIR/nonl.md"
printf '# Only\nlast line without a newline' >"$nonl"
assert_eq "map: bytes count a last line with no newline exactly" "$(wc -c <"$nonl" | tr -d ' ')" "$(dc "$S" map --file "$nonl" | cut -f5)"
crlf="$TEST_TMPDIR/crlf.md"
printf '# Title  ##\r\nbody\r\n' >"$crlf"
assert_eq "map: a CRLF heading path drops the carriage return and closing hashes" "Title" "$(dc "$S" map --file "$crlf" | cut -f7)"
assert_eq "map: no heading, no rows" "" "$(printf 'just text\n' >"$TEST_TMPDIR/flat.md" && dc "$S" map --file "$TEST_TMPDIR/flat.md")"

# --- slice ----------------------------------------------------------------------
assert_eq "slice: a section is its heading, body and child sections" "$(sed -n '2,10p' "$PAGE")" "$(dc "$S" slice "$KEY" 1)"
assert_eq "slice: a leaf section" "$(sed -n '4,8p' "$PAGE")" "$(dc "$S" slice "$KEY" 2)"
assert_eq "slice: ids print in the order asked" "$(
  sed -n '9,10p' "$PAGE"
  sed -n '4,8p' "$PAGE"
)" "$(dc "$S" slice "$KEY" 3 2)"
assert_eq "slice --file: same as by key" "$(dc "$S" slice "$KEY" 2)" "$(dc "$S" slice --file "$PAGE" 2)"
rc=0
out="$(dc "$S" slice "$KEY" 2 9 2>/dev/null)" || rc=$?
assert_eq "slice: an unknown id exits 1" 1 "$rc"
assert_eq "slice: an unknown id prints nothing" "" "$out"
rc=0
dc "$S" slice "$KEY" 2>/dev/null || rc=$?
assert_eq "slice: no id is a usage error" 2 "$rc"

# --- put and info ----------------------------------------------------------------
info() { DOCS_CACHE_NOW="$2" dc "$1" info "$3"; }
rec="$(info "$S" $T2 "$KEY")"
assert_eq "info: the record" \
  "$URL markdown $(sha <"$PAGE") $(wc -c <"$PAGE" | tr -d ' ') text/markdown; charset=utf-8 $T1_ISO $T1_ISO 100" \
  "$(jq -r '"\(.url) \(.format) \(.sha256) \(.bytes) \(.content_type) \(.retrieved) \(.validated) \(.age_seconds)"' <<<"$rec")"
assert_eq "info: the stored body is the bytes put" "" "$(cmp "$PAGE" "$(jq -r .entry <<<"$rec")/body" 2>&1)"
meta_before="$(sha <"$(jq -r .entry <<<"$rec")/meta.json")"
dc "$S" map "$KEY" >/dev/null
dc "$S" slice "$KEY" 1 >/dev/null
info "$S" $T2 "$KEY" >/dev/null
assert_eq "read: meta.json is never rewritten by a read" "$meta_before" "$(sha <"$(jq -r .entry <<<"$rec")/meta.json")"
assert_eq "read: last access is recorded beside the pointer" "$T2" "$(cat "$S/keys/$KEY.access" 2>/dev/null)"
rc=0
out="$(dc "$S" info "$(dc "$S" key https://docs.test/docs/en/other.md markdown)")" || rc=$?
assert_eq "info: a key with no entry is a miss, exit 1" "1 " "$rc $out"

# --- edge: TTL expiry with unchanged sha ------------------------------------------
S="$TEST_TMPDIR/s-ttl"
KEY="$(DOCS_CACHE_NOW=$T1 dc "$S" put "$URL" markdown "$PAGE")"
first_entry="$(jq -r .entry <<<"$(info "$S" $T1 "$KEY")")"
DOCS_CACHE_NOW=$T3 dc "$S" put "$URL" markdown "$PAGE" >/dev/null
rec="$(info "$S" $T3 "$KEY")"
assert_eq "edge: TTL expiry with unchanged sha refreshes validated only, retrieved unchanged" \
  "$T1_ISO $T3_ISO 0" "$(jq -r '"\(.retrieved) \(.validated) \(.age_seconds)"' <<<"$rec")"
assert_eq "edge: TTL expiry with unchanged sha keeps the same entry directory" "$first_entry" "$(jq -r .entry <<<"$rec")"
assert_eq "edge: TTL expiry with unchanged sha adds no entry" 1 "$(entries_for "$S" "$KEY")"
DOCS_CACHE_NOW=$T3 dc "$S" put "$URL" markdown "$parent" >/dev/null
rec="$(info "$S" $T3 "$KEY")"
assert_eq "put: changed bytes are a new entry with a new retrieved" "$(sha <"$parent") $T3_ISO $T3_ISO" "$(jq -r '"\(.sha256) \(.retrieved) \(.validated)"' <<<"$rec")"
assert_eq "put: the earlier entry stays, unmodified" "2 " "$(entries_for "$S" "$KEY") $(cmp "$PAGE" "$first_entry/body" 2>&1)"
assert_eq "slice <key>-<sha256>: reads that entry, not the current one" "$(sed -n '2,3p' "$PAGE")" \
  "$(dc "$S" slice "$KEY-$(sha <"$PAGE")" 1 | head -2)"
assert_eq "slice <key>: reads the current entry" "top body changed" "$(dc "$S" slice "$KEY" 1 | sed -n 2p)"
bad="$(find "$S" -mindepth 2 -maxdepth 2 ! -name store_version | sed 's|.*/||' | grep -vcE '^[0-9a-f]{64}(-[0-9a-f]{64}|\.access)?$')"
assert_eq "store: every entry and pointer name is hex digests only" 0 "$bad"

# --- edge: two real parallel writer processes --------------------------------------
other="$TEST_TMPDIR/other.md"
printf '%s\n' '# Other' 'other body' >"$other"
for round in 1 2 3; do
  S="$TEST_TMPDIR/s-par$round"
  bash "$SCRIPT" --cache-dir "$S" put "$URL" markdown "$PAGE" >/dev/null 2>"$S.err1" &
  p1=$!
  bash "$SCRIPT" --cache-dir "$S" put "$URL" markdown "$PAGE" >/dev/null 2>"$S.err2" &
  p2=$!
  rc1=0 rc2=0
  wait "$p1" || rc1=$?
  wait "$p2" || rc2=$?
  KEY="$(dc "$S" key "$URL" markdown)"
  assert_eq "edge: two real parallel writer processes leave one complete entry (round $round): both exit 0" "0 0" "$rc1 $rc2"
  assert_eq "edge: two real parallel writer processes leave one complete entry (round $round): one entry" 1 "$(entries_for "$S" "$KEY")"
  assert_eq "edge: two real parallel writer processes leave one complete entry (round $round): no temp left" 0 "$(leftovers "$S")"
  assert_eq "edge: two real parallel writer processes leave one complete entry (round $round): it reads back whole" \
    "$(sed -n '2,10p' "$PAGE")" "$(dc "$S" slice "$KEY" 1)"

  S="$TEST_TMPDIR/s-pard$round"
  bash "$SCRIPT" --cache-dir "$S" put "$URL" markdown "$PAGE" >/dev/null 2>&1 &
  p1=$!
  bash "$SCRIPT" --cache-dir "$S" put "$URL" markdown "$other" >/dev/null 2>&1 &
  p2=$!
  wait "$p1"
  wait "$p2"
  rec="$(dc "$S" info "$KEY")"
  cur="$(jq -r .sha256 <<<"$rec")"
  ok=0
  [[ "$cur" == "$(sha <"$PAGE")" || "$cur" == "$(sha <"$other")" ]] && ok=1
  assert_eq "edge: two real parallel writers with different bytes (round $round): the pointer names one writer's entry" 1 "$ok"
  assert_eq "edge: two real parallel writers with different bytes (round $round): that entry is complete" \
    "$cur" "$(sha <"$(jq -r .entry <<<"$rec")/body")"
  assert_eq "edge: two real parallel writers with different bytes (round $round): no temp left" 0 "$(leftovers "$S")"
done

# --- edge: torn-entry read ---------------------------------------------------------
S="$TEST_TMPDIR/s-torn"
KEY="$(dc "$S" key "$URL" markdown)"
mkdir -p "$S/entries/.tmp-123-456"
cp "$PAGE" "$S/entries/.tmp-123-456/body"
printf '1\n' >"$S/store_version"
mkdir -p "$S/keys"
rc=0
out="$(dc "$S" info "$KEY")" || rc=$?
assert_eq "edge: torn-entry read: a half-written temp directory is a miss" "1 " "$rc $out"
printf '%s-%s\t%s\t%s\n' "$KEY" "$(sha <"$PAGE")" "$T1" "$T1_ISO" >"$S/keys/$KEY"
rc=0
out="$(dc "$S" info "$KEY")" || rc=$?
assert_eq "edge: torn-entry read: a dangling pointer is a miss" "1 " "$rc $out"
rc=0
out="$(dc "$S" slice "$KEY" 1 2>/dev/null)" || rc=$?
assert_eq "edge: torn-entry read: a dangling pointer slices nothing" "1 " "$rc $out"
mkdir -p "$S/entries/$KEY-$(sha <"$PAGE")"
cp "$PAGE" "$S/entries/$KEY-$(sha <"$PAGE")/body"
rc=0
out="$(dc "$S" info "$KEY")" || rc=$?
assert_eq "edge: torn-entry read: an entry with no meta.json is a miss" "1 " "$rc $out"
: >"$S/keys/$KEY"
rc=0
dc "$S" info "$KEY" >/dev/null || rc=$?
assert_eq "edge: torn-entry read: an empty pointer is a miss" 1 "$rc"

# --- edge: old reader on new store -------------------------------------------------
S="$TEST_TMPDIR/s-new"
KEY="$(DOCS_CACHE_NOW=$T1 dc "$S" put "$URL" markdown "$PAGE")"
printf '2\n' >"$S/store_version"
rc=0
out="$(dc "$S" info "$KEY" 2>&1)" || rc=$?
assert_eq "edge: old reader on new store: an unknown store_version is a miss, never a parse" "1 " "$rc $out"
rc=0
out="$(dc "$S" map "$KEY" 2>/dev/null)" || rc=$?
assert_eq "edge: old reader on new store: map is a miss too" "1 " "$rc $out"
rc=0
DOCS_CACHE_NOW=$T2 dc "$S" put "$URL" markdown "$other" >/dev/null 2>&1 || rc=$?
assert_eq "edge: old reader on new store: a write is refused" 2 "$rc"
assert_eq "edge: old reader on new store: the refused write adds no entry" 1 "$(entries_for "$S" "$KEY")"
printf '1\n' >"$S/store_version"
entry="$(jq -r .entry <<<"$(dc "$S" info "$KEY")")"
jq '.store_version = 2 | .shape = "unknown"' "$entry/meta.json" >"$TEST_TMPDIR/meta2" && cp "$TEST_TMPDIR/meta2" "$entry/meta.json"
rc=0
out="$(dc "$S" info "$KEY" 2>&1)" || rc=$?
assert_eq "edge: old reader on new store: an entry with an unknown store_version is a miss" "1 " "$rc $out"

# --- cache directory resolution ------------------------------------------------------
H="$TEST_TMPDIR/home"
mkdir -p "$H"
env -u DOCS_CACHE_DIR -u XDG_CACHE_HOME HOME="$H" bash "$SCRIPT" put "$URL" markdown "$PAGE" >/dev/null
assert_eq "dir: default is \$HOME/.cache/claude-docs-cache" 1 "$([[ -f "$H/.cache/claude-docs-cache/store_version" ]] && echo 1 || echo 0)"
env -u DOCS_CACHE_DIR XDG_CACHE_HOME="$TEST_TMPDIR/xdg" HOME="$H" bash "$SCRIPT" put "$URL" markdown "$PAGE" >/dev/null
assert_eq "dir: XDG_CACHE_HOME moves the default" 1 "$([[ -f "$TEST_TMPDIR/xdg/claude-docs-cache/store_version" ]] && echo 1 || echo 0)"
DOCS_CACHE_DIR="$TEST_TMPDIR/env" HOME="$H" bash "$SCRIPT" put "$URL" markdown "$PAGE" >/dev/null
assert_eq "dir: DOCS_CACHE_DIR wins over the default" 1 "$([[ -f "$TEST_TMPDIR/env/store_version" ]] && echo 1 || echo 0)"
DOCS_CACHE_DIR="$TEST_TMPDIR/env-lost" bash "$SCRIPT" --cache-dir "$TEST_TMPDIR/flag" put "$URL" markdown "$PAGE" >/dev/null
assert_eq "dir: --cache-dir wins over DOCS_CACHE_DIR" "1 0" \
  "$([[ -f "$TEST_TMPDIR/flag/store_version" ]] && echo 1 || echo 0) $([[ -e "$TEST_TMPDIR/env-lost" ]] && echo 1 || echo 0)"

# --- title, quarantine and validators ------------------------------------------------
# lib_run <store> <now> <shell code>: run code with this file's functions sourced.
lib_run() {
  DOCS_CACHE_NOW="$2" bash -c '. "$1"; dc_set_dir "$2"; eval "$3"' _ "$SCRIPT" "$1" "$3"
}
S="$TEST_TMPDIR/s-title"
KEY="$(DOCS_CACHE_NOW=$T1 dc "$S" put "$URL" markdown "$PAGE")"
assert_eq "title: the body's first heading is recorded" Top "$(info "$S" $T1 "$KEY" | jq -r .title)"
printf '%s\n' 'no heading here' >"$TEST_TMPDIR/plain.md"
lib_run "$S" $T1 'dc_put https://docs.test/plain markdown "'"$TEST_TMPDIR/plain.md"'" text/markdown "From Title"' >/dev/null
assert_eq "title: a body with no heading records the title the writer passed" "From Title" \
  "$(info "$S" $T1 "$(dc "$S" key https://docs.test/plain markdown)" | jq -r .title)"
assert_eq "title: an entry with a heading ignores the passed title" Top \
  "$(lib_run "$S" $T1 'dc_put "'"$URL"'" markdown "'"$PAGE"'" "" Other >/dev/null; printf %s "$DC_TITLE"')"

S="$TEST_TMPDIR/s-quarantine"
printf '%s\n' '# Alpha' 'body one' >"$TEST_TMPDIR/alpha.md"
printf '%s\n' '# Alpha' 'body two' >"$TEST_TMPDIR/alpha2.md"
printf '%s\n' '# Beta' 'body two' >"$TEST_TMPDIR/beta.md"
KEY="$(DOCS_CACHE_NOW=$T1 dc "$S" put "$URL" markdown "$TEST_TMPDIR/alpha.md")"
DOCS_CACHE_NOW=$T2 dc "$S" put "$URL" markdown "$TEST_TMPDIR/alpha2.md" >/dev/null
assert_eq "quarantine: new bytes under the same title do not quarantine" null "$(info "$S" $T2 "$KEY" | jq -c .quarantine)"
DOCS_CACHE_NOW=$T3 dc "$S" put "$URL" markdown "$TEST_TMPDIR/beta.md" >/dev/null
assert_eq "quarantine: a retitled page quarantines the key, naming both titles and entries" \
  "Alpha Beta $KEY-$(sha <"$TEST_TMPDIR/alpha2.md") $KEY-$(sha <"$TEST_TMPDIR/beta.md") $T3_ISO" \
  "$(info "$S" $T3 "$KEY" | jq -r '.quarantine | "\(.from_title) \(.to_title) \(.from_entry) \(.to_entry) \(.at)"')"
assert_eq "quarantine: the sourced API reports it" 1 "$(lib_run "$S" $T3 'dc_lookup '"$KEY"'; printf %s "$DC_QUARANTINED"')"
DOCS_CACHE_NOW=$T3 dc "$S" put "$URL" markdown "$TEST_TMPDIR/alpha.md" >/dev/null
assert_eq "quarantine: retitling back keeps the key quarantined, recording the latest change" "Beta Alpha" \
  "$(info "$S" $T3 "$KEY" | jq -r '.quarantine | "\(.from_title) \(.to_title)"')"

S="$TEST_TMPDIR/s-formats"
k_md="$(DOCS_CACHE_NOW=$T1 dc "$S" put "$URL" markdown "$TEST_TMPDIR/alpha.md")"
k_html="$(DOCS_CACHE_NOW=$T1 dc "$S" put "$URL" html-converted "$TEST_TMPDIR/beta.md")"
assert_eq "edge: one URL in two formats is two keys, each with its own entry" "1 1 1" \
  "$([[ "$k_md" != "$k_html" ]] && echo 1 || echo 0) $(entries_for "$S" "$k_md") $(entries_for "$S" "$k_html")"
assert_eq "edge: the second format neither replaces nor quarantines the first" "Alpha null Beta null" \
  "$(info "$S" $T1 "$k_md" | jq -r '"\(.title) \(.quarantine)"') $(info "$S" $T1 "$k_html" | jq -r '"\(.title) \(.quarantine)"')"

S="$TEST_TMPDIR/s-validators"
KEY="$(lib_run "$S" $T1 'dc_put "'"$URL"'" markdown "'"$PAGE"'" text/markdown "" "$(printf "%s\x1f%s\x1f%s\x1f%s" text/markdown "'"$URL"'" "\"v1\"" "Sat, 08 Sep 2001 00:00:00 GMT")" >/dev/null; printf %s "$DC_KEY"')"
assert_eq "validators: the pointer holds them and info reports them" '"v1" Sat, 08 Sep 2001 00:00:00 GMT' \
  "$(info "$S" $T1 "$KEY" | jq -r '"\(.etag) \(.last_modified)"')"
assert_eq "validators: the sourced API reads them back" "text/markdown $URL" \
  "$(lib_run "$S" $T1 'dc_lookup '"$KEY"'; printf "%s %s" "$DC_ACCEPT" "$DC_REQ_URL"')"
entry="$(info "$S" $T1 "$KEY" | jq -r .entry)"
lib_run "$S" $T3 'dc_confirm '"$KEY-$(sha <"$PAGE")" >/dev/null
rec="$(info "$S" $T3 "$KEY")"
assert_eq "edge: a confirm (a 304) moves validated and leaves retrieved and the entry" "$T1_ISO $T3_ISO 0 $entry 1" \
  "$(jq -r '"\(.retrieved) \(.validated) \(.age_seconds) \(.entry)"' <<<"$rec") $(entries_for "$S" "$KEY")"
assert_eq "validators: a confirm with none passed drops them" "null null" "$(jq -r '"\(.etag) \(.last_modified)"' <<<"$rec")"
assert_eq "validators: a value holding a separator is not stored" "" \
  "$(lib_run "$S" $T1 'dc_validators a "b	c" "\"v\"" ""')"
assert_eq "validators: no ETag and no Last-Modified is no record" "" \
  "$(lib_run "$S" $T1 'dc_validators text/markdown '"$URL"' "" ""')"
rc=0
lib_run "$S" $T1 'dc_confirm '"$KEY"'-'"$(printf '%064d' 0)" >/dev/null 2>&1 || rc=$?
assert_eq "validators: confirming an entry that is not stored fails" 1 "$rc"

# --- usage --------------------------------------------------------------------------
rc=0
bash "$SCRIPT" --cache-dir "$TEST_TMPDIR/u" nope >/dev/null 2>&1 || rc=$?
assert_eq "usage: an unknown command exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --cache-dir "$TEST_TMPDIR/u" put "$URL" markdown "$TEST_TMPDIR/absent" >/dev/null 2>&1 || rc=$?
assert_eq "usage: put of a missing file exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --cache-dir "$TEST_TMPDIR/u" info not-a-key >/dev/null 2>&1 || rc=$?
assert_eq "usage: a malformed key is a miss" 1 "$rc"

echo
if [[ $FAILED -eq 0 ]]; then
  printf 'All %d assertions passed.\n' "$CASE_NUM"
else
  printf '%d of %d assertions failed.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
