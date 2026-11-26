#!/usr/bin/env bash
set -uo pipefail

# Under the 30000 characters of Bash output Claude Code reads back by default (BASH_MAX_OUTPUT_LENGTH):
# https://code.claude.com/docs/en/env-vars
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
body="${body%$'\r'}"
[[ "$body" =~ $'\n'+$ ]] && body="${body:0:${#body}-${#BASH_REMATCH}}" # one pass, not one copy per LF
n="$(printf '%s' "$body" | wc -c | tr -d ' ')"
[[ "$n" -gt "$MAX_BODY" ]] && kind=too-large
if command -v sha256sum >/dev/null 2>&1; then hash=(sha256sum); else hash=(shasum -a 256); fi
body_sha="$(printf '%s' "$body" | "${hash[@]}" | cut -d' ' -f1)"
printf 'docs-raw: url=%s state=read format=%s validated=%s sha256=%s kind=%s bytes=%s body_sha256=%s\n' \
  "$url" "$format" "$validated" "$sha" "$kind" "$n" "$body_sha"
[[ "$kind" == too-large ]] || printf '%s\n' "$body"
