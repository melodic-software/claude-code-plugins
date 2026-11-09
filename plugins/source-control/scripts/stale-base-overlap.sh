#!/usr/bin/env bash
# Answers whether a checkout's HEAD and a base ref changed the same paths since
# their merge-base. Used by skills/pull-request/scripts/push-branch.sh and
# branch-update-signals.sh.
#
#   stale-base-overlap.sh [--paths-only] <checkout> <base-ref>
#
# When the base ref holds scripts/check-stale-base-overlap.sh and --paths-only
# is not given, that copy (with the base's scripts/ beside it) is the rule, run
# as --check <base-ref>: exit 1 is an overlap, 0 is none, anything else is
# unknown. The head's copy and the working tree's are never run. Otherwise the
# paths changed on both sides since the merge-base are compared. A caller passes
# --paths-only for any base it cannot show is the default branch, since the
# author may have pushed such a base unreviewed and the rule is code.
#
# Stdout is one line: `yes`, `no`, or `unknown <reason>`. The rule's own output
# goes to stderr. Exit 0, or 2 for a usage error.
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
if [[ "$mb" == "$tip" ]]; then
  echo no
  exit 0
fi
overlap=$(LC_ALL=C comm -12 <(LC_ALL=C sort -u <<<"$paths_base") <(LC_ALL=C sort -u <<<"$paths_head"))
if [[ -n "${overlap//$'\n'/}" ]]; then echo yes; else echo no; fi
