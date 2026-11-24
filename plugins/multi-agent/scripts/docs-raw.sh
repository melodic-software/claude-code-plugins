#!/usr/bin/env bash
# GENERATED from lib/docs-raw.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Fresh raw read of one docs page through fetch-docs.sh and docs-cache.sh
# beside this script, for an agent whose shell may run this command and
# nothing else (the docs-fetcher agents, held to it by their plugin's
# docs-fetcher-gate.mjs). It takes no path argument and writes only a temporary
# directory it removes on exit.
#
#   docs-raw.sh [--render] <url> [<section-id>...]
#
# --render is for a benchmark registry fetcher: the URL must be a row link in
# ../reference/benchmarks.json beside this script, and the fetch passes that
# row's expect marker and --render-fallback, so a page that comes back blocked
# or without the marker (a page drawn by script) is rendered through the
# Firecrawl CLI when docs-cache.sh's renderer is firecrawl.
#
# The page is fetched with --cache --max-age 0, so the server is asked every
# time and cached bytes never stand in for a failed fetch. The profile follows
# the host: code.claude.com is anthropic, platform.claude.com is platform, and
# any other https host is generic. A #fragment is dropped before the fetch; the
# caller picks sections from the map itself. The fetch runs with --public-only,
# so a host, a redirect or a DNS answer that leads to a non-global address is
# unread private-address. A generic page is cached in the temporary directory,
# never the shared docs cache, so pages an untrusted URL names cannot push the
# user's own entries out of it.
#
# Output: one header line, then the body.
#   docs-raw: url=<url> state=unread reason=<reason>
#   docs-raw: url=<url> state=read format=<f> validated=<iso> sha256=<page sha> kind=<k> bytes=<n> body_sha256=<sha>
# With no ids, kind is page (the whole page, at or under the cache's
# whole-page threshold) or map (its section map: id level start end bytes
# sha256 heading_path). With ids, kind is sections: each section's heading,
# body and child sections. kind too-large has no body: the ids asked for more
# than MAX_BODY bytes, or the body would pass it. MAX_BODY, which also caps
# kind page, stays under the 30000 characters of Bash output Claude Code reads
# back by default (BASH_MAX_OUTPUT_LENGTH,
# https://code.claude.com/docs/en/env-vars), so the header is never cut off. The body's CRLF line ends
# become LF; bytes and body_sha256 are the byte count and hash of the body
# without its trailing newlines, so a reader can tell a retyped body from the
# printed one. Summaries and notes are never printed: this is a
# verification read.
#
# Exit: 0 header printed (the page may be unread); 2 bad arguments, or the
# lookup itself failed.
set -uo pipefail

MAX_BODY=28000
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "docs-raw: $1" >&2
  exit 2
}

render=0
if [[ "${1:-}" == --render ]]; then
  render=1
  shift
fi
[[ $# -ge 1 ]] || die "usage: docs-raw.sh [--render] <url> [<section-id>...]"
url="${1%%#*}"
shift
[[ "$url" =~ ^https://([A-Za-z0-9.-]+)(:[0-9]{1,5})?([/?].*)?$ ]] || die "not an https URL: $url"
host="${BASH_REMATCH[1],,}"
[[ "$url" =~ [[:space:][:cntrl:]] ]] && die "the URL carries whitespace or a control character"
[[ $# -le 20 ]] || die "at most 20 section ids"
for id in "$@"; do
  [[ "$id" =~ ^[1-9][0-9]{0,5}$ ]] || die "not a section id: $id"
done

case "$host" in
code.claude.com) profile=anthropic ;;
platform.claude.com) profile=platform ;;
*) profile=generic ;;
esac

extra=()
if [[ $render -eq 1 ]]; then
  registry="$HERE/../reference/benchmarks.json"
  [[ -f "$registry" ]] || die "--render needs a benchmark registry beside this script"
  expect="$(jq -r --arg u "$url" '[.rows[] | select((.link | sub("#.*$"; "")) == $u) | .expect] | first // empty' "$registry")" ||
    die "cannot read the benchmark registry"
  [[ -n "$expect" ]] || die "--render: not a registry row link: $url"
  extra=(--render-fallback --expect "$expect")
fi

tmp="$(mktemp -d)" || die "cannot make a temporary directory"
trap 'rm -rf "$tmp"' EXIT
store=()
[[ "$profile" != generic ]] || store=(--cache-dir "$tmp/cache")

bash "$HERE/fetch-docs.sh" --cache --max-age 0 --public-only ${store[@]+"${store[@]}"} ${extra[@]+"${extra[@]}"} --profile "$profile" --out "$tmp/out" "$url" >/dev/null ||
  die "fetch-docs.sh failed"
# Unit separators, not tabs: IFS whitespace would merge an empty field into the next.
IFS=$'\x1f' read -r state reason key sha format validated bytes file < <(
  jq -r '.pages[0] | [.state, (.reason // "-"), (.cache_key // ""), (.sha256 // ""), (.format // ""),
    (.validated // ""), (.bytes // 0 | tostring), (.file // "")] | join("\u001f")' "$tmp/out/manifest.json"
) || die "cannot read the manifest"
file="${file%$'\r'}" # a Windows jq ends its line with CRLF

if [[ "$state" != read ]]; then
  printf 'docs-raw: url=%s state=unread reason=%s\n' "$url" "$reason"
  exit 0
fi

cache=(bash "$HERE/docs-cache.sh" ${store[@]+"${store[@]}"} --escalate-percent 100 --escalate-bytes "$MAX_BODY")
whole="$("${cache[@]}" config | sed -n 's/^whole_page_bytes=\([0-9]*\) .*/\1/p')"
[[ "$whole" =~ ^[0-9]+$ ]] || die "cannot read whole_page_bytes from docs-cache.sh config"
[[ "$whole" -le "$MAX_BODY" ]] || whole="$MAX_BODY"
# The pinned entry when the cache stored one; the fetched file when it did not.
if [[ -n "$key" ]]; then src=("$key-$sha"); else src=(--file "$file"); fi

if [[ $# -gt 0 ]]; then
  kind=sections
  body="$("${cache[@]}" slice "${src[@]}" "$@" 2>"$tmp/slice.err")" || die "slice failed: $(head -c 300 "$tmp/slice.err")"
  grep -q 'whole page' "$tmp/slice.err" && kind=too-large
elif [[ "$bytes" -le "$whole" ]]; then
  kind=page
  if [[ -n "$key" ]]; then body="$("${cache[@]}" read --raw "${src[@]}")"; else body="$(cat "$file")"; fi || die "read failed"
else
  kind=map
  body="$("${cache[@]}" map "${src[@]}")" || die "map failed"
fi

body="${body//$'\r\n'/$'\n'}"
# $(...) on Linux drops only the LFs at the very end, so a CRLF tail leaves a CR and
# LFs before it; trim both so the header describes the body the workflow keeps.
body="${body%$'\r'}"
[[ "$body" =~ $'\n'+$ ]] && body="${body:0:${#body}-${#BASH_REMATCH}}" # one pass, not one copy per LF
n="$(printf '%s' "$body" | wc -c | tr -d ' ')"
[[ "$n" -gt "$MAX_BODY" ]] && kind=too-large
if command -v sha256sum >/dev/null 2>&1; then hash=(sha256sum); else hash=(shasum -a 256); fi
body_sha="$(printf '%s' "$body" | "${hash[@]}" | cut -d' ' -f1)"
printf 'docs-raw: url=%s state=read format=%s validated=%s sha256=%s kind=%s bytes=%s body_sha256=%s\n' \
  "$url" "$format" "$validated" "$sha" "$kind" "$n" "$body_sha"
[[ "$kind" == too-large ]] || printf '%s\n' "$body"
