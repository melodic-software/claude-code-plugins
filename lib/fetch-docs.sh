#!/usr/bin/env bash
# Upstream docs fetcher, shared by the plugins that read vendor docs pages.
#
# Skills that rest on official docs pages grep them for cited spans and read
# them for the criteria their checks apply. This script is the one place those
# pages are fetched. It reads each page verbatim to a file and writes a
# manifest of what it did. It never reads, searches or summarizes a page: it
# guarantees complete bytes on disk plus the manifest, and the caller reads.
#
# A publisher is a profile (--profile, default anthropic). An indexed profile
# (anthropic, platform) has an index URL (llms.txt), the path prefix pages live
# under on the index's origin, the raw channel (the suffix that turns a page
# slug into its raw-markdown file name) and the content types the index and the
# channel answer with. A page whose channel does not answer as declared is
# unread with a reason, never read from another channel.
#
# Identity in an indexed profile comes from the index. A slug the index does not
# list is not fetched: a retired slug can answer 200 with another page's body, so
# a body that arrived is no proof the page exists. A page is read only when the
# whole body arrived over HTTPS from the profile's origin with the profile's
# content type and a 2xx status. Anything else is unread and leaves no file, so a
# partial or foreign body is never counted as read. A body over max_page_bytes
# (--max-page-bytes, else docs-cache.sh's configuration) is unread too-large:
# nothing of it is converted or stored.
#
# The generic profile takes any https URL and needs no index. It prefers
# markdown, in this order: the URL with Accept: text/markdown; the URL with a
# .md suffix; a same-origin link in the origin's llms.txt whose path, without a
# .md or .txt suffix or a trailing /index, is the page's path. When none
# answers with markdown, the page's HTML is converted by html2md.py beside this
# script, run by the first of python3 and python whose probe prints 3, with
# PYTHONUTF8=1. Identity: the page's own request must end on the requested
# origin and path, or the page is unread. With --cache the page's title (its
# first heading, else the HTML <title>) is stored, and an entry whose title
# differs from the one it replaces quarantines the cache key (docs-cache.sh).
#
# The page file is the raw bytes as fetched, or the converter's output. The
# manifest hash is taken over those bytes, so a caller that strips control
# characters from a working copy does not change it.
#
# With --cache the index and every page go through docs-cache.sh beside this
# script, keyed by URL and format (markdown or html-converted), so one URL that
# negotiates to either is two keys. An entry validated within --max-age seconds
# is copied to the page file with no request. Any other read is fetched; when
# the cached entry was stored with an ETag or Last-Modified, the request carries
# If-None-Match or If-Modified-Since, and a 304 serves the entry and moves only
# its validated time. A Last-Modified equal to the response's Date is treated as
# absent. --max-age 0 always asks the server, and a failed fetch is unread. With
# --max-age above 0, a fetch that failed (a transport error or a 5xx) serves the
# cached bytes flagged stale: true, its reason and age_seconds since validated.
# A 404, a 410, a landing off the origin or path, or a slug the index no longer
# lists is unread and quarantines the URL's cache keys, so their notes are never
# served. The server's Date is recorded as server_date, never used for age.
#
# Manifest (JSON, written to --manifest):
#   claude_version  installed `claude --version` number, or "" when unreadable
#   index           record for the index itself (null for the generic profile)
#   pages[]         one record per requested page, in request order
#   cache_disabled  null, or the layer (env or file) whose cache_enabled false
#                   made this --cache run read and write no cache
# Each record: slug, url, mode, source (fetch|fixture|cache), retrieved (UTC
# ISO, when these bytes were first fetched), validated (UTC ISO, when they were
# last confirmed current), age_seconds (since validated), cache_key (the
# docs-cache.sh key, null when nothing was stored), sha256 (raw bytes), status
# (HTTP code; 304 when the server confirmed a cached entry), content_type,
# bytes, lines, file (path on disk), format (markdown|html-converted), title
# (from the cache), quarantined (the cache key's quarantine flag), stale (true
# when cached bytes stood in for a failed fetch), server_date (the Date header of
# the response that last validated the bytes), cache_error (why --cache stored
# nothing for a read page, else null), state, reason. state is read or unread; unparsed is set by a caller whose parse of a
# read page failed. mode (full|search) is the caller's declaration of how it
# will use the page; the fetcher only records it. Fields with no value are null
# (a page never requested, or served from the cache, has no status; a run
# without --cache has no title or quarantined).
#
# Exit codes:
#   0  the manifest was written (pages may be unread; read the manifest)
#   2  fatal (bad arguments, unknown profile, jq missing, manifest not writable)
#
# Env overrides (the test seam):
#   FETCH_DOCS_FIXTURE_DIR  directory of llms.txt and <slug>.md
#       files. Set, even to an empty or missing directory, means no network: a
#       file the directory lacks is unread (fixture-missing), never fetched.
#   FETCH_DOCS_INDEX_URL    index URL when --index-url is absent (default: the profile's)
#   FETCH_DOCS_CLAUDE_BIN   claude binary for claude_version
#   FETCH_DOCS_HTML2MD      HTML converter (default: html2md.py beside this script)
#   DOCS_CACHE_DIR          cache directory when --cache-dir is absent; in
#       fixture mode --cache needs one of the two, so fixture bytes never reach
#       the default or the machine file's cache. The other DOCS_CACHE_*
#       settings and the machine file are docs-cache.sh's (its header).
#   DOCS_CACHE_NOW          epoch seconds docs-cache.sh uses as the current time

set -uo pipefail

PROFILES="anthropic, platform, generic"

usage() {
  cat <<EOF
fetch-docs.sh: fetch a publisher's docs pages verbatim and write a manifest.

Usage:
  fetch-docs.sh --out <dir> [--manifest <file>] [--profile <name>] [--index-url <url>] [--follow <depth>]
                [--max-page-bytes <n>] [--cache [--max-age <seconds>] [--cache-dir <dir>]]
                (--discover | [--mode full|search] <slug|url>...)

  --out <dir>        directory for the page files (<slug>.md) and the index (llms.txt)
  --manifest <file>  manifest path (default: <dir>/manifest.json)
  --profile <name>   publisher profile (default: anthropic; known: $PROFILES)
  --index-url <url>  docs index (default: the profile's; its origin is the allowed origin)
  --discover         request every page the index links under the profile's path prefix
  --mode <m>         how the caller will use the pages that follow: full (default) or search
  --follow <depth>   reserved for link-following; accepted, default 0, acted on by no caller
  --max-page-bytes <n>  a body over <n> bytes is unread too-large (default: the docs cache's
                     max_page_bytes, 10485760 unless configured)
  --cache            read through the docs cache and store what is fetched
  --max-age <s>      serve a cached entry validated at most <s> seconds ago (default: the
                     docs cache's ttl_seconds, 86400 unless configured); 0 always asks the server
  --cache-dir <dir>  cache directory (default: the docs cache's cache_dir)
                     These defaults, and cache_enabled, resolve from DOCS_CACHE_* and the machine
                     file; docs-cache.sh config prints them with their layer.
  <slug|url>         a page slug (settings-reference) or an origin URL the index lists;
                     for --profile generic, any https URL (its slug is host/path)

Exit: 0 manifest written; 2 fatal (including an unknown profile).
EOF
}

die() {
  echo "ERROR: $1" >&2
  exit 2
}

PROFILE=anthropic
INDEX_URL=""
OUT=""
MANIFEST=""
DISCOVER=0
MODE=full
CACHE=0
MAX_AGE=""
MAX_PAGE=""
CACHE_DIR=""
TARGETS=()
TARGET_MODES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --out | --manifest | --profile | --index-url | --follow | --mode | --max-age | --max-page-bytes | --cache-dir)
    [[ $# -ge 2 ]] || die "$1 needs a value"
    case "$1" in
    --out) OUT="$2" ;;
    --manifest) MANIFEST="$2" ;;
    --profile) PROFILE="$2" ;;
    --index-url) INDEX_URL="$2" ;;
    --follow) [[ "$2" =~ ^[0-9]+$ ]] || die "--follow needs a non-negative integer" ;; # depth is validated and dropped: no caller follows links
    --mode)
      [[ "$2" == full || "$2" == search ]] || die "--mode is full or search"
      MODE="$2"
      ;;
    --max-age)
      [[ "$2" =~ ^(0|[1-9][0-9]{0,17})$ ]] || die "--max-age needs a non-negative integer"
      MAX_AGE="$2"
      ;;
    --max-page-bytes)
      [[ "$2" =~ ^[1-9][0-9]{0,17}$ ]] || die "--max-page-bytes needs a positive integer"
      MAX_PAGE="$2"
      ;;
    --cache-dir)
      [[ -n "$2" ]] || die "--cache-dir needs a value"
      CACHE_DIR="$2"
      ;;
    *) die "unreachable" ;;
    esac
    shift 2
    ;;
  --discover)
    DISCOVER=1
    shift
    ;;
  --cache)
    CACHE=1
    shift
    ;;
  -*) die "unknown argument: $1" ;;
  *)
    TARGETS+=("$1")
    TARGET_MODES+=("$MODE")
    shift
    ;;
  esac
done

MD_CTYPE='^text/(markdown|x-markdown)'
MD_OR_TEXT_CTYPE='^text/(markdown|x-markdown|plain)'
HTML_CTYPE='^(text/html|application/xhtml\+xml)'

# profile <name>: set the publisher's record. P_KIND is index or url. For an
# index profile P_DOCS_PATH is the path prefix a page URL has under the index's
# origin, P_SUFFIX the raw channel's file suffix, P_INDEX_CTYPE and
# P_PAGE_CTYPE the content-type patterns the index and the raw channel answer
# with, P_FORMAT the format the cache keys their bytes by.
profile() {
  P_KIND=index P_DOCS_PATH="/docs/" P_SUFFIX=".md" P_FORMAT=markdown
  P_INDEX_CTYPE='^text/(plain|markdown)' P_PAGE_CTYPE="$MD_CTYPE"
  case "$1" in
  anthropic) P_INDEX_URL="https://code.claude.com/docs/llms.txt" ;;
  platform) P_INDEX_URL="https://platform.claude.com/llms.txt" ;;
  generic) P_KIND=url P_INDEX_URL="" ;;
  *) return 1 ;;
  esac
}
profile "$PROFILE" || die "unknown profile: $PROFILE (known: $PROFILES)"

[[ -n "$OUT" ]] || die "--out is required"
[[ $DISCOVER -eq 1 || ${#TARGETS[@]} -gt 0 ]] || die "name a page or pass --discover"
command -v jq >/dev/null 2>&1 || die "jq required"
ORIGIN=""
if [[ "$P_KIND" == index ]]; then
  INDEX_URL="${INDEX_URL:-${FETCH_DOCS_INDEX_URL:-$P_INDEX_URL}}"
  [[ "$INDEX_URL" =~ ^(https://[^/]+) ]] && ORIGIN="${BASH_REMATCH[1]}"
  [[ -n "$ORIGIN" ]] || die "--index-url must be an https URL"
else
  [[ $DISCOVER -eq 0 ]] || die "--discover needs an indexed profile"
  [[ -z "$INDEX_URL" ]] || die "--index-url needs an indexed profile"
fi

FIXTURE_SET=0
[[ -n "${FETCH_DOCS_FIXTURE_DIR+x}" ]] && FIXTURE_SET=1
FIXTURE="${FETCH_DOCS_FIXTURE_DIR:-}"
CURL_MISSING=0
if [[ $FIXTURE_SET -eq 0 ]] && ! command -v curl >/dev/null 2>&1; then CURL_MISSING=1; fi
CACHE_DISABLED=""
# The docs cache's configuration holds max_page_bytes, so it resolves with or without --cache.
DOCS_CACHE="$(dirname "${BASH_SOURCE[0]}")/docs-cache.sh"
[[ -f "$DOCS_CACHE" ]] || die "docs-cache.sh not found beside fetch-docs.sh"
# shellcheck source=docs-cache.sh
. "$DOCS_CACHE"
dc_config cache_dir="$CACHE_DIR" ttl_seconds="$MAX_AGE" max_page_bytes="$MAX_PAGE"
dc_config_warn
MAX_PAGE="$DC_CFG_max_page_bytes"
if [[ $CACHE -eq 1 ]]; then
  if [[ "$DC_CFG_cache_enabled" == false ]]; then
    CACHE=0 CACHE_DISABLED="$DC_LAYER_cache_enabled"
  else
    # Fixture bytes reach only a cache this invocation named, never the machine file's.
    [[ $FIXTURE_SET -eq 0 || "$DC_LAYER_cache_dir" == flag || "$DC_LAYER_cache_dir" == env ]] ||
      die "--cache with FETCH_DOCS_FIXTURE_DIR needs --cache-dir or DOCS_CACHE_DIR"
    MAX_AGE="$DC_CFG_ttl_seconds"
  fi
fi
MAX_AGE="${MAX_AGE:-0}"
CONVERTER="${FETCH_DOCS_HTML2MD:-$(dirname "${BASH_SOURCE[0]}")/html2md.py}"

mkdir -p "$OUT" || die "cannot create $OUT"
MANIFEST="${MANIFEST:-$OUT/manifest.json}"
mkdir -p "$(dirname "$MANIFEST")" || die "cannot create the manifest directory"
WORK="$(mktemp -d)" || die "could not create a temp directory"
INDEX_REC="$WORK/index.json"
PAGE_RECS="$WORK/pages.jsonl"
: >"$PAGE_RECS"
trap 'rm -rf "$WORK"' EXIT

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum <"$1" | cut -d' ' -f1; else shasum -a 256 <"$1" | cut -d' ' -f1; fi
}

# with_timeout <seconds> <command...>: run under timeout when it exists.
with_timeout() {
  local s="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi
}

reset_g() {
  G_SOURCE="" G_STATE=unread G_REASON="" G_STATUS="" G_CTYPE="" G_AT="" G_VALIDATED="" G_AGE="" G_KEY=""
  G_FORMAT="" G_TITLE="" G_QUAR="" G_VALIDATORS="" G_TITLE_HINT="" G_STALE="" G_DATE="" G_CACHE_ERR=""
}

# http_get <url> <dest> <accept> <if-none-match> <if-modified-since>: one GET
# with the body at <dest>. Sets H_RC H_STATUS H_EFF H_CTYPE and the final
# response's H_DATE, H_ETAG and H_LM (empty when absent, or Last-Modified equal
# to Date). A body over max_page_bytes is deleted and H_RC is 63, curl's own
# code for it: curl stops at a declared Content-Length over the limit, and the
# size check catches a body sent without one, which an older curl lets through.
http_get() {
  local hdr="$2.hdr" meta args=() line low date=""
  [[ -z "$3" ]] || args+=(-H "Accept: $3")
  [[ -z "$4" ]] || args+=(-H "If-None-Match: $4")
  [[ -z "$5" ]] || args+=(-H "If-Modified-Since: $5")
  rm -f "$2" "$hdr"
  # No -f: an HTTP error still prints its status and content type through -w.
  meta="$(curl -sSL --proto =https --proto-redir =https --max-redirs 5 --connect-timeout 15 --max-time 120 \
    --max-filesize "$MAX_PAGE" ${args[@]+"${args[@]}"} -D "$hdr" -w '%{http_code} %{url_effective} %{content_type}' \
    -o "$2" "$1" 2>/dev/null)"
  H_RC=$?
  if [[ -f "$2" && $(wc -c <"$2") -gt $MAX_PAGE ]]; then H_RC=63; fi
  [[ $H_RC -ne 63 ]] || rm -f "$2"
  H_STATUS="" H_EFF="" H_CTYPE="" H_ETAG="" H_LM=""
  read -r H_STATUS H_EFF H_CTYPE <<<"$meta"
  [[ "$H_STATUS" =~ ^[0-9]+$ ]] || H_STATUS=""
  if [[ -f "$hdr" ]]; then
    # A redirect writes one header block per response; the last one counts.
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      low="${line,,}"
      case "$low" in
      http/*) H_ETAG="" H_LM="" date="" ;;
      etag:*) H_ETAG="$(trim "${line#*:}")" ;;
      last-modified:*) H_LM="$(trim "${line#*:}")" ;;
      date:*) date="$(trim "${line#*:}")" ;;
      *) ;;
      esac
    done <"$hdr"
    rm -f "$hdr"
  fi
  [[ "$H_LM" != "$date" ]] || H_LM=""
  H_DATE="$date"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

# cache_candidate <url> <format>...: the freshest stored entry for the URL in
# any of the formats. Sets C_REF (<key>-<sha256>, empty when none), the
# validated time its pointer held when it was chosen (C_EPOCH C_ISO) and the
# server Date (C_DATE), C_CTYPE C_FORMAT and its validators C_ACCEPT C_REQ_URL
# C_ETAG C_LM.
cache_candidate() {
  local url="$1" f
  C_REF="" C_EPOCH="" C_ISO="" C_DATE="" C_CTYPE="" C_FORMAT="" C_ACCEPT="" C_REQ_URL="" C_ETAG="" C_LM=""
  [[ $CACHE -eq 1 ]] || return 0
  shift
  for f in "$@"; do
    dc_lookup "$(dc_key "$url" "$f")" || continue
    [[ -n "$DC_VALIDATED_EPOCH" ]] || continue
    [[ -z "$C_REF" || $DC_VALIDATED_EPOCH -gt $C_EPOCH ]] || continue
    C_REF="$DC_REF" C_EPOCH="$DC_VALIDATED_EPOCH" C_ISO="$DC_VALIDATED" C_DATE="$DC_SERVER_DATE" C_CTYPE="$DC_CTYPE" C_FORMAT="$f"
    C_ACCEPT="$DC_ACCEPT" C_REQ_URL="$DC_REQ_URL" C_ETAG="$DC_ETAG" C_LM="$DC_LM"
  done
}

# serve_cached <dest> <status>: copy the candidate's body to <dest> and set the
# G_ fields from its immutable entry and the pointer snapshot taken when it was
# chosen, so a pointer switched since then cannot blank its validated time.
serve_cached() {
  if ! { [[ -n "$C_EPOCH" ]] && dc_lookup "$C_REF" && cp "$DC_ENTRY/body" "$1"; }; then
    rm -f "$1"
    return 1
  fi
  G_SOURCE=cache G_STATE=read G_REASON="" G_STATUS="$2" G_CTYPE="$DC_CTYPE" G_AT="$DC_RETRIEVED"
  G_VALIDATED="$C_ISO" G_AGE=$((DC_NOW - C_EPOCH)) G_KEY="$DC_KEY"
  G_FORMAT="$DC_FORMAT" G_TITLE="$DC_TITLE" G_QUAR="$DC_QUARANTINED" G_DATE="$C_DATE"
}

# settle_unread <url> <dest> <format>...: an unread page whose fetch failed (a
# transport error or a 5xx) is served stale from the candidate when --max-age
# allows staleness; one the server reports removed or redirected quarantines
# the URL's cache keys.
settle_unread() {
  local url="$1" dest="$2" reason="$G_REASON" status="$G_STATUS" f
  shift 2
  [[ $CACHE -eq 1 && "$G_STATE" != read ]] || return 0
  case "$reason" in
  fetch-failed | http-5[0-9][0-9])
    [[ $MAX_AGE -gt 0 && -n "$C_REF" ]] || return 0
    serve_cached "$dest" "$status" || return 0
    G_STALE=1 G_REASON="$reason"
    ;;
  http-404 | http-410 | redirected-off-origin | redirected-off-path | not-in-index)
    for f in "$@"; do dc_quarantine_reason "$(dc_key "$url" "$f")" "$reason"; done
    ;;
  *) ;;
  esac
}

# serve_fresh <dest> <format>...: serve the candidate when it was validated
# within --max-age. Outside fixture mode its stored content type must fit its
# format, so a fixture read (stored with none) never reaches a real read.
serve_fresh() {
  local dest="$1" age re
  [[ $CACHE -eq 1 && $MAX_AGE -gt 0 && -n "$C_REF" ]] || return 1
  age=$((DC_NOW - C_EPOCH))
  [[ $age -ge 0 && $age -le $MAX_AGE ]] || return 1
  re="$MD_OR_TEXT_CTYPE"
  [[ "$C_FORMAT" != html-converted ]] || re="$HTML_CTYPE"
  [[ $FIXTURE_SET -eq 1 || "${C_CTYPE,,}" =~ $re ]] || return 1
  serve_cached "$dest" ""
}

# request <accept> <url> <dest>: http_get, conditional when the candidate was
# last confirmed over this same request. A 304 to a conditional request serves
# the candidate and returns 0; anything else returns 1 with the H_ fields set.
request() {
  local inm="" ims=""
  if [[ -n "$C_REF" && "$C_ACCEPT" == "$1" && "$C_REQ_URL" == "$2" ]]; then inm="$C_ETAG" ims="$C_LM"; fi
  http_get "$2" "$3" "$1" "$inm" "$ims"
  [[ $H_RC -eq 0 && "$H_STATUS" == 304 && -n "$inm$ims" ]] || return 1
  rm -f "$3"
  dc_confirm "$C_REF" "$(dc_validators "$1" "$2" "${H_ETAG:-$C_ETAG}" "${H_LM:-$C_LM}")" "$H_DATE" || return 1
  C_EPOCH="$DC_VALIDATED_EPOCH" C_ISO="$DC_VALIDATED" C_DATE="$DC_SERVER_DATE"
  [[ -n "$4" ]] || return 0
  serve_cached "$4" 304
}

# store <url> <dest>: put a read page in the cache and take its record.
store() {
  G_VALIDATED="$G_AT" G_AGE=0
  [[ $CACHE -eq 1 ]] || return 0
  if dc_put "$1" "$G_FORMAT" "$2" "$G_CTYPE" "$G_TITLE_HINT" "$G_VALIDATORS" "$G_DATE"; then
    G_AT="$DC_RETRIEVED" G_VALIDATED="$DC_VALIDATED" G_KEY="$DC_KEY" G_TITLE="$DC_TITLE" G_QUAR="$DC_QUARANTINED"
  else
    G_CACHE_ERR="${DC_ERR:-the store refused the write}"
    echo "WARNING: $1 was read but not cached in $DC_DIR: $G_CACHE_ERR" >&2
  fi
}

# fixture_read <dest> <fixture file> <format>: a read from the fixture directory.
fixture_read() {
  G_SOURCE=fixture
  if [[ -s "$FIXTURE/$2" ]] && cp "$FIXTURE/$2" "$1"; then
    G_STATE=read G_FORMAT="$3"
    G_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  else
    G_REASON="fixture-missing"
  fi
}

# get_doc <url> <dest> <fixture file> <content-type regex>: an indexed
# profile's read, the whole body or nothing. Sets the G_ fields; on read the raw
# bytes are at <dest>, otherwise no file is left there.
get_doc() {
  local url="$1" dest="$2" ctype_re="$4"
  reset_g
  rm -f "$dest" "$dest.part"
  mkdir -p "$(dirname "$dest")"
  cache_candidate "$url" "$P_FORMAT"
  if [[ -n "$C_REF" && $FIXTURE_SET -eq 0 && ! "${C_CTYPE,,}" =~ $ctype_re ]]; then C_REF=""; fi
  serve_fresh "$dest" && return 0
  if [[ $FIXTURE_SET -eq 1 ]]; then
    fixture_read "$dest" "$3" "$P_FORMAT"
  else
    G_SOURCE=fetch
    if [[ $CURL_MISSING -eq 1 ]]; then
      G_REASON="curl-missing"
      return 0
    fi
    G_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    request "" "$url" "$dest.part" "$dest" && return 0
    G_STATUS="$H_STATUS" G_CTYPE="$H_CTYPE"
    if [[ $H_RC -eq 63 ]]; then
      G_REASON="too-large"
    elif [[ $H_RC -ne 0 ]]; then
      G_REASON="fetch-failed"
    elif [[ "$H_EFF" != "$ORIGIN$P_DOCS_PATH"* && ("$url" != "$INDEX_URL" || "$H_EFF" != "$INDEX_URL") ]]; then
      # A page lands under the docs path; the index, at its own URL.
      G_REASON="redirected-off-origin"
    elif [[ ! "$H_STATUS" =~ ^2[0-9][0-9]$ ]]; then
      G_REASON="http-${H_STATUS:-unknown}"
    elif [[ ! "${H_CTYPE,,}" =~ $ctype_re ]]; then
      G_REASON="unexpected-content-type"
    elif [[ ! -s "$dest.part" ]]; then
      G_REASON="empty-body"
    elif mv "$dest.part" "$dest"; then
      G_STATE=read G_FORMAT="$P_FORMAT" G_VALIDATORS="$(dc_validators_or_none "" "$url")" G_DATE="$H_DATE"
    fi
    rm -f "$dest.part"
  fi
  if [[ "$G_STATE" != read ]]; then
    settle_unread "$url" "$dest" "$P_FORMAT"
    return 0
  fi
  store "$url" "$dest"
}

# dc_validators_or_none <accept> <url>: the validators record of the last
# response, or nothing without --cache.
dc_validators_or_none() {
  [[ $CACHE -eq 1 ]] || return 0
  dc_validators "$1" "$2" "$H_ETAG" "$H_LM"
}

# url_parts <url>: set U_ORIGIN (scheme and host lower-cased) and U_PATH (the
# rest, fragment dropped, one trailing slash dropped); return 1 unless https.
url_parts() {
  local u="${1%%#*}"
  [[ "$u" =~ ^([Hh][Tt][Tt][Pp][Ss]://[^/?]+)(.*)$ ]] || return 1
  U_ORIGIN="${BASH_REMATCH[1],,}" U_PATH="${BASH_REMATCH[2]}"
  [[ "$U_PATH" == "/" || "$U_PATH" != */ ]] || U_PATH="${U_PATH%/}"
  [[ -n "$U_PATH" ]] || U_PATH="/"
}

# landed <requested> <effective>: same, off-origin or off-path.
landed() {
  local o p
  url_parts "$1" || return 1
  o="$U_ORIGIN" p="$U_PATH"
  url_parts "$2" || {
    printf off-origin
    return 0
  }
  if [[ "$U_ORIGIN" != "$o" ]]; then
    printf off-origin
  elif [[ "$U_PATH" != "$p" ]]; then
    printf off-path
  else
    printf same
  fi
}

# generic_slug <url>: host/path, lower-cased, every character outside
# [a-z0-9_-/] replaced by -, a trailing .md dropped.
generic_slug() {
  local LC_ALL=C s
  url_parts "$1" || return 1
  s="${U_ORIGIN#https://}$U_PATH"
  s="${s%/}"
  s="${s%.md}"
  s="${s,,}"
  s="${s//[^a-z0-9_\/-]/-}"
  printf '%s' "$s"
}

# resolve_python: set PY to the first of python3 and python whose probe prints
# 3 (a Store stub or a Python 2 fails it); return 1 when none does.
resolve_python() {
  local c v
  if [[ -n "${PY_STATE:-}" ]]; then [[ "$PY_STATE" == ok ]] && return 0 || return 1; fi
  PY_STATE=none
  for c in python3 python; do
    command -v "$c" >/dev/null 2>&1 || continue
    v="$(with_timeout 30 "$c" -c 'import sys; print(sys.version_info[0])' 2>/dev/null </dev/null)"
    [[ "${v%$'\r'}" == 3 ]] || continue
    PY="$c" PY_STATE=ok
    return 0
  done
  return 1
}

# html_title <file>: the first <title> element's text, whitespace collapsed.
html_title() {
  LC_ALL=C awk '
    { buf = buf " " $0 }
    END {
      low = tolower(buf)
      s = index(low, "<title")
      if (!s) exit
      rest = substr(buf, s); g = index(rest, ">")
      if (!g) exit
      rest = substr(rest, g + 1); e = index(tolower(rest), "</title")
      if (!e) exit
      t = substr(rest, 1, e - 1); gsub(/[ \t\r\n]+/, " ", t); sub(/^ /, "", t); sub(/ $/, "", t)
      print t
    }' "$1"
}

# bundle_link <origin> <path> <tried url>: set B_LINK to the same-origin
# llms.txt link for the page (empty when none); the llms.txt is fetched once per
# origin and run.
bundle_link() {
  local origin="$1" path="$2" idx="$WORK/bundle-${#BUNDLES[@]}.txt" u p
  B_LINK=""
  if [[ -z "${BUNDLES[$origin]:-}" ]]; then
    BUNDLES[$origin]=none
    http_get "$origin/llms.txt" "$idx" "" "" ""
    if [[ $H_RC -eq 0 && "$H_STATUS" =~ ^2[0-9][0-9]$ && "${H_CTYPE,,}" =~ $MD_OR_TEXT_CTYPE && -s "$idx" &&
      "$(landed "$origin/llms.txt" "$H_EFF")" == same ]]; then
      BUNDLES[$origin]="$idx"
    fi
  fi
  [[ "${BUNDLES[$origin]}" != none ]] || return 0
  while IFS= read -r u; do
    [[ "$u" != /* || "$u" == //* ]] || u="$origin$u"
    url_parts "$u" && [[ "$U_ORIGIN" == "$origin" ]] || continue
    p="${U_PATH%.md}"
    p="${p%.txt}"
    p="${p%/index}"
    if [[ "$p" == "$path" && "$u" != "$3" ]]; then
      B_LINK="$u"
      return 0
    fi
  done < <(link_urls "${BUNDLES[$origin]}")
}

# markdown_channel <accept> <url> <dest> <ctype regex>: one markdown channel of
# a generic read. Returns 0 when it settled the page (read, or served by a 304).
markdown_channel() {
  request "$1" "$2" "$3.part" "$3" && return 0
  if [[ $H_RC -eq 0 && "$(landed "$2" "$H_EFF")" == same && "$H_STATUS" =~ ^2[0-9][0-9]$ &&
  "${H_CTYPE,,}" =~ $4 && -s "$3.part" ]] && mv "$3.part" "$3"; then
    G_STATE=read G_FORMAT=markdown G_STATUS="$H_STATUS" G_CTYPE="$H_CTYPE" G_DATE="$H_DATE"
    G_VALIDATORS="$(dc_validators_or_none "$1" "$2")"
    return 0
  fi
  rm -f "$3.part"
  return 1
}

# convert <html> <dest>: run the converter. Sets G_REASON on failure.
convert() {
  if ! resolve_python; then
    G_REASON="no-python"
  elif [[ ! -f "$CONVERTER" ]]; then
    G_REASON="converter-missing"
  elif with_timeout 120 env PYTHONUTF8=1 "$PY" "$CONVERTER" "$1" >"$2.part" 2>/dev/null </dev/null && [[ -s "$2.part" ]] &&
    mv "$2.part" "$2"; then
    return 0
  else
    G_REASON="convert-failed"
  fi
  rm -f "$2.part"
  return 1
}

# get_generic <url> <dest> <fixture file>: a generic read, markdown preferred,
# converted HTML otherwise. Sets the G_ fields like get_doc.
get_generic() {
  local url="$1" dest="$2" html="$WORK/page.html" html_status="" html_ctype="" html_val="" html_date="" sfx=""
  reset_g
  rm -f "$dest" "$dest.part" "$html"
  mkdir -p "$(dirname "$dest")"
  cache_candidate "$url" markdown html-converted
  serve_fresh "$dest" && return 0
  if [[ $FIXTURE_SET -eq 1 ]]; then
    fixture_read "$dest" "$3" markdown
    [[ "$G_STATE" != read ]] || store "$url" "$dest"
    return 0
  fi
  G_SOURCE=fetch
  if [[ $CURL_MISSING -eq 1 ]]; then
    G_REASON="curl-missing"
    return 0
  fi
  G_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  url_parts "$url"
  local origin="$U_ORIGIN" path="$U_PATH"

  # The page's own request decides identity: a failure or a landing elsewhere ends the read.
  request text/markdown "$url" "$dest.part" "$dest" && return 0
  G_STATUS="$H_STATUS" G_CTYPE="$H_CTYPE"
  if [[ $H_RC -eq 63 ]]; then
    G_REASON="too-large"
  elif [[ $H_RC -ne 0 ]]; then
    G_REASON="fetch-failed"
  else
    case "$(landed "$url" "$H_EFF")" in
    off-origin) G_REASON="redirected-off-origin" ;;
    off-path) G_REASON="redirected-off-path" ;;
    *) ;;
    esac
  fi
  if [[ -n "$G_REASON" ]]; then
    rm -f "$dest.part"
    settle_unread "$url" "$dest" markdown html-converted
    return 0
  fi
  if [[ "$H_STATUS" =~ ^2[0-9][0-9]$ && "${H_CTYPE,,}" =~ $MD_CTYPE && -s "$dest.part" ]] && mv "$dest.part" "$dest"; then
    G_STATE=read G_FORMAT=markdown G_VALIDATORS="$(dc_validators_or_none text/markdown "$url")" G_DATE="$H_DATE"
  elif [[ "$H_STATUS" =~ ^2[0-9][0-9]$ && "${H_CTYPE,,}" =~ $HTML_CTYPE && -s "$dest.part" ]]; then
    mv "$dest.part" "$html"
    html_status="$H_STATUS" html_ctype="$H_CTYPE" html_val="$(dc_validators_or_none text/markdown "$url")" html_date="$H_DATE"
  else
    G_REASON="http-${H_STATUS:-unknown}"
    [[ ! "$H_STATUS" =~ ^2[0-9][0-9]$ ]] || G_REASON="unexpected-content-type"
  fi
  rm -f "$dest.part"

  if [[ "$G_STATE" != read && "$path" != *.md ]]; then
    sfx="$origin$path.md"
    [[ "$path" != / ]] || sfx="$origin/index.md"
    markdown_channel "" "$sfx" "$dest" "$MD_OR_TEXT_CTYPE" && [[ "$G_SOURCE" == cache ]] && return 0
  fi
  if [[ "$G_STATE" != read ]]; then
    bundle_link "$origin" "$path" "${sfx:-}"
    if [[ -n "$B_LINK" ]]; then
      markdown_channel "" "$B_LINK" "$dest" "$MD_OR_TEXT_CTYPE" && [[ "$G_SOURCE" == cache ]] && return 0
    fi
  fi
  if [[ "$G_STATE" != read && -z "$html_status" ]]; then
    request "" "$url" "$html" "$dest" && return 0
    [[ $H_RC -ne 63 ]] || G_REASON="too-large"
    if [[ $H_RC -eq 0 && "$(landed "$url" "$H_EFF")" == same && "$H_STATUS" =~ ^2[0-9][0-9]$ &&
    "${H_CTYPE,,}" =~ $HTML_CTYPE && -s "$html" ]]; then
      html_status="$H_STATUS" html_ctype="$H_CTYPE" html_val="$(dc_validators_or_none "" "$url")" html_date="$H_DATE"
    fi
  fi
  if [[ "$G_STATE" != read && -n "$html_status" ]]; then
    G_STATUS="$html_status" G_CTYPE="$html_ctype"
    if convert "$html" "$dest"; then
      G_STATE=read G_REASON="" G_FORMAT=html-converted G_VALIDATORS="$html_val" G_DATE="$html_date"
      G_TITLE_HINT="$(html_title "$html")"
    fi
  fi
  rm -f "$html"
  if [[ "$G_STATE" != read ]]; then
    settle_unread "$url" "$dest" markdown html-converted
    return 0
  fi
  G_REASON=""
  store "$url" "$dest"
}

# emit <slug> <url> <mode> <file>: print one manifest record from the G_ result.
emit() {
  local sha="" bytes=0 lines=0 file=""
  if [[ "$G_STATE" == read ]]; then
    file="$4"
    sha="$(sha256_of "$file")"
    bytes="$(wc -c <"$file" | tr -d ' ')"
    lines="$(awk 'END { print NR }' "$file")"
  else
    G_FORMAT="" G_TITLE="" G_QUAR="" G_DATE=""
  fi
  jq -cn --arg slug "$1" --arg url "$2" --arg mode "$3" --arg source "$G_SOURCE" --arg at "$G_AT" --arg sha "$sha" \
    --arg status "$G_STATUS" --arg ctype "$G_CTYPE" --argjson bytes "$bytes" --argjson lines "$lines" --arg file "$file" \
    --arg state "$G_STATE" --arg reason "$G_REASON" --arg validated "$G_VALIDATED" --arg age "$G_AGE" --arg key "$G_KEY" \
    --arg format "$G_FORMAT" --arg title "$G_TITLE" --arg quar "$G_QUAR" --arg stale "$G_STALE" --arg sdate "$G_DATE" \
    --arg cerr "$G_CACHE_ERR" \
    'def n: if . == "" then null else . end;
     {slug: $slug, url: ($url | n), mode: $mode, source: ($source | n), retrieved: ($at | n),
      validated: ($validated | n), age_seconds: ($age | n | if . == null then null else tonumber end),
      cache_key: ($key | n), sha256: ($sha | n),
      status: ($status | if . == "" then null else tonumber end), content_type: ($ctype | n), bytes: $bytes,
      lines: $lines, file: ($file | n), format: ($format | n), title: ($title | n),
      quarantined: (if $quar == "" then null else $quar == "1" end), stale: ($stale == "1"),
      server_date: ($sdate | n), cache_error: ($cerr | n), state: $state, reason: ($reason | n)}'
}

# link_urls <file>: every link URL in the file, one per line.
link_urls() {
  awk '{
    while (match($0, /\]\([^) \t]+\)/)) {
      print substr($0, RSTART + 2, RLENGTH - 3)
      $0 = substr($0, RSTART + RLENGTH)
    }
  }' "$1"
}

# index_link <slug>: the first link URL in the index whose path is exactly
# <docs-path>en/<slug><suffix> or <docs-path><slug><suffix>, on any scheme (or none) and host (an
# off-origin link is reported by the caller). A page nested under another path (plugins/x.md) is
# a different slug and never matches x.
index_link() {
  link_urls "$OUT/llms.txt" | awk -v a="${P_DOCS_PATH}en/$1${P_SUFFIX}" -v b="${P_DOCS_PATH}$1${P_SUFFIX}" '{ p = $0; sub(/^([A-Za-z][A-Za-z0-9+.-]*:)?\/\/[^\/]+/, "", p) } p == a || p == b { print; exit }'
}

# slug_of <url>: the slug an index link names: its path under the profile path, without a
# leading en/ and the raw-channel suffix.
slug_of() {
  local s="${1#"$ORIGIN$P_DOCS_PATH"}"
  s="${s#en/}"
  printf '%s' "${s%"$P_SUFFIX"}"
}

# A slug becomes a path under --out: lower-case segments joined by `/`, never
# `.`, `..` or a leading `/`. The C locale keeps `a-z` an ASCII range.
slug_ok() {
  local LC_ALL=C re='^[a-z0-9_-]+(/[a-z0-9_-]+)*$'
  [[ "$1" =~ $re ]]
}

declare -A SEEN=()
declare -A BUNDLES=()

if [[ "$P_KIND" == url ]]; then
  printf 'null\n' >"$INDEX_REC"
  for i in "${!TARGETS[@]}"; do
    t="${TARGETS[$i]}"
    m="${TARGET_MODES[$i]}"
    reset_g
    if ! slug="$(generic_slug "$t")"; then
      G_REASON="invalid-url"
      emit "$t" "" "$m" "" >>"$PAGE_RECS"
      continue
    fi
    if ! slug_ok "$slug"; then
      G_REASON="invalid-slug"
      emit "$t" "$t" "$m" "" >>"$PAGE_RECS"
      continue
    fi
    if [[ -n "${SEEN[$slug]:-}" ]]; then
      [[ "${SEEN[$slug]}" != "${t%%#*}" ]] || continue
      G_REASON="slug-collision"
      emit "$slug" "$t" "$m" "" >>"$PAGE_RECS"
      continue
    fi
    SEEN[$slug]="${t%%#*}"
    get_generic "$t" "$OUT/$slug.md" "$slug.md"
    emit "$slug" "$t" "$m" "$OUT/$slug.md" >>"$PAGE_RECS"
  done
else
  # The index first: every page resolves through it.
  get_doc "$INDEX_URL" "$OUT/llms.txt" llms.txt "$P_INDEX_CTYPE"
  INDEX_STATE="$G_STATE"
  emit index "$INDEX_URL" "" "$OUT/llms.txt" >"$INDEX_REC"

  if [[ $DISCOVER -eq 1 && "$INDEX_STATE" == read ]]; then
    while IFS= read -r u; do
      [[ "$u" == "$ORIGIN$P_DOCS_PATH"*"$P_SUFFIX" ]] || continue
      TARGETS+=("$u")
      TARGET_MODES+=("$MODE")
    done < <(link_urls "$OUT/llms.txt")
  fi

  for i in "${!TARGETS[@]}"; do
    t="${TARGETS[$i]}"
    m="${TARGET_MODES[$i]}"
    want=""
    slug="${t%"$P_SUFFIX"}"
    if [[ "$t" == *://* ]]; then
      want="$t"
      slug="$(slug_of "$t")"
    fi
    [[ -z "${SEEN[$slug]:-}" ]] || continue
    SEEN[$slug]=1
    reset_g
    url=""
    if ! slug_ok "$slug"; then
      G_REASON="invalid-slug"
      emit "$t" "$want" "$m" "" >>"$PAGE_RECS"
      continue
    fi
    rm -f "$OUT/$slug.md"
    if [[ "$INDEX_STATE" != read ]]; then
      G_REASON="index-unread"
    else
      url="$(index_link "$slug")"
      if [[ -z "$url" || (-n "$want" && "$url" != "$want") ]]; then
        url=""
        G_REASON="not-in-index"
        if [[ $CACHE -eq 1 ]]; then
          for u in "$want" "$ORIGIN${P_DOCS_PATH}en/$slug$P_SUFFIX" "$ORIGIN$P_DOCS_PATH$slug$P_SUFFIX"; do
            [[ -z "$u" ]] || dc_quarantine_reason "$(dc_key "$u" "$P_FORMAT")" not-in-index
          done
        fi
      elif [[ "$url" != "$ORIGIN$P_DOCS_PATH"* ]]; then
        G_REASON="off-origin"
      else
        get_doc "$url" "$OUT/$slug.md" "$slug.md" "$P_PAGE_CTYPE"
      fi
    fi
    emit "$slug" "$url" "$m" "$OUT/$slug.md" >>"$PAGE_RECS"
  done
fi

claude_bin="${FETCH_DOCS_CLAUDE_BIN-$(command -v claude 2>/dev/null || true)}"
claude_version=""
if [[ -n "$claude_bin" && -f "$claude_bin" ]]; then
  raw="$(with_timeout 30 "$claude_bin" --version 2>/dev/null </dev/null | head -n 1)"
  [[ "$raw" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && claude_version="${BASH_REMATCH[1]}"
fi

if jq -n --arg v "$claude_version" --slurpfile idx "$INDEX_REC" --slurpfile pages "$PAGE_RECS" --arg cd "$CACHE_DISABLED" \
  '{claude_version: $v, index: $idx[0], pages: $pages, cache_disabled: (if $cd == "" then null else $cd end)}' >"$MANIFEST.tmp"; then
  mv "$MANIFEST.tmp" "$MANIFEST" || die "could not write $MANIFEST"
else
  die "could not write $MANIFEST"
fi
