#!/usr/bin/env bash
# confirm-verdict.sh: record a /verification:confirm or /verification:measure verdict for the head
# commit it judged, and show the one recorded for a head.
#
# `record` runs at the end of /verification:confirm and stores its verdict and each MISSING or
# PARTIAL plan item for one head commit; with `--of measure` it runs at the end of a
# /verification:measure compare and stores that verdict and the improvement claim it judged.
# `show` runs in the pull-request `ready` report and prints the verdict recorded for that exact
# head, or for confirm says none is; for measure, a head with no record prints nothing. A verdict
# recorded for another head never counts, so a commit after the run voids it. `show` is advisory:
# it never refuses, whatever the verdict, so it never stops the ready flip.
#
# Usage:
#   confirm-verdict.sh record --head <sha> --verdict CONFIRMED|'NEEDS WORK'|'NOT VERIFIED'
#                             [--missing <item>]... [--partial <item>]...
#   confirm-verdict.sh record --of measure --head <sha>
#                             --verdict CONFIRMED|MIXED|INCONCLUSIVE|'NOT CONFIRMED'|DEGRADED|'CANNOT QUANTIFY'
#                             [--claim <text>]
#   confirm-verdict.sh show   [--of measure] --head <sha>
#
# The record lives under the repository's common git directory (`confirm-verdict/<sha>`, and
# `confirm-verdict/<sha>.measure` for measure), shared by every worktree, so a record and a show
# agree whichever checkout the shell sits in; or under $CONFIRM_VERDICT_DIR when set. Its first
# line is `verdict: <verdict>`; each later line is `MISSING: <item>`, `PARTIAL: <item>` or
# `CLAIM: <text>`, in the order given.
#
# Exit codes:
#   0  record: stored; show: printed the verdict, that none is recorded or readable, or nothing
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

OF=confirm HEAD_SHA="" VERDICT="" items=()
while (($# > 0)); do
  case "$1" in
  --of | --head | --verdict | --missing | --partial | --claim)
    (($# >= 2)) || die 1 "$1 needs a value"
    case "$1" in
    --of) OF="$2" ;;
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
case "$OF" in
confirm | measure) ;;
*) die 1 "--of must be confirm or measure" ;;
esac
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || die 1 "--head must be a full 40-character commit sha"

# valid_verdict <verdict>: whether <verdict> is one of the words the --of skill defines.
valid_verdict() {
  case "$OF:$1" in
  confirm:CONFIRMED | 'confirm:NEEDS WORK' | 'confirm:NOT VERIFIED') return 0 ;;
  measure:CONFIRMED | measure:MIXED | measure:INCONCLUSIVE | 'measure:NOT CONFIRMED') return 0 ;;
  measure:DEGRADED | 'measure:CANNOT QUANTIFY') return 0 ;;
  *) return 1 ;;
  esac
}

if [[ "$CMD" == show ]]; then
  [[ -z "$VERDICT" && ${#items[@]} -eq 0 ]] || die 1 "show takes only --of and --head"
else
  for item in ${items[@]+"${items[@]}"}; do
    case "$OF:$item" in
    confirm:MISSING:* | confirm:PARTIAL:* | measure:CLAIM:*) ;;
    confirm:*) die 1 "--claim needs --of measure" ;;
    *) die 1 "--of measure takes --claim, not --missing or --partial" ;;
    esac
  done
fi

dir="${CONFIRM_VERDICT_DIR:-}"
if [[ -z "$dir" ]]; then
  if ! common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    [[ "$CMD" == show ]] || die 2 "not in a git repository, and CONFIRM_VERDICT_DIR is unset"
    [[ "$OF" == measure ]] ||
      printf 'confirm: no verdict readable for head %s (not in a git repository)\n' "$HEAD_SHA"
    exit 0
  fi
  dir="$common/confirm-verdict"
fi
file="$dir/$HEAD_SHA"
[[ "$OF" == confirm ]] || file="$file.$OF"

if [[ "$CMD" == record ]]; then
  if ! valid_verdict "$VERDICT"; then
    [[ "$OF" == measure ]] &&
      die 1 "--verdict must be CONFIRMED, MIXED, INCONCLUSIVE, 'NOT CONFIRMED', DEGRADED or 'CANNOT QUANTIFY'"
    die 1 "--verdict must be CONFIRMED, 'NEEDS WORK' or 'NOT VERIFIED'"
  fi
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
  [[ "$OF" == measure ]] || printf 'confirm: no verdict recorded for head %s\n' "$HEAD_SHA"
  exit 0
fi
lines=()
if ! mapfile -t lines <"$file" || [[ "${lines[0]:-}" != 'verdict: '* ]] ||
  ! valid_verdict "${lines[0]#verdict: }"; then
  printf '%s: unreadable verdict record for head %s\n' "$OF" "$HEAD_SHA"
  exit 0
fi
recorded="${lines[0]#verdict: }"
if [[ "$recorded" == 'CANNOT QUANTIFY' ]]; then
  printf 'measure: CANNOT QUANTIFY for head %s: no baseline was captured before the change\n' "$HEAD_SHA"
else
  printf '%s: %s for head %s\n' "$OF" "$recorded" "$HEAD_SHA"
fi
for line in "${lines[@]:1}"; do
  case "$OF:$line" in
  'confirm:MISSING: '?* | 'confirm:PARTIAL: '?* | 'measure:CLAIM: '?*) printf '  %s\n' "$line" ;;
  *) ;;
  esac
done
exit 0
