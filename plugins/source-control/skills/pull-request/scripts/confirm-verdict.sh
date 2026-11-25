#!/usr/bin/env bash
# GENERATED from lib/confirm-verdict.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Exit codes:
#   0  record: stored; show: printed the verdict, that none is recorded or readable, or nothing
#   1  invalid argument, or --dir names no directory
#   2  record: the state cannot be written

# portability-scope: local state under the git directory; no forge call.
set -uo pipefail

usage() {
  cat <<'EOF'
confirm-verdict.sh: record a /verification:confirm or /verification:measure verdict for a head commit, or show it.
Usage:
  confirm-verdict.sh record [--of measure] --head <sha> --verdict <verdict> [options]
  confirm-verdict.sh show   [--of measure] --head <sha> [--dir <checkout>]
  --of <confirm|measure>  the skill whose verdict this is (default confirm)
  --head <sha>            the full 40-character commit the verdict judged
  --verdict <verdict>     confirm: CONFIRMED, 'NEEDS WORK' or 'NOT VERIFIED'; measure: CONFIRMED,
                          MIXED, INCONCLUSIVE, 'NOT CONFIRMED', DEGRADED or 'CANNOT QUANTIFY'
  --missing <item>        confirm: a MISSING plan item (repeatable)
  --partial <item>        confirm: a PARTIAL plan item (repeatable)
  --row <row>             confirm: one criterion, `<criterion> | <files> | <test or check> | <result>` (repeatable)
  --claim <text>          measure: the improvement claim judged
  --dir <checkout>        a checkout whose git directory holds the record (default: .);
                          $CONFIRM_VERDICT_DIR wins over it
Exit codes:
  0  record: stored; show: printed the verdict, that none is recorded or readable, or nothing
  1  invalid argument, or --dir names no directory
  2  record: the state cannot be written
EOF
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

OF=confirm HEAD_SHA="" VERDICT="" CHECKOUT="" items=()
while (($# > 0)); do
  case "$1" in
  --dir)
    (($# >= 2)) && [[ -n "$2" && -z "$CHECKOUT" ]] || die 1 "--dir needs one value and is given once"
    CHECKOUT="$2"
    shift 2
    ;;
  --of | --head | --verdict | --missing | --partial | --row | --claim)
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
CHECKOUT="${CHECKOUT:-.}"
[[ -d "$CHECKOUT" ]] || die 1 "--dir $(printf '%q' "$CHECKOUT") is not a directory"

valid_verdict() {
  case "$OF:$1" in
  confirm:CONFIRMED | 'confirm:NEEDS WORK' | 'confirm:NOT VERIFIED') return 0 ;;
  measure:CONFIRMED | measure:MIXED | measure:INCONCLUSIVE | 'measure:NOT CONFIRMED') return 0 ;;
  measure:DEGRADED | 'measure:CANNOT QUANTIFY') return 0 ;;
  *) return 1 ;;
  esac
}

if [[ "$CMD" == show ]]; then
  [[ -z "$VERDICT" && ${#items[@]} -eq 0 ]] || die 1 "show takes only --of, --head and --dir"
else
  for item in ${items[@]+"${items[@]}"}; do
    case "$OF:$item" in
    confirm:MISSING:* | confirm:PARTIAL:* | confirm:ROW:* | measure:CLAIM:*) ;;
    confirm:*) die 1 "--claim needs --of measure" ;;
    *) die 1 "--of measure takes --claim, not --missing, --partial or --row" ;;
    esac
  done
fi

dir="${CONFIRM_VERDICT_DIR:-}"
if [[ -z "$dir" ]]; then
  if ! common=$(git -C "$CHECKOUT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    [[ "$CMD" == show ]] || die 2 "$(printf '%q' "$CHECKOUT") is not in a git repository, and CONFIRM_VERDICT_DIR is unset"
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
  if ! printf '%s\n' "verdict: $VERDICT" ${items[@]+"${items[@]}"} >"$tmp" || ! mv -f "$tmp" "$file"; then
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
  'confirm:MISSING: '?* | 'confirm:PARTIAL: '?* | 'confirm:ROW: '?* | 'measure:CLAIM: '?*) printf '  %s\n' "$line" ;;
  *) ;;
  esac
done
exit 0
