#!/usr/bin/env bash
# Flag unstamped restatements of upstream-owned skill-frontmatter facts.
#
#   detect-restated-facts.sh [files...] [--paths-file F] [--show-config]
#
# Reasoning-free. The catalog below is a fixed list of tokens the skills
# frontmatter reference owns. A line matches or it does not. Clearance is the
# same kind of check: a pointer URL in the window, or an ISO date plus a
# recheck-trigger phrase plus a basis URL. Whether the prose is wise, current,
# or a copy is not decided here.
#
# The copy lane stays lexical. SKILL.md states that a paraphrase can never be
# fingerprint-confirmed. This script is the other lane #3525 asks for, aimed at
# the #3524 census (bare restatements of the listing cap and the listing-budget
# constants). Findings are report-only. emit-findings.sh relays them and keeps
# them off the fix path.
#
# Catalog record, upstream-drift shape, fetched 2026-09-28 from
# https://code.claude.com/docs/en/skills#frontmatter-reference :
#   Claim: the combined description and when_to_use text is truncated at 1,536
#   characters; the listing budget is skillListingBudgetFraction; the per-entry
#   cap is skillListingMaxDescChars.
#   Basis: that frontmatter reference (the page also names the budget fraction
#   and the max-desc setting in the listing-budget section).
#   As of: 2026-09-28.
#   Recheck trigger: that page moves either default.
#
# Exit: 0 on a clean run (with findings or none), 2 on usage or input error.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

FILES=()
PATHS_FILE=""
SHOW_CONFIG=0

usage() {
  cat <<'EOF'
detect-restated-facts.sh — flag unstamped restatements of frontmatter facts.

Usage:
  detect-restated-facts.sh [files...] [--paths-file F] [--show-config]

  files...        markdown to check (default: tracked markdown in this repo)
  --paths-file F  read the file list from F, one path per line
  --show-config   print the catalog record, then exit

Output: JSON on stdout — {catalog, findings, cleared, declined, counts}.
Diagnostics go to stderr.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file)
    require_opt_value "detect-restated-facts.sh" "$@"
    PATHS_FILE="$2"
    shift 2
    ;;
  --show-config)
    SHOW_CONFIG=1
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  -*)
    echo "detect-restated-facts.sh: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  *)
    FILES+=("$1")
    shift
    ;;
  esac
done

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  echo "Catalog: skill-frontmatter listing cap and budget constants"
  echo "Basis: https://code.claude.com/docs/en/skills#frontmatter-reference"
  echo "As of: 2026-09-28"
  echo "Recheck trigger: that page moves the 1,536 cap or skillListingBudgetFraction or skillListingMaxDescChars"
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -n "$PATHS_FILE" ]]; then
  if [[ ! -r "$PATHS_FILE" ]]; then
    echo "detect-restated-facts.sh: cannot read --paths-file: $PATHS_FILE" >&2
    exit 2
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && FILES+=("$line")
  done <"$PATHS_FILE"
fi

if [[ "${#FILES[@]}" -eq 0 ]]; then
  if [[ -z "$REPO_ROOT" ]]; then
    echo "detect-restated-facts.sh: no files and no git repository" >&2
    exit 2
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && FILES+=("$REPO_ROOT/$line")
  done < <(git -C "$REPO_ROOT" -c core.quotePath=false ls-files -- '*.md' 2>/dev/null)
fi

for f in ${FILES[@]+"${FILES[@]}"}; do
  if [[ ! -f "$f" ]]; then
    echo "detect-restated-facts.sh: not a readable file: $f" >&2
    exit 2
  fi
done

if [[ "${#FILES[@]}" -eq 0 ]]; then
  echo "detect-restated-facts.sh: no files to check" >&2
  exit 2
fi

# awk writes TSV: F<TAB>fact<TAB>file<TAB>line<TAB>excerpt
#                 C<TAB>reason
#                 D<TAB>reason
RECORDS="$(
  awk '
function listing_context(s, low) {
  low = tolower(s)
  if (index(low, "listing")) return 1
  if (index(low, "description")) return 1
  if (index(low, "when_to_use")) return 1
  if (index(low, "frontmatter")) return 1
  if (index(low, "truncat")) return 1 # stem matches truncate and truncation # spellchecker:disable-line
  if (index(low, "per-skill")) return 1
  if (index(low, "per-entry")) return 1
  if (index(low, "-char")) return 1
  if (index(low, "character")) return 1
  return 0
}
function has_1536(s, t, before, after) {
  if (index(s, "1,536")) return 1
  t = s
  while (match(t, /1536/)) {
    before = (RSTART > 1) ? substr(t, RSTART - 1, 1) : ""
    after = substr(t, RSTART + 4, 1)
    if (before !~ /[0-9]/ && after !~ /[0-9]/) return 1
    t = substr(t, RSTART + 4)
  }
  return 0
}
function tsv(s) {
  gsub(/\t/, " ", s)
  gsub(/\r/, "", s)
  gsub(/\n/, " ", s)
  if (length(s) > 180) s = substr(s, 1, 180)
  return s
}
function window_clears(nlines, line_no,    i, lo, hi, w, low, has_pointer, has_date, has_trigger, has_basis) {
  lo = line_no - 12
  if (lo < 1) lo = 1
  hi = line_no + 8
  if (hi > nlines) hi = nlines
  has_pointer = 0
  has_date = 0
  has_trigger = 0
  has_basis = 0
  for (i = lo; i <= hi; i++) {
    w = line[i]
    if (index(w, "code.claude.com/docs/en/skills") || index(w, "code.claude.com/docs/en/settings")) has_pointer = 1
    if (w ~ /20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) has_date = 1
    low = tolower(w)
    if (index(low, "recheck trigger")) has_trigger = 1
    if (index(w, "https://") || index(w, "http://")) has_basis = 1
  }
  if (has_pointer) return 1
  if (has_date && has_trigger && has_basis) return 1
  return 0
}
function consider(fact, nlines, lineno, text) {
  if (window_clears(nlines, lineno)) {
    print "C\t" fact
  } else {
    print "F\t" fact "\t" file "\t" lineno "\t" tsv(text)
  }
}
# A bare setting name is how a sentence points at the knob. The census defect
# is restating the upstream fact: the default, or the 1,536 cap, on the line.
function restates_cap_name(s) {
  return index(s, "skillListingMaxDescChars") && (has_1536(s) || index(tolower(s), "default"))
}
function restates_budget_name(s) {
  return index(s, "skillListingBudgetFraction") && (index(s, "0.01") || index(s, "1%") || index(tolower(s), "default"))
}
function is_candidate(s) {
  return restates_cap_name(s) || restates_budget_name(s) || (has_1536(s) && listing_context(s))
}
BEGIN { back = 12 }
FNR == 1 {
  if (NR > 1) scan_file()
  file = FILENAME
  n = 0
  in_fm = 0
  fm_done = 0
  in_fence = 0
  base = FILENAME
  sub(/^.*\//, "", base)
  is_changelog = (base == "CHANGELOG.md")
}
{
  n++
  line[n] = $0
  fm[n] = 0
  fence[n] = 0
  if (!fm_done) {
    if (FNR == 1 && $0 == "---") { in_fm = 1; fm[n] = 1; next }
    if (in_fm) {
      fm[n] = 1
      if ($0 == "---") { in_fm = 0; fm_done = 1 }
      next
    }
    fm_done = 1
  }
  if ($0 ~ /^```/) { in_fence = !in_fence; fence[n] = 1; next }
  if (in_fence) fence[n] = 1
}
END { scan_file() }
function scan_file(    i, s) {
  for (i = 1; i <= n; i++) {
    s = line[i]
    if (fm[i]) {
      if (is_candidate(s)) print "D\tfrontmatter"
      continue
    }
    if (fence[i]) {
      if (is_candidate(s)) print "D\tfenced"
      continue
    }
    if (is_changelog) {
      if (is_candidate(s)) print "D\tchangelog"
      continue
    }
    if (restates_cap_name(s)) consider("listing-max-desc-chars", n, i, s)
    if (restates_budget_name(s)) consider("listing-budget-fraction", n, i, s)
    if (has_1536(s) && listing_context(s)) consider("listing-entry-cap-1536", n, i, s)
  }
  delete line
  delete fm
  delete fence
}
' ${FILES[@]+"${FILES[@]}"}
)"

RULE="attribution/audit/rule-restated-upstream-fact"
SOURCE_URL="https://code.claude.com/docs/en/skills#frontmatter-reference"

findings_json=""
first=1
n_findings=0
n_cleared=0
n_declined=0
declare -A DECLINED=()
declare -A CLEARED=()

while IFS=$'\t' read -r kind c2 c3 c4 c5; do
  [[ -n "$kind" ]] || continue
  case "$kind" in
  F)
    n_findings=$((n_findings + 1))
    piece="$(printf '{"rule": %s, "class": "restated-upstream-fact", "fix_eligible": false, "file": %s, "line": %s, "fact_id": %s, "source_url": %s, "excerpt": %s}' \
      "$(json_str "$RULE")" "$(json_str "$c3")" "$c4" "$(json_str "$c2")" "$(json_str "$SOURCE_URL")" "$(json_str "$c5")")"
    if [[ "$first" -eq 1 ]]; then
      findings_json="$piece"
      first=0
    else
      findings_json="$findings_json,$piece"
    fi
    ;;
  C)
    n_cleared=$((n_cleared + 1))
    CLEARED["$c2"]=$((${CLEARED[$c2]:-0} + 1))
    ;;
  D)
    n_declined=$((n_declined + 1))
    DECLINED["$c2"]=$((${DECLINED[$c2]:-0} + 1))
    ;;
  *) ;;
  esac
done <<<"$RECORDS"

cleared_json=""
cfirst=1
for key in listing-max-desc-chars listing-budget-fraction listing-entry-cap-1536; do
  [[ -n "${CLEARED[$key]:-}" ]] || continue
  piece="$(printf '{"fact_id": %s, "count": %s}' "$(json_str "$key")" "${CLEARED[$key]}")"
  if [[ "$cfirst" -eq 1 ]]; then
    cleared_json="$piece"
    cfirst=0
  else
    cleared_json="$cleared_json,$piece"
  fi
done

declined_json=""
dfirst=1
for key in changelog fenced frontmatter; do
  [[ -n "${DECLINED[$key]:-}" ]] || continue
  piece="$(printf '{"reason": %s, "count": %s}' "$(json_str "$key")" "${DECLINED[$key]}")"
  if [[ "$dfirst" -eq 1 ]]; then
    declined_json="$piece"
    dfirst=0
  else
    declined_json="$declined_json,$piece"
  fi
done

printf '{\n'
printf '  "catalog": {"basis": %s, "as_of": "2026-09-28"},\n' "$(json_str "$SOURCE_URL")"
printf '  "findings": [%s],\n' "$findings_json"
printf '  "cleared": [%s],\n' "$cleared_json"
printf '  "declined": [%s],\n' "$declined_json"
printf '  "counts": {"files": %s, "findings": %s, "cleared": %s, "declined": %s}\n' \
  "${#FILES[@]}" "$n_findings" "$n_cleared" "$n_declined"
printf '}\n'
