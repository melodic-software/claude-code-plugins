#!/usr/bin/env bash
set -uo pipefail

RULE=scripts/check-stale-base-overlap.sh

unknown() {
  echo "unknown $1"
  exit 0
}

paths_only=0
if [[ "${1:-}" == --paths-only ]]; then
  paths_only=1
  shift
fi
if [[ $# -ne 2 || -z "$1" || -z "$2" ]]; then
  echo "usage: stale-base-overlap.sh [--paths-only] <checkout> <base-ref>" >&2
  exit 2
fi
wd="$1" ref="$2"
[[ "$ref" != -* ]] || unknown "the base ref '$ref' starts with '-'"

if ((!paths_only)) && git -C "$wd" cat-file -e "$ref:$RULE" 2>/dev/null; then
  tmp=$(mktemp -d) || unknown "no temporary directory for the base's $RULE"
  trap 'rm -rf "$tmp"' EXIT
  git -C "$wd" archive "$ref" -- scripts | tar -x -C "$tmp"
  (cd -- "$wd" && bash "$tmp/$RULE" --check "$ref") >&2
  rc=$?
  case "$rc" in
    0) echo no ;;
    1) echo yes ;;
    *) unknown "the base's $RULE exited $rc" ;;
  esac
  exit 0
fi

if ! mb=$(git -C "$wd" merge-base HEAD "$ref") || ! tip=$(git -C "$wd" rev-parse "$ref^{commit}") ||
  ! paths_base=$(git -C "$wd" diff --name-only --no-renames "$mb" "$tip") ||
  ! paths_head=$(git -C "$wd" diff --name-only --no-renames "$mb" HEAD); then
  unknown "the paths changed since the merge-base of HEAD and $ref could not be read"
fi
if [[ -n "$(LC_ALL=C comm -12 <(LC_ALL=C sort -u <<<"$paths_base") <(LC_ALL=C sort -u <<<"$paths_head"))" ]]; then
  echo yes
else
  echo no
fi
