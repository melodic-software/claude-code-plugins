#!/usr/bin/env bash
# file-provenance.sh — is this file owned here, or written by a sync from elsewhere?
# A synced copy's fix belongs upstream, since the next sync overwrites it. An
# untracked file is `local`: with no history, nothing proves it is synced.

set -uo pipefail

usage() {
  cat <<'EOF'
file-provenance.sh — classify a file as locally owned or written by a sync.

Usage: file-provenance.sh [--synced] <path>

  <path>     print `synced|local`, the signal (header, commit, none), and the
             upstream (`owner/repo` when the header names one, else unknown),
             tab-separated; exit 0
  --synced   exit 0 when the file is synced, 1 when local; print nothing
  --help     this message

Signals: a `SYNC-MANAGED` marker in the file, or a last commit whose author
contains `standards-sync` or whose subject starts `chore: sync standards`.
EOF
}

quiet=0
target=""
while (($# > 0)); do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --synced) quiet=1 ;;
  -*)
    usage >&2
    exit 2
    ;;
  *) target="$1" ;;
  esac
  shift
done
[[ -n "$target" ]] || {
  usage >&2
  exit 2
}

emit() {
  ((quiet)) && return 0
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

if [[ ! -f "$target" ]]; then
  emit local none unknown
  ((quiet)) && exit 1
  exit 0
fi

upstream=unknown
if grep -q 'SYNC-MANAGED' "$target" 2>/dev/null; then
  found=$(grep -m1 -oE 'Source of truth: *[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$target" 2>/dev/null | sed -E 's/.*: *//')
  [[ -n "$found" ]] && upstream="$found"
  emit synced header "$upstream"
  exit 0
fi

dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd)" || dir=""
if [[ -n "$dir" ]] && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  last=$(git -C "$dir" log -1 --format='%an%n%s' -- "$(basename "$target")" 2>/dev/null | tr -d '\r')
  author="${last%%$'\n'*}"
  subject="${last#*$'\n'}"
  if [[ -n "$last" ]] && { [[ "$author" == *standards-sync* ]] || [[ "$subject" == "chore: sync standards"* ]]; }; then
    emit synced commit "$upstream"
    exit 0
  fi
fi

emit local none unknown
((quiet)) && exit 1
exit 0
