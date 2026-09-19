#!/usr/bin/env bash
# emit-findings.sh — compose the rename plan the realign skill consumes.
#
# Takes the inventory and the sweep and writes one findings artifact. It
# adjudicates nothing: the form, the tier, and the action on every site come
# from the sweep, and the offenders come from the inventory.
#
# IDS ARE DERIVED FROM THE OLD PATH, never from rank. An id that shifted when a
# re-audit reordered the plan would make an operator's "apply FN-005" name a
# different file than the one they read, and a record whose id moved carries no
# decision forward. Presentation order is still site count, most-cited first.
#
# A RE-AUDIT MERGES. When the target exists and its branch matches, every record
# keeps the status it had: a decision the operator already made is never
# re-proposed, and a finding whose offender is gone is dropped rather than left
# behind. `--replace` starts a fresh artifact and says so.
#
# A COLLISION REFUSES THE WHOLE PLAN. Two paths differing only by case cannot
# coexist on a case-insensitive checkout, so a plan containing one is not a plan
# to review. Nothing is written.
#
# Usage:
#   emit-findings.sh --inventory <tsv> --sweep <tsv> --out <path>
#                    [--root <dir>] [--config-path <text>] [--replace]
#   emit-findings.sh --help
#
# Every single-quoted backtick below is literal markdown in the artifact body,
# never a shell expansion.
# shellcheck disable=SC2016
#
# Exit: 0 written, 1 a case collision (nothing written, the pair named on
#       stderr), 2 usage or an unreadable input, 3 the inputs carry no records
#       at all (refusing beats composing from garbage).
set -uo pipefail

die() {
  printf 'emit-findings: %s\n' "$1" >&2
  exit "${2:-2}"
}

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

INVENTORY=""
SWEEP=""
OUT=""
ROOT=""
CONFIG_PATH="resolved"
REPLACE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --inventory)
    shift
    [[ $# -gt 0 ]] || die "--inventory needs a file"
    INVENTORY="$1"
    ;;
  --sweep)
    shift
    [[ $# -gt 0 ]] || die "--sweep needs a file"
    SWEEP="$1"
    ;;
  --out)
    shift
    [[ $# -gt 0 ]] || die "--out needs a path"
    OUT="$1"
    ;;
  --root)
    shift
    [[ $# -gt 0 ]] || die "--root needs a directory"
    ROOT="$1"
    ;;
  --config-path)
    shift
    [[ $# -gt 0 ]] || die "--config-path needs a value"
    CONFIG_PATH="$1"
    ;;
  --replace)
    REPLACE=1
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument '$1'"
    ;;
  esac
  shift
done

[[ -n "$INVENTORY" ]] || die "--inventory is required"
[[ -n "$SWEEP" ]] || die "--sweep is required"
[[ -n "$OUT" ]] || die "--out is required"
[[ -r "$INVENTORY" ]] || die "cannot read the inventory at $INVENTORY"
[[ -r "$SWEEP" ]] || die "cannot read the sweep at $SWEEP"
command -v git >/dev/null 2>&1 || die "git is required and is not on PATH"

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
  [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"

records="$(grep -cE '^(OFFENDER|COLLISION|EXEMPT|SCANNED)	' "$INVENTORY" 2>/dev/null || true)"
[[ "${records:-0}" -gt 0 ]] || die "the inventory carries no records; this is not inventory.sh output" 3

# --- a collision refuses the whole plan --------------------------------------

collisions="$(grep -E '^COLLISION	' "$INVENTORY" 2>/dev/null || true)"
if [[ -n "$collisions" ]]; then
  printf 'emit-findings: the plan would create a case-only path collision; nothing written.\n' >&2
  printf '%s\n' "$collisions" | sed 's/^COLLISION\t/  /' >&2
  printf 'emit-findings: a case-insensitive checkout writes the second file over the first. Resolve the pair, then re-audit.\n' >&2
  exit 1
fi

# --- context -----------------------------------------------------------------

BRANCH="$(git -C "$ROOT" branch --show-current 2>/dev/null)"
if [[ -z "$BRANCH" ]]; then
  short="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  BRANCH="detached-$short"
fi
HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
NOW="$(date -u +%Y%m%dT%H%M%SZ)"
SCANNED="$(awk -F'\t' '$1=="SCANNED" {print $2; exit}' "$INVENTORY")"
ROOTS="$(awk -F'\t' '$1=="SCANNED" {print $3; exit}' "$INVENTORY")"

# --- statuses carried forward ------------------------------------------------

CARRIED=""
if [[ -f "$OUT" && "$REPLACE" -eq 0 ]]; then
  prior_branch="$(awk -F': ' '/^branch: /{print $2; exit}' "$OUT")"
  if [[ -n "$prior_branch" && "$prior_branch" != "$BRANCH" ]]; then
    die "the artifact at $OUT was written on branch '$prior_branch', this checkout is on '$BRANCH'; re-audit or pass --replace"
  fi
  CARRIED="$(awk '
    /^### FN-/ { id = $2 }
    /^- \*\*Status:\*\* / { if (id != "") { print id "\t" $3; id = "" } }
  ' "$OUT")"
fi

status_of() {
  s="$(printf '%s' "$CARRIED" | awk -F'\t' -v i="$1" '$1 == i {print $2; exit}')"
  [[ -n "$s" ]] || s="pending"
  printf '%s' "$s"
}

# --- the records -------------------------------------------------------------

offenders="$(awk -F'\t' '$1=="OFFENDER" {print $2 "\t" $3}' "$INVENTORY")"
finding_count="$(printf '%s' "$offenders" | grep -c . || true)"

body=""
# Most-cited first: the presentation order, never the id.
ranked="$(
  while IFS="$(printf '\t')" read -r old new; do
    [[ -n "$old" ]] || continue
    n="$(awk -F'\t' -v o="$old" '$1=="REF" && $2==o' "$SWEEP" | grep -c . || true)"
    printf '%s\t%s\t%s\n' "$n" "$old" "$new"
  done <<EOF
$offenders
EOF
)"
ranked="$(printf '%s' "$ranked" | sort -rn -k1,1)"

while IFS="$(printf '\t')" read -r nsites old new; do
  [[ -n "$old" ]] || continue
  id="FN-$(printf '%s' "$old" | git hash-object --stdin | cut -c1-8)"
  status="$(status_of "$id")"
  files="$(awk -F'\t' -v o="$old" '$1=="REF" && $2==o {print $3}' "$SWEEP" | sort -u | grep -c . || true)"
  by_tier="$(awk -F'\t' -v o="$old" '$1=="REF" && $2==o {print $6 " " $7}' "$SWEEP" |
    sort | uniq -c | awk '{printf "%s %s (%s), ", $1, $2, $3}' | sed 's/, $//')"
  [[ -n "$by_tier" ]] || by_tier="no site found"
  gen="$(awk -F'\t' -v o="$old" '$1=="REF" && $2==o && $7=="regenerate" {print $3}' "$SWEEP" | sort -u | tr '\n' ' ')"
  [[ -n "${gen// /}" ]] || gen="none"
  review="$(awk -F'\t' -v o="$old" '$1=="REF" && $2==o && $7=="review"' "$SWEEP" | grep -c . || true)"

  body="$body### $id \`$old\` to \`$new\`

- **Status:** $status
- **Collision:** none
- **References:** $nsites site(s) in $files file(s)
- **By tier:** $by_tier
- **Needs a human:** $review site(s) marked review
- **Generated touched:** $gen
- **Sites:**

| file | line | form | tier | action | excerpt |
|---|---|---|---|---|---|
$(awk -F'\t' -v o="$old" '$1=="REF" && $2==o {
    gsub(/\|/, "\\|", $8)
    print "| `" $3 "` | " $4 " | " $5 " | " $6 " | " $7 " | " $8 " |"
  }' "$SWEEP")

"
done <<EOF
$ranked
EOF

# --- write -------------------------------------------------------------------

mkdir -p "$(dirname "$OUT")" || die "cannot create $(dirname "$OUT")"
tmp="$OUT.tmp.$$"
{
  printf -- '---\n'
  printf 'type: docs-hygiene-file-name-findings\n'
  printf 'schema: 1\n'
  printf 'date: %s\n' "$NOW"
  printf 'branch: %s\n' "$BRANCH"
  printf 'head: %s\n' "$HEAD_SHA"
  printf 'config: %s\n' "$CONFIG_PATH"
  printf 'roots: %s\n' "${ROOTS:-unknown}"
  printf 'files_scanned: %s\n' "${SCANNED:-0}"
  printf 'findings: %s\n' "${finding_count:-0}"
  printf 'collisions: 0\n'
  printf -- '---\n\n'
  printf '# File-name rename plan\n\n'
  printf 'One record per file this tree would rename. `head` is recorded for the\n'
  printf 'evidence trail and is never checked: a consumer commits between accepted\n'
  printf 'renames. What a realign checks per record is that the old path is still in\n'
  printf 'the index and that each site still carries the old name.\n\n'
  printf 'Statuses move `pending` to `accepted`, `applying`, `applied`, `declined`, or\n'
  printf '`blocked`. Only the realign writes a forward move. A re-audit merges into\n'
  printf 'this file by id and never resurrects a decision.\n\n'
  printf '%s' "$body"
} >"$tmp" || {
  rm -f "$tmp"
  die "cannot compose the artifact"
}

if ! cat "$tmp" >"$OUT"; then
  rm -f "$tmp"
  die "cannot write $OUT"
fi
rm -f "$tmp"

printf 'wrote %s (%s finding(s), %s file(s) scanned)\n' "$OUT" "${finding_count:-0}" "${SCANNED:-0}"
exit 0
