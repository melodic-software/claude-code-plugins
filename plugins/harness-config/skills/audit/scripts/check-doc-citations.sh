#!/usr/bin/env bash
# Exit codes:
#   0  every fetched page carries every span it is cited for (skips allowed)
#   1  at least one fetched page lacks a cited span
#   2  fatal (manifest missing, a row whose slug is not lower-case `/`-joined
#      segments, the shared fetcher missing or failing, bad arguments)

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

declare -A PAGE_FILE=() PAGE_REASON=()

page_file() {
  if [[ -n "$DOCS_DIR" && -s "$DOCS_DIR/$1.md" ]]; then
    printf '%s' "$DOCS_DIR/$1.md"
  else
    printf '%s' "${PAGE_FILE[$1]:-}"
  fi
}

fetch_pages() {
  local slug state reason
  [[ -f "$FETCH_DOCS" ]] || {
    echo "ERROR: shared fetcher not found: $FETCH_DOCS" >&2
    exit 2
  }
  local fetch_env=(-u FETCH_DOCS_FIXTURE_DIR FETCH_DOCS_CLAUDE_BIN='')
  [[ -z "$FIXTURE_DIR" ]] || fetch_env=(FETCH_DOCS_FIXTURE_DIR="$FIXTURE_DIR" FETCH_DOCS_CLAUDE_BIN='')
  env "${fetch_env[@]}" bash "$FETCH_DOCS" --out "$FETCH_DIR" --manifest "$FETCH_DIR/manifest.json" --cache --max-age 0 --mode search "$@" >/dev/null || {
    echo "ERROR: the shared fetcher failed" >&2
    exit 2
  }
  while IFS=$'\t' read -r slug state reason; do
    reason="${reason%$'\r'}"
    if [[ "$state" == read ]]; then
      PAGE_FILE[$slug]="$FETCH_DIR/$slug.md"
    else
      PAGE_REASON[$slug]="$reason"
    fi
  done < <(jq -r '.pages[] | [.slug, .state, (.reason // "unread")] | @tsv' "$FETCH_DIR/manifest.json")
}

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
while IFS=$'\t' read -r slug span || [[ -n "$slug" ]]; do
  [[ -n "$slug" && "${slug:0:1}" != "#" && -n "$span" ]] || continue
  span="${span%$'\r'}"
  if [[ -z "${PAGE_STATE[$slug]:-}" ]]; then
    PAGE_STATE[$slug]="$(page_file "$slug")"
    if [[ -z "${PAGE_STATE[$slug]}" ]]; then
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
exit $((MISSING > 0))
