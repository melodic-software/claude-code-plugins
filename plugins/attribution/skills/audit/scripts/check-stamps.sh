#!/usr/bin/env bash
# Check verification stamps for expiry, and claim only what parses.
#
#   check-stamps.sh [files...] [--paths-file F] [--expiry-days N]
#                   [--trigger-less] [--as-of YYYY-MM-DD] [--show-config]
#
# Reasoning-free (Brief constraint C1): this script reads dates and compares
# them to a window. Whether a stamped claim is still TRUE is not knowable from
# a date and is never asserted here — the upstream-drift convention's own
# framing, that a date is an as-of record and never standing authority.
#
# What counts as a stamp, and what does not:
#
#   A candidate is a stamp keyword followed, within a short window, by
#   something date-shaped. BOTH halves are required. A date with no keyword is
#   not a stamp (a changelog entry is not a verification record) and a keyword
#   with no date is not one either ("confirmed from a primary source" is
#   prose). Of the candidates, only an ISO 8601 date is PARSED; every other
#   date-shaped form is DECLINED with the reason, and counted.
#
# The trigger-less check (--trigger-less, config `trigger_less_stamp_check`)
# ships OFF by default, per the Brief's portable-baseline constraint. It is
# deliberately coarse: it asks whether the SURFACE — the whole file, which is
# what the upstream-drift convention scopes a trigger to — states a recheck
# trigger anywhere, so a file that states one clears every stamp in it. Coarse
# in the conservative direction: it under-reports rather than inventing
# findings on a fleet whose stamp forms are not uniformly greppable.
#
# Exit: 0 on a clean run (with findings or none), 2 on usage or input error.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -r "$SCRIPT_DIR/lib.sh" ]]; then
  echo "check-stamps.sh: cannot read $SCRIPT_DIR/lib.sh" >&2
  for arg in "$@"; do
    if [[ "$arg" == "--show-config" ]]; then
      echo "detector unavailable"
      exit 0
    fi
  done
  exit 2
fi
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

FILES=()
PATHS_FILE=""
EXPIRY_OVERRIDE=""
TRIGGER_LESS_FLAG=0
AS_OF=""
SHOW_CONFIG=0

usage() {
  cat <<'EOF'
check-stamps.sh — flag expired verification stamps; decline what does not parse.

Usage:
  check-stamps.sh [files...] [--paths-file F] [--expiry-days N]
                  [--trigger-less] [--as-of YYYY-MM-DD] [--show-config]

  files...        markdown to check (default: tracked markdown in this repo;
                  the audit flow supplies list-corpus.sh's output instead)
  --paths-file F  read the file list from F, one path per line
  --expiry-days N override the configured window (default 180)
  --trigger-less  also flag dated stamps whose surface states no recheck
                  trigger; off unless this flag or config enables it
  --as-of DATE    the reference date (default: today), so a run is reproducible
  --show-config   print the effective config per layer, then exit

Output: JSON on stdout — {as_of, expiry_days, trigger_less_check, findings,
declined, counts}. Diagnostics go to stderr.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file)
    require_opt_value "check-stamps.sh" "$@"
    PATHS_FILE="$2"
    shift 2
    ;;
  --expiry-days)
    require_opt_value "check-stamps.sh" "$@"
    EXPIRY_OVERRIDE="$2"
    shift 2
    ;;
  --as-of)
    require_opt_value "check-stamps.sh" "$@"
    AS_OF="$2"
    shift 2
    ;;
  --trigger-less)
    TRIGGER_LESS_FLAG=1
    shift
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
    echo "check-stamps.sh: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  *)
    FILES+=("$1")
    shift
    ;;
  esac
done

if [[ -n "$EXPIRY_OVERRIDE" && ! "$EXPIRY_OVERRIDE" =~ ^[0-9]+$ ]]; then
  echo "check-stamps.sh: --expiry-days takes a whole number of days" >&2
  exit 2
fi
if [[ -n "$AS_OF" && ! "$AS_OF" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "check-stamps.sh: --as-of takes an ISO 8601 date (YYYY-MM-DD)" >&2
  exit 2
fi
[[ -n "$AS_OF" ]] || AS_OF="$(date +%Y-%m-%d)"

# --- Config cascade (user-global -> team -> personal override; JSON user-global, YAML team) -

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG_ROOT="${CLAUDE_PROJECT_DIR:-$REPO_ROOT}"

cfg_layers_init "$CONFIG_ROOT"

if cfg_have_unread_layer; then
  echo "check-stamps.sh: jq not found; JSON config layers present but unread, using defaults" >&2
fi

# The setup skill tells the operator to read per-value provenance out of
# `--show-config` rather than parsing the layers by hand, so each value carries
# the layer that supplied it (CFG_SOURCE after each read).
DEFAULT_EXPIRY_DAYS=180
EXPIRY_DAYS="" TRIGGER_LESS=""
cfg_scalar EXPIRY_DAYS stamp_expiry_days
EXPIRY_FROM="$CFG_SOURCE"
if [[ ! "$EXPIRY_DAYS" =~ ^[0-9]+$ ]]; then
  EXPIRY_DAYS="$DEFAULT_EXPIRY_DAYS"
  EXPIRY_FROM=""
fi
if [[ -n "$EXPIRY_OVERRIDE" ]]; then
  EXPIRY_DAYS="$EXPIRY_OVERRIDE"
  EXPIRY_FROM="--expiry-days"
fi

cfg_scalar TRIGGER_LESS trigger_less_stamp_check
TRIGGER_LESS_FROM="$CFG_SOURCE"
if [[ "$TRIGGER_LESS" != "true" && "$TRIGGER_LESS" != "false" ]]; then
  TRIGGER_LESS_FROM=""
fi
if [[ "$TRIGGER_LESS_FLAG" -eq 1 ]]; then
  TRIGGER_LESS_CHECK=1
  TRIGGER_LESS_FROM="--trigger-less"
elif [[ "$TRIGGER_LESS" == "true" ]]; then
  TRIGGER_LESS_CHECK=1
else
  TRIGGER_LESS_CHECK=0
fi
TRIGGER_LESS_BOOL=false
[[ "$TRIGGER_LESS_CHECK" -eq 1 ]] && TRIGGER_LESS_BOOL=true

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  cfg_layers_print
  echo "Effective: stamp_expiry_days=$EXPIRY_DAYS $(cfg_from_label "$EXPIRY_FROM")"
  echo "Effective: trigger_less_stamp_check=$TRIGGER_LESS_BOOL $(cfg_from_label "$TRIGGER_LESS_FROM")"
  echo "Effective: as_of=$AS_OF"
  exit 0
fi

# --- Inputs ----------------------------------------------------------------------

if [[ -n "$PATHS_FILE" ]]; then
  if [[ ! -r "$PATHS_FILE" ]]; then
    echo "check-stamps.sh: cannot read --paths-file: $PATHS_FILE" >&2
    exit 2
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && FILES+=("$line")
  done <"$PATHS_FILE"
fi

if [[ "${#FILES[@]}" -eq 0 ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && FILES+=("$REPO_ROOT/$line")
  done < <(git -C "$REPO_ROOT" -c core.quotePath=false ls-files -- '*.md' 2>/dev/null)
fi

for f in ${FILES[@]+"${FILES[@]}"}; do
  if [[ ! -f "$f" ]]; then
    echo "check-stamps.sh: not a readable file: $f" >&2
    exit 2
  fi
done

if [[ "${#FILES[@]}" -eq 0 ]]; then
  echo "check-stamps.sh: no files to check" >&2
fi

# --- Scan ------------------------------------------------------------------------
#
# awk emits a tab-separated record stream; the JSON is composed below. Records:
#   P <file> <line> <iso-date> <days_over> <surface_has_trigger>
#   D <file> <line> <reason-key> <text>
# Date arithmetic is days-from-civil (proleptic Gregorian), so no `date -d`
# dependency and no divergence between GNU and BSD date.

RECORDS="$(LC_ALL=C awk \
  -v as_of="$AS_OF" -v window="$EXPIRY_DAYS" '
function days_from_civil(y, m, d,   era, yoe, doy, doe) {
  if (m <= 2) y -= 1
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}

function valid_date(y, m, d,   md) {
  if (m < 1 || m > 12 || d < 1) return 0
  md = 31
  if (m == 4 || m == 6 || m == 9 || m == 11) md = 30
  if (m == 2) md = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28
  return d <= md
}

function tsv(s) {
  gsub(/[\t\r]/, " ", s)
  return s
}

function flush(   i) {
  if (current == "") return
  for (i = 1; i <= n_par; i++)
    printf("P\t%s\t%d\t%s\t%d\t%d\n", current, p_line[i], p_date[i], p_days[i], has_trigger)
  for (i = 1; i <= n_dec; i++)
    printf("D\t%s\t%d\t%s\t%s\n", current, d_line[i], d_reason[i], d_text[i])
}

function reset(name) {
  current = name
  n_par = 0; n_dec = 0; has_trigger = 0
  delete p_line; delete p_date; delete p_days
  delete d_line; delete d_reason; delete d_text
}

# may_form(w, worig): does this window carry the MONTH May rather than the
# ordinary English modal? "w" is the lowered window and "worig" the same span of
# the original line, which is where the discriminating signal lives.
#
# Two signals separate the two words, and either one alone is enough:
#
#   A digit beside it. Every date form carries one ("may 2026", "may 17",
#   "17 may") and the modal does not. Case-blind, so it is what an ALL-CAPS
#   heading falls back on.
#
#   A capital M on the original line. In edited prose the month is capitalized
#   and the modal is not, and the rest of the scan works from a lowered copy
#   that throws that signal away. This is what admits a digitless month date,
#   "Verified this May", as a digitless "Verified in June" is admitted.
#
# Known costs: a capitalized modal opening a sentence or a markdown table cell
# ("May the build stay green") reads as a month, and ALL-CAPS defeats case, so a
# digitless ALL-CAPS May date stays invisible.
#
# The two signals share ONE RSTART, and the caller reads it to decide whether
# the match began inside the window or out in the 9 characters of slack. So both
# are evaluated and the LEFTMOST wins, with RSTART and RLENGTH left describing
# that match — never the one this function passed over.
#
# Both scripts carry this rule, so the cross-script agreement the suites assert is
# blind to a defect they share: the two agree, on the wrong count. Both suites
# therefore pin the count itself as well as the agreement.
#
# A false return leaves RSTART = 0 and RLENGTH = -1, the values awk itself sets
# after a failed match, so a caller cannot read a stale offset off a window this
# function rejected.
function may_form(w, worig,   ds, dl, cs, cl) {
  ds = 0; dl = 0
  if (match(w, /(may[^a-z]*[0-9]|[0-9][^a-z]*may)/)) { ds = RSTART; dl = RLENGTH }
  # No leading boundary, matching the abbreviation rule below: a capital M after
  # a letter is not a word anyone writes. The trailing one is load-bearing, or
  # "Maybe" opening a sentence reads as a date.
  cs = 0; cl = 0
  if (match(worig, /May([^a-z]|$)/)) { cs = RSTART; cl = RLENGTH }
  # w and worig are the same span cut at the same offsets, so the two offsets are
  # directly comparable. A tie keeps the digit match: it cuts the window after
  # the digit rather than before it, and "May 2026" ties on every line that
  # carries one.
  if (ds > 0 && (cs == 0 || ds <= cs)) { RSTART = ds; RLENGTH = dl; return 1 }
  if (cs > 0) { RSTART = cs; RLENGTH = cl; return 1 }
  RSTART = 0; RLENGTH = -1
  return 0
}

# year_form(w): does this window carry a bare year, or a year and month, as a
# date? A year is four digits standing alone: not inside a longer token
# ("SC2034", "20260901T100000Z", "Finder_2024"), and the first number after the
# keyword, so "verified real (item 9, 2025" is prose that mentions a year, not
# a stamp. On a match RSTART is the offset of the year and RLENGTH is 4, or 7 when
# "-MM" follows, so the classifier can tell "2026-07" from "2026". A false
# return leaves RSTART = 0 and RLENGTH = -1. extract-breadcrumbs.sh carries the
# same test without the "-MM" extension.
function year_form(w,   off, s, pre, post) {
  off = 0
  while (match(substr(w, off + 1), /(19|20)[0-9][0-9]/)) {
    s = off + RSTART
    if (substr(w, 1, s - 1) ~ /[0-9]/) break
    pre = (s > 1) ? substr(w, s - 1, 1) : ""
    post = substr(w, s + 4, 1)
    if (pre !~ /[0-9a-z_]/ && post !~ /[0-9a-z_]/) {
      RSTART = s; RLENGTH = 4
      if (substr(w, s + 4, 3) ~ /^-[0-9][0-9]/ && substr(w, s + 7, 1) !~ /[0-9]/) RLENGTH = 7
      return 1
    }
    off = s
  }
  RSTART = 0; RLENGTH = -1
  return 0
}

# The stamp keyword list, the month list and may_form() are shared with
# extract-breadcrumbs.sh so the inventory and the check agree on which lines
# are candidates: change one, change the other.
#
# "read" is an ordinary English verb, so it gets a 30-character window rather
# than 60. That still admits the real forms ("read <ISO>", "read on <ISO>",
# "read of the page on <ISO>") while prose with a later year falls out.
function keyword_window(line,   low, pos, off, kw, wlen, s) {
  low = tolower(line)
  off = 0
  while (1) {
    if (!match(substr(low, off + 1), \
      /(^|[^a-z-])(verified|re-verified|docs-verified|last-verified|checked|confirmed|probed|measured|read|as[ -]of|current as of)([^a-z]|$)/))
      return ""
    pos = off + RSTART + RLENGTH - 1
    kw = substr(low, off + RSTART, RLENGTH)
    # "read" inside an identifier ("cache_read_input_tokens") is a name, not the verb.
    # Underscores that wrap the word alone ("_read_", Markdown emphasis) are not a name.
    s = off + RSTART
    if (kw ~ /_read|read_/ &&
        ((substr(kw, 1, 1) == "_" && s > 1 && substr(low, s - 1, 1) ~ /[a-z0-9]/) ||
         (substr(kw, length(kw), 1) == "_" && substr(low, pos + 1, 1) ~ /[a-z0-9]/))) {
      off = pos
      if (off >= length(low)) return ""
      continue
    }
    wlen = (kw ~ /read/) ? 30 : 60
    # The window is a distance from the keyword, not a cut through the text: a
    # date that STARTS inside it is read whole. So slice wlen plus 9 characters,
    # one short of the 10-character ISO date, and require each match to begin at
    # or before wlen. Each test returns the window cut at the end of its own
    # match, so the caller classifies on that match, never on one in the slack.
    # win_orig is the same span of the original line (tolower() keeps length),
    # read by may_form() for the capital May.
    win = substr(low, pos, wlen + 9)
    win_orig = substr(line, pos, wlen + 9)
    if (match(win, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) && RSTART <= wlen) return substr(win, 1, RSTART + RLENGTH - 1)
    if (match(win, /[0-9]+\/[0-9]+\/[0-9]+/) && RSTART <= wlen) return substr(win, 1, RSTART + RLENGTH - 1)
    if (match(win, /(january|february|march|april|june|july|august|september|october|november|december)/) && RSTART <= wlen) return substr(win, 1, RSTART + RLENGTH - 1)
    # may_form() leaves RSTART on the leftmost of its two signals. Its digit
    # half is unbounded in length, so a contrived "may" + 10 or more
    # non-letters + year starting at exactly wlen outruns the slack; no corpus
    # line has that form.
    if (may_form(win, win_orig) && RSTART <= wlen) return substr(win, 1, RSTART + RLENGTH - 1)
    if (match(win, /(jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)[^a-z]/) && RSTART <= wlen) return substr(win, 1, RSTART + RLENGTH - 1)
    if (year_form(win) && RSTART <= wlen) return substr(win, 1, RSTART + RLENGTH - 1)
    off = pos
    if (off >= length(low)) return ""
  }
}

BEGIN {
  split(as_of, a, "-")
  today = days_from_civil(a[1] + 0, a[2] + 0, a[3] + 0)
  current = ""
}

FNR == 1 { flush(); reset(FILENAME) }

# A recheck trigger anywhere on the surface clears every stamp in it.
# Interval expressions ({0,4}) are avoided throughout this program: mawk panics
# on them at compile time, and the panic is silent enough that the scan just
# returns nothing. `[^a-z]*` carries the same intent portably.
tolower($0) ~ /((recheck|re-check|revisit|re-derivation|reopening|re-trigger)[^a-z]*trigger)|(trigger[^a-z]*(for|is|:))|(what would reopen)/ {
  has_trigger = 1
}

# The inline clause `recheck when <condition>` and the `Recheck:` label (bold or
# plain) also state a trigger, but only with a condition after them: a bare
# `recheck` does not.
tolower($0) ~ /recheck[ \t]+when[ \t]+[^ \t]|recheck\**:\**[ \t]*[^ \t*]/ {
  has_trigger = 1
}

{
  win = keyword_window($0)
  if (win == "") next

  if (match(win, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) {
    iso = substr(win, RSTART, RLENGTH)
    split(iso, p, "-")
    if (!valid_date(p[1] + 0, p[2] + 0, p[3] + 0)) {
      n_dec++; d_line[n_dec] = FNR; d_reason[n_dec] = "invalid"; d_text[n_dec] = tsv($0)
      next
    }
    n_par++
    p_line[n_par] = FNR
    p_date[n_par] = iso
    p_days[n_par] = today - days_from_civil(p[1] + 0, p[2] + 0, p[3] + 0) - window
    next
  }

  n_dec++
  d_line[n_dec] = FNR
  d_text[n_dec] = tsv($0)
  if (win ~ /[0-9]+\/[0-9]+\/[0-9]+/) d_reason[n_dec] = "slash"
  else if (win ~ /(january|february|march|april|june|july|august|september|october|november|december)/) d_reason[n_dec] = "month"
  # The same may_form() the window test used, on win_orig re-cut to the length
  # of the accepted window, so a capital May in the slack cannot relabel a
  # bare-year decline as a month.
  else if (may_form(win, substr(win_orig, 1, length(win)))) d_reason[n_dec] = "month"
  else if (win ~ /(jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)[^a-z]/) d_reason[n_dec] = "month"
  else if (win ~ /(19|20)[0-9][0-9]-[0-9][0-9]$/) d_reason[n_dec] = "yearmonth"
  else d_reason[n_dec] = "year"
}

END { flush() }
' ${FILES[@]+"${FILES[@]}"})"

# --- JSON product ----------------------------------------------------------------

reason_text() {
  case "$1" in
  month) printf 'unparsed stamp date: month name form, not ISO 8601 (YYYY-MM-DD)' ;;
  slash) printf 'unparsed stamp date: slash form, not ISO 8601 (YYYY-MM-DD)' ;;
  year) printf 'unparsed stamp date: bare year, no month or day' ;;
  yearmonth) printf 'unparsed stamp date: year and month only, no day' ;;
  invalid) printf 'unparsed stamp date: not a valid calendar date' ;;
  *) printf 'unparsed stamp date' ;;
  esac
}

FINDINGS=()
declare -A DECLINED_COUNT=()
declare -A DECLINED_EXAMPLES=()
parsed=0
declined=0

EXPIRED_RULE="attribution/audit/rule-stamp-expired"
TRIGGERLESS_RULE="attribution/audit/rule-trigger-less-stamp"

while IFS=$'\t' read -r kind file line c4 c5 c6; do
  [[ -n "$kind" ]] || continue
  case "$kind" in
  P)
    parsed=$((parsed + 1))
    if [[ "$c5" -gt 0 ]]; then
      FINDINGS+=("$EXPIRED_RULE"$'\t'"$file"$'\t'"$line"$'\t'"$c4"$'\t'"$c5")
    fi
    if [[ "$TRIGGER_LESS_CHECK" -eq 1 && "$c6" -eq 0 ]]; then
      FINDINGS+=("$TRIGGERLESS_RULE"$'\t'"$file"$'\t'"$line"$'\t'"$c4"$'\t')
    fi
    ;;
  D)
    declined=$((declined + 1))
    DECLINED_COUNT["$c4"]=$((${DECLINED_COUNT[$c4]:-0} + 1))
    if [[ "${DECLINED_COUNT[$c4]}" -le 5 ]]; then
      DECLINED_EXAMPLES["$c4"]="${DECLINED_EXAMPLES[$c4]:-}${file}"$'\t'"${line}"$'\t'"${c5}"$'\n'
    fi
    ;;
  *) ;;
  esac
done <<<"$RECORDS"

printf '{\n'
printf '  "as_of": %s,\n' "$(json_str "$AS_OF")"
printf '  "expiry_days": %s,\n' "$EXPIRY_DAYS"
printf '  "trigger_less_check": %s,\n' "$TRIGGER_LESS_BOOL"

printf '  "findings": ['
first=1
for entry in ${FINDINGS[@]+"${FINDINGS[@]}"}; do
  IFS=$'\t' read -r rule file line stamp_date days_over <<<"$entry"
  [[ "$first" -eq 1 ]] && printf '\n' || printf ',\n'
  first=0
  printf '    {"rule": %s, "file": %s, "line": %s, "stamp_date": %s, "window_days": %s' \
    "$(json_str "$rule")" "$(json_str "$file")" "$line" "$(json_str "$stamp_date")" "$EXPIRY_DAYS"
  if [[ -n "$days_over" ]]; then
    printf ', "days_over": %s' "$days_over"
  fi
  printf '}'
done
[[ "$first" -eq 1 ]] || printf '\n  '
printf '],\n'

printf '  "declined": ['
first=1
for key in month slash year yearmonth invalid; do
  [[ -n "${DECLINED_COUNT[$key]:-}" ]] || continue
  [[ "$first" -eq 1 ]] && printf '\n' || printf ',\n'
  first=0
  printf '    {"reason": %s, "count": %s, "examples": [' \
    "$(json_str "$(reason_text "$key")")" "${DECLINED_COUNT[$key]}"
  ex_first=1
  while IFS=$'\t' read -r ef el et; do
    [[ -n "$ef" ]] || continue
    [[ "$ex_first" -eq 1 ]] || printf ', '
    ex_first=0
    printf '{"file": %s, "line": %s, "text": %s}' \
      "$(json_str "$ef")" "$el" "$(json_str "$et")"
  done <<<"${DECLINED_EXAMPLES[$key]:-}"
  printf ']}'
done
[[ "$first" -eq 1 ]] || printf '\n  '
printf '],\n'

printf '  "counts": {"files": %s, "candidates": %s, "parsed": %s, "declined": %s, "findings": %s}\n' \
  "${#FILES[@]}" "$((parsed + declined))" "$parsed" "$declined" "${#FINDINGS[@]}"
printf '}\n'
