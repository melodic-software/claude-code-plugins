#!/usr/bin/env bash
# confirm-verdict.sh: record a /verification:confirm verdict for the head commit it judged, and
# show the one recorded for a head.
#
# `record` runs at the end of /verification:confirm and stores its verdict and each MISSING or
# PARTIAL plan item for one head commit. `show` runs in the pull-request `ready` report and prints
# the verdict recorded for that exact head, or says none is. A verdict recorded for another head
# never counts, so a commit after confirm voids it. `show` is advisory: it never refuses, whatever
# the verdict, so it never stops the ready flip.
#
# Usage:
#   confirm-verdict.sh record --head <sha> --verdict CONFIRMED|'NEEDS WORK'|'NOT VERIFIED'
#                             [--missing <item>]... [--partial <item>]...
#   confirm-verdict.sh show   --head <sha>
#
# The record lives under the repository's common git directory (`confirm-verdict/<sha>`), shared
# by every worktree, so a record and a show agree whichever checkout the shell sits in; or under
# $CONFIRM_VERDICT_DIR when set. Its first line is `verdict: <verdict>`; each later line is
# `MISSING: <item>` or `PARTIAL: <item>`, in the order given.
#
# Exit codes:
#   0  record: stored; show: printed the verdict, or that none is recorded or readable
#   1  invalid argument
#   2  record: the state cannot be written

# portability-scope: local state under the git directory; no forge call.
set -uo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  printf 'confirm-verdict: %s\n' "$2" >&2
  exit "$1"
}

(($# > 0)) || die 1 "a subcommand is required (use --help)"
case "$1" in
-h | --help) usage ;;
record | show) CMD="$1" ;;
*) die 1 "unknown subcommand $(printf '%q' "$1") (use --help)" ;;
esac
shift

HEAD_SHA="" VERDICT="" items=()
while (($# > 0)); do
  case "$1" in
  --head | --verdict | --missing | --partial)
    (($# >= 2)) || die 1 "$1 needs a value"
    case "$1" in
    --head) HEAD_SHA="$2" ;;
    --verdict) VERDICT="$2" ;;
    *)
      [[ -n "$2" && "$2" != *[[:cntrl:]]* ]] || die 1 "$1 needs one non-empty line of text"
      label="${1#--}"
      items+=("${label^^}: $2")
      ;;
    esac
    shift 2
    ;;
  *) die 1 "unknown argument $(printf '%q' "$1") (use --help)" ;;
  esac
done
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || die 1 "--head must be a full 40-character commit sha"

if [[ "$CMD" == show ]]; then
  [[ -z "$VERDICT" && ${#items[@]} -eq 0 ]] || die 1 "show takes only --head"
fi

dir="${CONFIRM_VERDICT_DIR:-}"
if [[ -z "$dir" ]]; then
  if ! common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    [[ "$CMD" == show ]] || die 2 "not in a git repository, and CONFIRM_VERDICT_DIR is unset"
    printf 'confirm: no verdict readable for head %s (not in a git repository)\n' "$HEAD_SHA"
    exit 0
  fi
  dir="$common/confirm-verdict"
fi
file="$dir/$HEAD_SHA"

if [[ "$CMD" == record ]]; then
  case "$VERDICT" in
  CONFIRMED | 'NEEDS WORK' | 'NOT VERIFIED') ;;
  *) die 1 "--verdict must be CONFIRMED, 'NEEDS WORK' or 'NOT VERIFIED'" ;;
  esac
  mkdir -p "$dir" || die 2 "cannot create $dir"
  tmp=$(mktemp "$dir/.$HEAD_SHA.XXXXXX") || die 2 "cannot write in $dir"
  if ! {
    printf 'verdict: %s\n' "$VERDICT" && { ((${#items[@]} == 0)) || printf '%s\n' "${items[@]}"; }
  } >"$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    die 2 "cannot write $file"
  fi
  exit 0
fi

if [[ ! -f "$file" ]]; then
  printf 'confirm: no verdict recorded for head %s\n' "$HEAD_SHA"
  exit 0
fi
lines=()
if ! mapfile -t lines <"$file" || [[ "${lines[0]:-}" != 'verdict: '* ]]; then
  printf 'confirm: unreadable verdict record for head %s\n' "$HEAD_SHA"
  exit 0
fi
recorded="${lines[0]#verdict: }"
case "$recorded" in
CONFIRMED | 'NEEDS WORK' | 'NOT VERIFIED') ;;
*)
  printf 'confirm: unreadable verdict record for head %s\n' "$HEAD_SHA"
  exit 0
  ;;
esac
printf 'confirm: %s for head %s\n' "$recorded" "$HEAD_SHA"
for line in "${lines[@]:1}"; do
  case "$line" in
  'MISSING: '?* | 'PARTIAL: '?*) printf '  %s\n' "$line" ;;
  *) ;;
  esac
done
exit 0
