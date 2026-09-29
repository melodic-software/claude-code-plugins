#!/usr/bin/env bash
# Upstream docs fetcher for claude-config.
#
# The audit skill rests on official Claude Code docs pages: it greps them for
# cited spans and reads them for the criteria its checks apply. This script is
# the one place those pages are fetched. It resolves every page through the
# docs index (llms.txt), reads it verbatim over the raw-markdown channel to a
# file, and writes a manifest of what it did. It never reads, searches or
# summarizes a page: it guarantees complete bytes on disk plus the manifest, and
# the caller reads.
#
# Identity comes from the index. A slug the index does not list is not fetched:
# a retired slug can answer 200 with another page's body, so a body that
# arrived is no proof the page exists. A page is read only when the whole body
# arrived over HTTPS from the docs origin as text/markdown with a 2xx status.
# Anything else is unread and leaves no file, so a partial or foreign body is
# never counted as read.
#
# The page file is the raw bytes as fetched. The manifest hash is taken over
# those bytes, so a caller that strips control characters from a working copy
# does not change it.
#
# Manifest (JSON, written to --manifest):
#   claude_version  installed `claude --version` number, or "" when unreadable
#   index           record for the index itself
#   pages[]         one record per requested page, in request order
# Each record: slug, url, mode, source (fetch|fixture), retrieved (UTC ISO),
# sha256 (raw bytes), status (HTTP code), content_type, bytes, lines, file
# (path on disk), state, reason. state is read or unread; unparsed is set by a
# caller whose parse of a read page failed. mode (full|search) is the caller's
# declaration of how it will use the page; the fetcher only records it. Fields
# with no value are null (a page never requested has no status).
#
# Exit codes:
#   0  the manifest was written (pages may be unread; read the manifest)
#   2  fatal (bad arguments, jq missing, manifest not writable)
#
# Env overrides (the test seam):
#   SETTINGS_AUDIT_ENGINE_DOCS_FIXTURE_DIR  directory of llms.txt and <slug>.md
#       files. Set, even to an empty or missing directory, means no network: a
#       file the directory lacks is unread (fixture-missing), never fetched.
#   SETTINGS_AUDIT_ENGINE_DOCS_INDEX_URL    index URL when --index-url is absent
#   SETTINGS_AUDIT_ENGINE_CLAUDE_BIN        claude binary for claude_version

set -uo pipefail

usage() {
  cat <<'EOF'
fetch-docs.sh — fetch official docs pages verbatim and write a manifest.

Usage:
  fetch-docs.sh --out <dir> [--manifest <file>] [--index-url <url>] [--follow <depth>]
                (--discover | [--mode full|search] <slug|url>...)

  --out <dir>        directory for the page files (<slug>.md) and the index (llms.txt)
  --manifest <file>  manifest path (default: <dir>/manifest.json)
  --index-url <url>  docs index (default: https://code.claude.com/docs/llms.txt)
  --discover         request every page the index links on the docs origin
  --mode <m>         how the caller will use the pages that follow: full (default) or search
  --follow <depth>   reserved for link-following; accepted, default 0, acted on by no caller
  <slug|url>         a page slug (settings-reference) or a docs-origin URL the index lists

Exit: 0 manifest written; 2 fatal.
EOF
}

die() {
  echo "ERROR: $1" >&2
  exit 2
}

INDEX_URL="${SETTINGS_AUDIT_ENGINE_DOCS_INDEX_URL:-https://code.claude.com/docs/llms.txt}"
OUT=""
MANIFEST=""
DISCOVER=0
MODE=full
TARGETS=()
TARGET_MODES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --out | --manifest | --index-url | --follow | --mode)
    [[ $# -ge 2 ]] || die "$1 needs a value"
    case "$1" in
    --out) OUT="$2" ;;
    --manifest) MANIFEST="$2" ;;
    --index-url) INDEX_URL="$2" ;;
    --follow) [[ "$2" =~ ^[0-9]+$ ]] || die "--follow needs a non-negative integer" ;; # depth is validated and dropped: no caller follows links
    --mode)
      [[ "$2" == full || "$2" == search ]] || die "--mode is full or search"
      MODE="$2"
      ;;
    *) die "unreachable" ;;
    esac
    shift 2
    ;;
  --discover)
    DISCOVER=1
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

[[ -n "$OUT" ]] || die "--out is required"
[[ $DISCOVER -eq 1 || ${#TARGETS[@]} -gt 0 ]] || die "name a page or pass --discover"
command -v jq >/dev/null 2>&1 || die "jq required"
ORIGIN=""
[[ "$INDEX_URL" =~ ^(https://[^/]+) ]] && ORIGIN="${BASH_REMATCH[1]}"
[[ -n "$ORIGIN" ]] || die "--index-url must be an https URL"

FIXTURE_SET=0
[[ -n "${SETTINGS_AUDIT_ENGINE_DOCS_FIXTURE_DIR+x}" ]] && FIXTURE_SET=1
FIXTURE="${SETTINGS_AUDIT_ENGINE_DOCS_FIXTURE_DIR:-}"
CURL_MISSING=0
if [[ $FIXTURE_SET -eq 0 ]] && ! command -v curl >/dev/null 2>&1; then CURL_MISSING=1; fi

mkdir -p "$OUT" || die "cannot create $OUT"
MANIFEST="${MANIFEST:-$OUT/manifest.json}"
mkdir -p "$(dirname "$MANIFEST")" || die "cannot create the manifest directory"
INDEX_REC="$(mktemp)" || die "could not create a temp file"
PAGE_RECS="$(mktemp)" || die "could not create a temp file"
trap 'rm -f "$INDEX_REC" "$PAGE_RECS"' EXIT

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum <"$1" | cut -d' ' -f1; else shasum -a 256 <"$1" | cut -d' ' -f1; fi
}

# get_doc <url> <dest> <fixture file> <content-type regex>: the whole body or
# nothing. Sets G_SOURCE G_STATE G_REASON G_STATUS G_CTYPE G_AT; on read the
# raw bytes are at <dest>, otherwise no file is left there.
get_doc() {
  local url="$1" dest="$2" fx="$3" ctype_re="$4" meta rc eff
  G_SOURCE="" G_STATE=unread G_REASON="" G_STATUS="" G_CTYPE="" G_AT=""
  rm -f "$dest" "$dest.part"
  mkdir -p "$(dirname "$dest")"
  if [[ $FIXTURE_SET -eq 1 ]]; then
    G_SOURCE=fixture
    if [[ -s "$FIXTURE/$fx" ]] && cp "$FIXTURE/$fx" "$dest"; then
      G_STATE="read"
      G_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
      G_REASON="fixture-missing"
    fi
    return 0
  fi
  G_SOURCE=fetch
  if [[ $CURL_MISSING -eq 1 ]]; then
    G_REASON="curl-missing"
    return 0
  fi
  G_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # No -f: an HTTP error still prints its status and content type through -w.
  meta="$(curl -sSL --proto =https --proto-redir =https --max-redirs 5 --connect-timeout 15 --max-time 120 \
    -w '%{http_code} %{url_effective} %{content_type}' -o "$dest.part" "$url" 2>/dev/null)"
  rc=$?
  read -r G_STATUS eff G_CTYPE <<<"$meta"
  [[ "$G_STATUS" =~ ^[0-9]+$ ]] || G_STATUS=""
  if [[ $rc -ne 0 ]]; then
    G_REASON="fetch-failed"
  elif [[ "$eff" != "$ORIGIN/docs/"* ]]; then
    G_REASON="redirected-off-origin"
  elif [[ ! "$G_STATUS" =~ ^2[0-9][0-9]$ ]]; then
    G_REASON="http-${G_STATUS:-unknown}"
  elif [[ ! "${G_CTYPE,,}" =~ $ctype_re ]]; then
    G_REASON="unexpected-content-type"
  elif [[ ! -s "$dest.part" ]]; then
    G_REASON="empty-body"
  else
    mv "$dest.part" "$dest" && G_STATE="read"
  fi
  rm -f "$dest.part"
}

# emit <slug> <url> <mode> <file>: print one manifest record from the G_ result.
emit() {
  local sha="" bytes=0 lines=0 file=""
  if [[ "$G_STATE" == read ]]; then
    file="$4"
    sha="$(sha256_of "$file")"
    bytes="$(wc -c <"$file" | tr -d ' ')"
    lines="$(awk 'END { print NR }' "$file")"
  fi
  jq -cn --arg slug "$1" --arg url "$2" --arg mode "$3" --arg source "$G_SOURCE" --arg at "$G_AT" --arg sha "$sha" \
    --arg status "$G_STATUS" --arg ctype "$G_CTYPE" --argjson bytes "$bytes" --argjson lines "$lines" --arg file "$file" \
    --arg state "$G_STATE" --arg reason "$G_REASON" \
    'def n: if . == "" then null else . end;
     {slug: $slug, url: ($url | n), mode: $mode, source: ($source | n), retrieved: ($at | n), sha256: ($sha | n),
      status: ($status | if . == "" then null else tonumber end), content_type: ($ctype | n), bytes: $bytes,
      lines: $lines, file: ($file | n), state: $state, reason: ($reason | n)}'
}

# link_urls: every link URL in the index, one per line.
link_urls() {
  awk '{
    while (match($0, /\]\([^) \t]+\)/)) {
      print substr($0, RSTART + 2, RLENGTH - 3)
      $0 = substr($0, RSTART + RLENGTH)
    }
  }' "$OUT/llms.txt"
}

# index_link <slug>: the first link URL in the index whose path is exactly
# /docs/en/<slug>.md or /docs/<slug>.md, on any host (an off-origin link is
# reported by the caller). A page nested under another path (plugins/x.md) is
# a different slug and never matches x.
index_link() {
  link_urls | awk -v a="/docs/en/$1.md" -v b="/docs/$1.md" '{ p = $0; sub(/^https:\/\/[^\/]+/, "", p) } p == a || p == b { print; exit }'
}

# slug_of <url>: the slug an index link names: its path under /docs/, without a
# leading en/ and the .md suffix.
slug_of() {
  local s="${1#"$ORIGIN"/docs/}"
  s="${s#en/}"
  printf '%s' "${s%.md}"
}

# A slug becomes a path under --out: lower-case segments joined by `/`, never
# `.`, `..` or a leading `/`. The C locale keeps `a-z` an ASCII range.
slug_ok() {
  local LC_ALL=C re='^[a-z0-9_-]+(/[a-z0-9_-]+)*$'
  [[ "$1" =~ $re ]]
}

# The index first: every page resolves through it.
get_doc "$INDEX_URL" "$OUT/llms.txt" llms.txt '^text/(plain|markdown)'
INDEX_STATE="$G_STATE"
emit index "$INDEX_URL" "" "$OUT/llms.txt" >"$INDEX_REC"

if [[ $DISCOVER -eq 1 && "$INDEX_STATE" == read ]]; then
  while IFS= read -r u; do
    [[ "$u" == "$ORIGIN/docs/"*.md ]] || continue
    TARGETS+=("$u")
    TARGET_MODES+=("$MODE")
  done < <(link_urls)
fi

declare -A SEEN=()
for i in "${!TARGETS[@]}"; do
  t="${TARGETS[$i]}"
  m="${TARGET_MODES[$i]}"
  want=""
  slug="${t%.md}"
  if [[ "$t" == *://* ]]; then
    want="$t"
    slug="$(slug_of "$t")"
  fi
  [[ -z "${SEEN[$slug]:-}" ]] || continue
  SEEN[$slug]=1
  G_SOURCE="" G_STATE=unread G_REASON="" G_STATUS="" G_CTYPE="" G_AT=""
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
    elif [[ "$url" != "$ORIGIN/docs/"* ]]; then
      G_REASON="off-origin"
    else
      get_doc "$url" "$OUT/$slug.md" "$slug.md" '^text/markdown'
    fi
  fi
  emit "$slug" "$url" "$m" "$OUT/$slug.md" >>"$PAGE_RECS"
done

claude_bin="${SETTINGS_AUDIT_ENGINE_CLAUDE_BIN-$(command -v claude 2>/dev/null || true)}"
claude_version=""
if [[ -n "$claude_bin" && -f "$claude_bin" ]]; then
  if command -v timeout >/dev/null 2>&1; then
    raw="$(timeout 30 "$claude_bin" --version 2>/dev/null </dev/null | head -n 1)"
  else
    raw="$("$claude_bin" --version 2>/dev/null </dev/null | head -n 1)"
  fi
  [[ "$raw" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && claude_version="${BASH_REMATCH[1]}"
fi

if jq -n --arg v "$claude_version" --slurpfile idx "$INDEX_REC" --slurpfile pages "$PAGE_RECS" \
  '{claude_version: $v, index: $idx[0], pages: $pages}' >"$MANIFEST.tmp"; then
  mv "$MANIFEST.tmp" "$MANIFEST" || die "could not write $MANIFEST"
else
  die "could not write $MANIFEST"
fi
