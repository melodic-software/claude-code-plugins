#!/usr/bin/env bash
# fetch-changelog.sh: the one place that decides where the Claude Code changelog is read from.
#
# Usage:
#   fetch-changelog.sh --out <dir>     read the changelog to <dir>/changelog.md
#   fetch-changelog.sh --check <file>  exit 0 when the file's first heading is a changelog's
#
# Sources, first read wins:
#   1. repo: CHANGELOG.md in anthropics/claude-code, by raw.githubusercontent.com (no GitHub
#      REST call), first heading `# Changelog`. Upstream commits it before the release is
#      published; the docs page below has lagged it by an hour or more.
#   2. docs: the `changelog` docs page, raw markdown, first heading `# Claude Code changelog`.
# Both go through fetch-docs.sh beside this script with --cache --max-age 0, so the server is
# always asked and a failed fetch is unread, never a stale cached copy. A body whose first
# heading is not its source's is unread (a moved file or retired slug can answer 200 with
# other bytes). changelog-releases.sh parses either source's release markup.
#
# Output (--out): on a read, one line `changelog: <url>` on stdout, exit 0. When neither
# source reads, `unread: repo: <reason>; docs: <reason>` on stdout, exit 1.
# Exit: 0 read or check passed; 1 unread or check failed; 3 invalid argument.
# FETCH_DOCS_FIXTURE_DIR and DOCS_CACHE_DIR reach fetch-docs.sh unchanged (its test seam).

set -uo pipefail

REPO_URL="https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
REPO_HEADING="# Changelog"
DOCS_HEADING="# Claude Code changelog"

first_heading() { grep -m1 -E '^# ' "$1" 2>/dev/null | tr -d '\r'; }

case "${1:-}" in
--check)
  [[ $# -eq 2 && -r "$2" ]] || {
    echo "usage: fetch-changelog.sh --check <file>" >&2
    exit 3
  }
  h="$(first_heading "$2")"
  [[ "$h" == "$REPO_HEADING" || "$h" == "$DOCS_HEADING" ]]
  exit
  ;;
--out)
  [[ $# -eq 2 && -n "$2" ]] || {
    echo "usage: fetch-changelog.sh --out <dir>" >&2
    exit 3
  }
  out="$2"
  ;;
*)
  echo "usage: fetch-changelog.sh --out <dir> | --check <file>" >&2
  exit 3
  ;;
esac

command -v jq >/dev/null 2>&1 || {
  echo "unread: jq is not installed"
  exit 1
}
mkdir -p "$out" || exit 3
fetcher="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fetch-docs.sh"

# try <name> <heading> <fetch-docs args...>: read one source into $out/changelog.md.
reasons=""
try() {
  local name="$1" heading="$2" work="$out/.$1" file reason
  shift 2
  rm -rf "${work:?}"
  # No claude_version is read from the manifest, so the fetcher runs no claude.
  FETCH_DOCS_CLAUDE_BIN='' bash "$fetcher" --out "$work" --cache --max-age 0 "$@" >/dev/null 2>&1
  if [[ "$(jq -r '.pages[0].state' "$work/manifest.json" 2>/dev/null)" == read ]]; then
    file="$(jq -r '.pages[0].file' "$work/manifest.json")"
    if [[ "$(first_heading "$file")" == "$heading" ]] && cp "$file" "$out/changelog.md"; then
      printf 'changelog: %s\n' "$(jq -r '.pages[0].url' "$work/manifest.json")"
      rm -rf "${work:?}"
      return 0
    fi
    reason="first heading: $(first_heading "$file")"
  else
    reason="$(jq -r '.pages[0].reason // empty' "$work/manifest.json" 2>/dev/null)"
  fi
  rm -rf "${work:?}"
  reasons+="${reasons:+; }$name: ${reason:-no manifest}"
  return 1
}

try repo "$REPO_HEADING" --profile generic "$REPO_URL" && exit 0
try docs "$DOCS_HEADING" changelog && exit 0
printf 'unread: %s\n' "$reasons"
exit 1
