#!/usr/bin/env bash
# Upstream citation check for the audit skill.
#
# The checklist and references cite settings keys and sentences on official
# docs pages. Those pages move: a key migrates to another page, a sentence is
# reworded, and the row that cited it then points at text that is not there.
# This script reads the manifest of citations (reference/doc-citations.tsv,
# one <page slug><TAB><literal span> per row), fetches each page verbatim over
# the raw-markdown channel, and greps the span in the fetched file. A page that
# lost a span is a failure naming the row; a page that could not be fetched is
# a visible SKIP, never a pass and never a failure, because a truncated or
# absent read supports no claim in either direction.
#
# Pages already fetched this run can be reused: --docs-dir names a directory
# holding <slug>.md files, and a page present there is read from disk instead
# of fetched again. The fixture seam does the same without any network.
#
# Exit codes:
#   0  every fetched page carries every span it is cited for (skips allowed)
#   1  at least one fetched page lacks a cited span
#   2  fatal (manifest missing, curl missing with nothing on disk, bad arguments)
#
# Env overrides (the test seam):
#   SETTINGS_AUDIT_DOCS_FIXTURE_DIR  directory of <slug>.md files; when set no fetch happens

set -uo pipefail

usage() {
  cat <<'EOF'
check-doc-citations.sh — verify the docs pages the audit cites still carry the cited text.

Usage:
  check-doc-citations.sh [--docs-dir <dir>] [--manifest <file>] [--help]

  --docs-dir <dir>   read <slug>.md from <dir> when present, fetch the rest
  --manifest <file>  citation manifest (default: reference/doc-citations.tsv beside this skill)

Exit: 0 all cited spans present on every page that could be read; 1 a span is missing;
      2 fatal.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
if [[ -z "$FIXTURE_DIR" ]] && ! command -v curl >/dev/null 2>&1; then
  if [[ -z "$DOCS_DIR" ]]; then
    echo "ERROR: curl required to fetch pages (or pass --docs-dir with the pages on disk)" >&2
    exit 2
  fi
fi

FETCH_DIR="$(mktemp -d)"
trap 'rm -rf "$FETCH_DIR"' EXIT

# page_file <slug>: echo the path of the page's verbatim markdown, or nothing
# when it cannot be read this run.
declare -A PAGE_STATE=()
page_file() {
  local slug="$1" f
  if [[ -n "$FIXTURE_DIR" ]]; then
    f="$FIXTURE_DIR/$slug.md"
    [[ -s "$f" ]] && printf '%s' "$f"
    return 0
  fi
  if [[ -n "$DOCS_DIR" && -s "$DOCS_DIR/$slug.md" ]]; then
    printf '%s' "$DOCS_DIR/$slug.md"
    return 0
  fi
  f="$FETCH_DIR/$slug.md"
  if [[ ! -s "$f" ]] && command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 60 -o "$f" "https://code.claude.com/docs/en/$slug.md" 2>/dev/null || rm -f "$f"
  fi
  [[ -s "$f" ]] && printf '%s' "$f"
  return 0
}

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
      printf 'SKIP  %s: page could not be read this run; no claim about its rows\n' "$slug"
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
