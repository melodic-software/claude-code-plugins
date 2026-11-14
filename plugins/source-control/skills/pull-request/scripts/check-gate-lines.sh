#!/usr/bin/env bash
# check-gate-lines.sh — Refuse a PR body rewrite that changes a line a gate reads.
#
# A body refresh (reference/monitor.md §3.3.2 step 5) rewrites only stale
# sections. This compares the lines merge, ready and linkage checks read in the
# current body and the proposed one, as a multiset, so a line changed, added,
# removed or repeated fails. Gate lines, any case, after optional blanks or a
# quote marker where a reader allows one:
#   - `Hold:` and `Draft:` lines, and any "do not merge" / "don't merge" text
#     (check-ready-holds.sh; merge-holds.mjs BODY_HOLD)
#   - a closing keyword with an issue reference, and `Refs:`, `Relates to:` and
#     `No linked issue` / `No related issue` lines (hooks/pr-linkage-validator.sh),
#     or with a full issue URL (.github/scripts/maintenance-tidy-code-upkeep/batch.mjs
#     CLOSING)
#   - hold wording split across lines, one `hold wording across lines:` entry
#     per match: the hold readers test the whole body, where the space between
#     the words may be a line break (merge-holds.mjs BODY_HOLD, check-ready-holds.sh)
#   - `Siblings:` (siblings-line.sh) and `Merge-Risk:` lines
#   - every line of the `## Follow-ups` section, heading included
#     (publish-feedback's entries)
#
# Usage:
#   check-gate-lines.sh <current-body-file> <proposed-body-file>
#
# Exit codes:
#   0  the gate lines match: the edit may post
#   1  they differ: one `removed: <line>` or `added: <line>` per difference on stdout
#   2  usage error, or a file that does not read
set -uo pipefail
export LC_ALL=C

# shellcheck source=../../../hooks/pr-linkage-validator.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../hooks/pr-linkage-validator.sh"

die() {
  printf 'check-gate-lines: %s\n' "$1" >&2
  exit 2
}

(($# == 2)) || die "usage: check-gate-lines.sh <current-body-file> <proposed-body-file>"
for f in "$1" "$2"; do
  [[ -f "$f" && -r "$f" ]] || die "cannot read $(printf '%q' "$f")"
done

CLOSING_URL_ERE='(close[sd]?|fix(es|ed)?|resolve[sd]?):?[[:blank:]]*https?://github\.com/[a-z0-9_.-]+/[a-z0-9_.-]+/issues/[0-9]+'
HOLD_ERE='do(n[^[:space:]]{0,3}t|[[:space:]]+not)[[:space:]]+merge'

# The hold wording in the body in file $1 that spans a line break, its
# whitespace runs collapsed to one space, one per line.
split_holds() {
  local rest match
  rest=$(tr -d '\r' <"$1" | tr '[:upper:]' '[:lower:]') || return 1
  while [[ "$rest" =~ $HOLD_ERE ]]; do
    match=${BASH_REMATCH[0]}
    rest=${rest#*"$match"}
    [[ "$match" == *$'\n'* ]] || continue
    printf 'hold wording across lines: %s\n' "$(printf '%s' "$match" | tr -s '[:space:]' ' ')"
  done
}

# The gate lines of the body in file $1, one per line, sorted.
gate_lines() {
  local line lower in_followups=0
  local lead='^[[:blank:]>]*'
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
      if [[ "$lower" =~ ^##[[:blank:]]+follow-ups[[:blank:]]*$ ]]; then
        in_followups=1
      elif [[ "$lower" =~ ^#{1,2}[[:blank:]] ]]; then
        in_followups=0
      fi
      if ((in_followups)); then
        [[ "$line" =~ [^[:blank:]] ]] || continue
        printf '%s\n' "$line"
      elif [[ "$lower" =~ ${lead}(hold|draft|siblings|merge-risk|refs|relates[[:blank:]]+to): ]] ||
        [[ "$lower" =~ ${lead}no[[:blank:]]+(linked|related)[[:blank:]]+issue ]] ||
        [[ "$lower" =~ $HOLD_ERE ]] ||
        [[ "$lower" =~ $CLOSING_ERE ]] ||
        [[ "$lower" =~ $CLOSING_URL_ERE ]]; then
        printf '%s\n' "$line"
      fi
    done <"$1"
    split_holds "$1"
  } | sort
}

current=$(gate_lines "$1") || die "cannot read $(printf '%q' "$1")"
proposed=$(gate_lines "$2") || die "cannot read $(printf '%q' "$2")"
[[ "$current" == "$proposed" ]] && exit 0
comm -23 <(printf '%s\n' "$current") <(printf '%s\n' "$proposed") | sed '/^$/d; s/^/removed: /'
comm -13 <(printf '%s\n' "$current") <(printf '%s\n' "$proposed") | sed '/^$/d; s/^/added: /'
exit 1
