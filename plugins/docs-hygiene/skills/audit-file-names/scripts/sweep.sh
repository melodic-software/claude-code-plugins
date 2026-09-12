#!/usr/bin/env bash
# sweep.sh — find every reference to the files a rename plan would move.
#
# Read-only. For each `old<TAB>new` pair it locates every tracked line naming the
# old file, classifies the SHAPE of each reference, resolves the TIER the citing
# file belongs to, and derives the ACTION the tier's form table allows.
#
# THE FORM LADDER, first match wins:
#   raw-url         a raw.githubusercontent.com URL
#   github-url      any other github.com URL
#   md-link         a markdown link target, `](...name...)`
#   backtick-path   the name inside a code span
#   table-or-key    a table cell or a `key: value` line
#   plain           the basename in running prose
#   bare-stem       the stem with no extension, anchored so a hyphenated sibling
#                   is never matched inside
#
# WHY THE BARE STEM IS ANCHORED AND OFTEN ONLY REVIEWED. A word boundary treats
# a hyphen as a boundary, so `\bCATALOG\b` matches inside `CATALOG-TAXONOMY` and
# rewriting it produces a link to nothing. The pattern here consumes the
# surrounding character instead, and maps are applied longest old name first. A
# stem that is one dictionary-shaped word (no hyphen, no digit) is reported as
# `review` rather than edited, because such a stem also appears as an ordinary
# English word in prose that has nothing to do with the file.
#
# Every single-quoted `${...}` below is a jq or awk program argument, never a
# shell expansion.
# shellcheck disable=SC2016
#
# Usage:
#   sweep.sh --pairs <tsv|-> [--config <json>] [--root <dir>]
#   sweep.sh --help
#
#   --pairs   a file of `old<TAB>new` lines, or `-` for standard input. The
#             OFFENDER rows of inventory.sh, with the tag column removed.
#
# Output, tab-separated:
#   REF   <old>  <file>  <line>  <form>  <tier>  <action>  <excerpt>
#   TIER  <name> <forms> <files matched>
#   SITES <count>
#
# Actions: `edit` (the tier's form table allows this shape), `report` (a site the
# tier freezes), `review` (an ambiguous bare stem, for a human), `skip` (a
# sweep_exclude_sites entry), `regenerate` (a generated file, never text-edited).
#
# Exit: 0 the sweep ran, 2 usage, a missing prerequisite, or an unreadable
#       configuration.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-config.sh"

die() {
  printf 'sweep: %s\n' "$1" >&2
  exit "${2:-2}"
}

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

CONFIG_FILE=""
ROOT=""
PAIRS_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --config)
    shift
    [[ $# -gt 0 ]] || die "--config needs a file"
    CONFIG_FILE="$1"
    ;;
  --root)
    shift
    [[ $# -gt 0 ]] || die "--root needs a directory"
    ROOT="$1"
    ;;
  --pairs)
    shift
    [[ $# -gt 0 ]] || die "--pairs needs a file or -"
    PAIRS_FILE="$1"
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

command -v jq >/dev/null 2>&1 || die "jq is required and is not on PATH"
command -v git >/dev/null 2>&1 || die "git is required and is not on PATH"
[[ -n "$PAIRS_FILE" ]] || die "--pairs is required"

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
  [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "'$ROOT' is not a git repository"

if [[ "$PAIRS_FILE" == "-" ]]; then
  PAIRS="$(cat)"
else
  [[ -r "$PAIRS_FILE" ]] || die "cannot read the pairs file at $PAIRS_FILE"
  PAIRS="$(cat "$PAIRS_FILE")"
fi

if [[ -n "$CONFIG_FILE" ]]; then
  [[ -r "$CONFIG_FILE" ]] || die "cannot read the configuration at $CONFIG_FILE"
  CONFIG="$(jq -e . "$CONFIG_FILE" 2>/dev/null | tr -d '\r')" || die "the configuration at $CONFIG_FILE is not valid JSON"
else
  [[ -f "$RESOLVER" ]] || die "resolver missing at $RESOLVER"
  CONFIG="$(bash "$RESOLVER" resolve --root "$ROOT")" || exit 2
fi

cfg() {
  printf '%s' "$CONFIG" | jq -r "$1" 2>/dev/null | tr -d '\r'
}

# --- the searchable file set -------------------------------------------------

search_pathspec=()
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  search_pathspec+=(":(exclude,glob)$p")
done < <(cfg '.file_names.sweep_exclude[]')

GENERATED=" $(cfg '.file_names.generated[].path' | tr '\n' ' ')"
EXCLUDE_SITES="$(cfg '.file_names.sweep_exclude_sites[]')"

# --- tier resolution ---------------------------------------------------------
#
# A file belongs to the declared tier whose matching pathspec has the most path
# segments, ties going to the earlier entry. A file no tier claims belongs to the
# implicit `current` tier, whose form is `all`, so a tree declaring no tier at
# all still gets every reference repointed.

TIER_MAP=""
tier_count="$(cfg '.file_names.tiers | length')"
i=0
while [[ "$i" -lt "$tier_count" ]]; do
  tname="$(cfg ".file_names.tiers[$i].name")"
  tforms="$(cfg ".file_names.tiers[$i].forms")"
  matched=0
  while IFS= read -r glob; do
    [[ -n "$glob" ]] || continue
    segments="$(printf '%s' "$glob" | tr -cd '/' | wc -c | tr -d ' ')"
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      TIER_MAP="$TIER_MAP$f	$tname	$tforms	$segments	$i
"
      matched=$((matched + 1))
    done < <(git -C "$ROOT" ls-files -- ":(glob)$glob" 2>/dev/null)
  done < <(cfg ".file_names.tiers[$i].paths[]")
  printf 'TIER\t%s\t%s\t%d\n' "$tname" "$tforms" "$matched"
  i=$((i + 1))
done

# Reduce to one winning tier per file.
TIER_WINNER="$(printf '%s' "$TIER_MAP" | awk -F'\t' 'NF==5 {
  f = $1
  if (!(f in best) || $4 > seg[f] || ($4 == seg[f] && $5 < ord[f])) {
    best[f] = $2 "\t" $3; seg[f] = $4; ord[f] = $5
  }
} END { for (f in best) print f "\t" best[f] }')"

tier_of() {
  printf '%s' "$TIER_WINNER" | awk -F'\t' -v f="$1" 'NF==3 && $1 == f {print $2 "\t" $3; found=1; exit}
    END { if (!found) print "current\tall" }'
}

# --- classification ----------------------------------------------------------

# The form patterns are anchored on the SHAPE AROUND the name, not merely on
# both appearing somewhere on the line. One line often carries two forms (a
# markdown link to one file and a code span naming another), and a ladder that
# asked only "does this line contain `](` and the name" would label the second
# one a link and rewrite it in the wrong shape.
RE_RAW=""
RE_GH=""
RE_LINK=""
RE_TICK=""
RE_TABLE=""

set_form_patterns() {
  esc="$(printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"
  RE_RAW="raw\\.githubusercontent\\.com[^ )\"']*$esc"
  RE_GH="github\\.com[^ )\"']*$esc"
  RE_LINK="\\]\\([^)]*$esc"
  RE_TICK="\`[^\`]*$esc"
  RE_TABLE="(^\\|.*$esc|${esc}[[:space:]]*:)"
}

classify_form() {
  # classify_form <line>; the patterns come from set_form_patterns.
  # bash's own =~ keeps this in-process: one subprocess per site would multiply
  # by the thousands of sites a real tree carries.
  if [[ $1 =~ $RE_RAW ]]; then
    printf 'raw-url'
  elif [[ $1 =~ $RE_GH ]]; then
    printf 'github-url'
  elif [[ $1 =~ $RE_LINK ]]; then
    printf 'md-link'
  elif [[ $1 =~ $RE_TICK ]]; then
    printf 'backtick-path'
  elif [[ $1 =~ $RE_TABLE ]]; then
    printf 'table-or-key'
  else
    printf 'plain'
  fi
}

action_for() {
  # action_for <forms> <form>
  case "$1" in
  all) printf 'edit' ;;
  none) printf 'report' ;;
  links-and-paths)
    case "$2" in
    md-link | backtick-path | raw-url | github-url) printf 'edit' ;;
    *) printf 'report' ;;
    esac
    ;;
  *) printf 'report' ;;
  esac
}

is_excluded_site() {
  # is_excluded_site <file> <line-text>
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    efile="${entry%%:*}"
    eliteral="${entry#*:}"
    [[ "$efile" == "$1" ]] || continue
    case "$2" in
    *"$eliteral"*) return 0 ;;
    *) ;;
    esac
  done <<EOF
$EXCLUDE_SITES
EOF
  return 1
}

trim() {
  printf '%s' "$1" | tr '\t' ' ' | cut -c1-160
}

# --- the sweep ---------------------------------------------------------------
#
# Pairs are swept longest old basename first, so a map for `CATALOG` can never
# consume a site that belongs to `CATALOG-TAXONOMY`.

sites=0
sorted_pairs="$(printf '%s' "$PAIRS" | awk -F'\t' 'NF>=2 {print length($1) "\t" $0}' | sort -rn | cut -f2-)"

# The new name is read and discarded: the sweep locates sites by the OLD name,
# and the realign is what applies the new one.
while IFS="$(printf '\t')" read -r old _new; do
  [[ -n "$old" ]] || continue
  base="${old##*/}"
  set_form_patterns "$base"
  stem="${base%.*}"
  seen=""

  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    text="${rest#*:}"
    seen="$seen$file:$lineno
"
    form="$(classify_form "$text")"
    tinfo="$(tier_of "$file")"
    tname="${tinfo%%	*}"
    tforms="${tinfo#*	}"
    action="$(action_for "$tforms" "$form")"
    case "$GENERATED" in
    *" $file "*) action='regenerate' ;;
    *) ;;
    esac
    is_excluded_site "$file" "$text" && action='skip'
    printf 'REF\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$old" "$file" "$lineno" "$form" "$tname" "$action" "$(trim "$text")"
    sites=$((sites + 1))
  done < <(git -C "$ROOT" grep -n -F -- "$base" "${search_pathspec[@]+"${search_pathspec[@]}"}" 2>/dev/null)

  # Bare stems. A line the basename pass already reported is still eligible: one
  # line can carry BOTH forms, and the common shape is a markdown link whose
  # LABEL is the old name and whose target is the old path,
  # `[`PLUGIN-PHILOSOPHY`](../plugin-philosophy.md)`. Reporting only the first
  # match leaves the label reading the old name after the rename, which is a
  # current-tier site the rule says must change.
  #
  # The test is exact rather than a re-scan: remove every occurrence of the
  # basename from the line and ask whether the stem still stands on its own in
  # what is left. A line whose only stem occurrences ARE the basename adds
  # nothing and is skipped, as before.
  stem_pattern="(^|[^A-Za-z0-9_-])$stem([^A-Za-z0-9_-]|\$)"
  stem_outside_basename() {
    residue="${1//"$base"/}"
    [[ "$residue" =~ $stem_pattern ]]
  }
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    text="${rest#*:}"
    case "
$seen" in
    *"
$file:$lineno
"*) stem_outside_basename "$text" || continue ;;
    *) ;;
    esac
    tinfo="$(tier_of "$file")"
    tname="${tinfo%%	*}"
    tforms="${tinfo#*	}"
    action="$(action_for "$tforms" bare-stem)"
    # A stem that is one plain word is also an ordinary English word, so it is
    # never edited on the strength of a text match alone.
    case "$stem" in
    *-* | *[0-9]*) ;;
    *) [[ "$action" == "edit" ]] && action='review' ;;
    esac
    case "$GENERATED" in
    *" $file "*) action='regenerate' ;;
    *) ;;
    esac
    is_excluded_site "$file" "$text" && action='skip'
    printf 'REF\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$old" "$file" "$lineno" "bare-stem" "$tname" "$action" "$(trim "$text")"
    sites=$((sites + 1))
  done < <(git -C "$ROOT" grep -nE -- "$stem_pattern" "${search_pathspec[@]+"${search_pathspec[@]}"}" 2>/dev/null)
done <<EOF
$sorted_pairs
EOF

printf 'SITES\t%d\n' "$sites"
exit 0
