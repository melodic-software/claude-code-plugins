#!/usr/bin/env bash
# Upstream citation check for the audit skill.
#
# The checklist and references cite settings keys and sentences on official
# docs pages. Those pages move: a key migrates to another page, a sentence is
# reworded, and the row that cited it then points at text that is not there.
# This script reads the manifest of citations (reference/doc-citations.tsv,
# one <page slug><TAB><literal span> per row), has the plugin's shared fetcher
# (scripts/fetch-docs.sh) read each page verbatim, and greps the span in the
# fetched file. A page that lost a span is a failure naming the row; a page the
# fetcher reports unread (including a slug the docs index does not list) is a
# visible SKIP with the reason, never a pass and never a failure, because a
# truncated, foreign or absent read supports no claim in either direction.
#
# Pages already fetched this run can be reused: --docs-dir names a directory
# holding <slug>.md files, and a page present there is read from disk instead
# of fetched again. The fixture seam does the same without any network.
#
# Exit codes:
#   0  every fetched page carries every span it is cited for (skips allowed)
#   1  at least one fetched page lacks a cited span
#   2  fatal (manifest missing, a row whose slug is not lower-case `/`-joined
#      segments, the shared fetcher missing or failing, bad arguments)
#
# Env overrides (the test seam):
#   SETTINGS_AUDIT_DOCS_FIXTURE_DIR  directory of llms.txt and <slug>.md files; when set no fetch happens
#   CLAUDE_PLUGIN_ROOT               plugin root holding scripts/fetch-docs.sh

set -uo pipefail

usage() {
  cat <<'EOF'
check-doc-citations.sh — verify the docs pages the audit cites still carry the cited text.

Usage:
  check-doc-citations.sh [--docs-dir <dir>] [--manifest <file>] [--help]

  --docs-dir <dir>   read <slug>.md from <dir> when present, fetch the rest through the docs index
  --manifest <file>  citation manifest (default: reference/doc-citations.tsv beside this skill)

Exit: 0 all cited spans present on every page that could be read; 1 a span is missing;
      2 fatal.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
FETCH_DOCS="$PLUGIN_ROOT/scripts/fetch-docs.sh"
MANIFEST="$SCRIPT_DIR/../reference/doc-citations.tsv"
DOCS_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --docs-dir)
    DOCS_DIR="${2:-}"
    shift 2
    ;;
  --manifest)
    MANIFEST="${2:-}"
    shift 2
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 2
fi

FIXTURE_DIR="${SETTINGS_AUDIT_DOCS_FIXTURE_DIR:-}"
[[ -z "$FIXTURE_DIR" ]] || DOCS_DIR=""

FETCH_DIR="$(mktemp -d)"
trap 'rm -rf "$FETCH_DIR"' EXIT

# PAGE_FILE[slug] is the verbatim markdown of a page the fetcher read;
# PAGE_REASON[slug] is why it did not.
declare -A PAGE_FILE=() PAGE_REASON=()

# page_file <slug>: echo the path of the page's verbatim markdown, or nothing
# when it cannot be read this run.
page_file() {
  if [[ -n "$DOCS_DIR" && -s "$DOCS_DIR/$1.md" ]]; then
    printf '%s' "$DOCS_DIR/$1.md"
  else
    printf '%s' "${PAGE_FILE[$1]:-}"
  fi
}

# fetch_pages <slug>...: one fetcher call for every page not already on disk.
# The fetcher resolves each slug through the docs index, so a page the index
# does not list comes back unread without a request for it.
fetch_pages() {
  local slug state reason
  [[ -f "$FETCH_DOCS" ]] || {
    echo "ERROR: shared fetcher not found: $FETCH_DOCS" >&2
    exit 2
  }
  local fetch_env=(-u SETTINGS_AUDIT_ENGINE_DOCS_FIXTURE_DIR)
  [[ -z "$FIXTURE_DIR" ]] || fetch_env=(SETTINGS_AUDIT_ENGINE_DOCS_FIXTURE_DIR="$FIXTURE_DIR")
  env "${fetch_env[@]}" bash "$FETCH_DOCS" --out "$FETCH_DIR" --manifest "$FETCH_DIR/manifest.json" --mode search "$@" >/dev/null || {
    echo "ERROR: the shared fetcher failed" >&2
    exit 2
  }
  while IFS=$'\t' read -r slug state reason; do
    if [[ "$state" == read ]]; then
      PAGE_FILE[$slug]="$FETCH_DIR/$slug.md"
    else
      PAGE_REASON[$slug]="$reason"
    fi
  done < <(jq -r '.pages[] | [.slug, .state, (.reason // "unread")] | @tsv' "$FETCH_DIR/manifest.json")
}

# Every slug becomes a path under the fetch, docs and fixture directories, so
# the whole manifest is checked before any page is read: a slug is lower-case
# segments joined by `/`, never `.`, `..` or a leading `/`.
# The C locale keeps `a-z` an ASCII range.
slug_ok() {
  local LC_ALL=C re='^[a-z0-9_-]+(/[a-z0-9_-]+)*$'
  [[ "$1" =~ $re ]]
}
row=0
NEED=()
declare -A NEED_SEEN=()
while IFS=$'\t' read -r slug span || [[ -n "$slug" ]]; do
  row=$((row + 1))
  [[ -n "$slug" && "${slug:0:1}" != "#" && -n "$span" ]] || continue
  if ! slug_ok "$slug"; then
    printf 'ERROR: manifest row %d has an invalid page slug: %s\n' "$row" "${slug//[[:cntrl:]]/?}" >&2
    exit 2
  fi
  [[ -z "${NEED_SEEN[$slug]:-}" ]] || continue
  NEED_SEEN[$slug]=1
  [[ -n "$DOCS_DIR" && -s "$DOCS_DIR/$slug.md" ]] || NEED+=("$slug")
done <"$MANIFEST"
[[ ${#NEED[@]} -eq 0 ]] || fetch_pages "${NEED[@]}"

declare -A PAGE_STATE=()

MISSING=0
SKIPPED=0
CHECKED=0
# `|| [[ -n "$slug" ]]` keeps a final row that has no trailing newline: read
# returns nonzero at EOF even when it filled the variables.
while IFS=$'\t' read -r slug span || [[ -n "$slug" ]]; do
  [[ -n "$slug" && "${slug:0:1}" != "#" && -n "$span" ]] || continue
  span="${span%$'\r'}"
  if [[ -z "${PAGE_STATE[$slug]:-}" ]]; then
    pf="$(page_file "$slug")"
    if [[ -n "$pf" ]]; then
      PAGE_STATE[$slug]="$pf"
    else
      PAGE_STATE[$slug]="SKIP"
      printf 'SKIP  %s: page could not be read this run (%s); no claim about its rows\n' "$slug" "${PAGE_REASON[$slug]:-unread}"
    fi
  fi
  pf="${PAGE_STATE[$slug]}"
  if [[ "$pf" == "SKIP" ]]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  CHECKED=$((CHECKED + 1))
  if grep -qF -- "$span" "$pf"; then
    printf 'OK    %s: %s\n' "$slug" "$span"
  else
    printf 'MISS  %s: %s\n' "$slug" "$span"
    MISSING=$((MISSING + 1))
  fi
done <"$MANIFEST"

printf '\nChecked %d citation(s), %d missing, %d skipped (page unreadable).\n' "$CHECKED" "$MISSING" "$SKIPPED"
[[ $MISSING -eq 0 ]] && exit 0
exit 1
