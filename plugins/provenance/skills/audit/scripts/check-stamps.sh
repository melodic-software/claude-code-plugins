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
# Declining is the point, not a shortfall. The live corpus carries stamp dates
# in a long tail of prose forms — "verified <ISO>" dominates, but month-name,
# slash and bare-year forms all appear — and a parser that guessed at those
# would manufacture findings against dates nobody wrote down precisely. A high
# declined count is an honest report of the corpus, not a defect to tune away.
#
# The trigger-less check (--trigger-less, config `trigger_less_stamp_check`)
# ships OFF by default, per the Brief's portable-baseline constraint. It is
# deliberately coarse: it asks whether the SURFACE — the whole file, which is
# what the upstream-drift convention scopes a trigger to — states a recheck
# trigger anywhere, so a file that states one clears every stamp in it. Coarse
# in the conservative direction: it under-reports rather than inventing
# findings on a fleet whose stamp forms are not uniformly greppable.
#
# Contract: docs/specs/provenance-type-inventory.md.
# Exit: 0 on a clean run (with findings or none), 2 on usage or input error.
set -uo pipefail

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

require_opt_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
    echo "check-stamps.sh: $opt requires a value" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file)
    require_opt_value "$@"
    PATHS_FILE="$2"
    shift 2
    ;;
  --expiry-days)
    require_opt_value "$@"
    EXPIRY_OVERRIDE="$2"
    shift 2
    ;;
  --as-of)
    require_opt_value "$@"
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

# --- Config cascade (.claude/provenance.json; user-global -> team -> overlay) -----

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG_ROOT="${CLAUDE_PROJECT_DIR:-$REPO_ROOT}"

CFG_LAYERS=()
[[ -f "${HOME:-/nonexistent}/.claude/provenance.json" ]] && CFG_LAYERS+=("$HOME/.claude/provenance.json")
[[ -f "$CONFIG_ROOT/.claude/provenance.json" ]] && CFG_LAYERS+=("$CONFIG_ROOT/.claude/provenance.json")
[[ -f "$CONFIG_ROOT/.claude/provenance.local.json" ]] && CFG_LAYERS+=("$CONFIG_ROOT/.claude/provenance.local.json")

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

# cfg_scalar <jq-path>: last layer that defines the key wins (per-key override).
# Carriage returns are stripped because the Windows build of jq emits CRLF; a
# CR-suffixed value silently stops matching (the ai-slop #3343 finding).
# CFG_SOURCE carries the layer that supplied the value the last call returned,
# empty when no layer did. The setup skill tells the operator to read per-value
# provenance out of `--show-config` rather than parsing the layers by hand, so
# the effective value alone is not enough: with two layers present, nothing
# would say which one won.
CFG_SOURCE=""
cfg_scalar() {
  local path="$1" layer v out="" src=""
  CFG_SOURCE=""
  if [[ "$HAVE_JQ" -eq 0 ]]; then
    printf ''
    return 0
  fi
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    v="$(jq -r "$path // empty" "$layer" 2>/dev/null)" || continue
    v="${v//$'\r'/}"
    if [[ -n "$v" ]]; then
      out="$v"
      src="$layer"
    fi
  done
  CFG_SOURCE="$src"
  printf '%s' "$out"
}

if [[ "$HAVE_JQ" -eq 0 && "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  echo "check-stamps.sh: jq not found; config layers present but unread, using defaults" >&2
fi

DEFAULT_EXPIRY_DAYS=180
EXPIRY_DAYS="$(cfg_scalar '.stamp_expiry_days')"
EXPIRY_FROM="$CFG_SOURCE"
if [[ ! "$EXPIRY_DAYS" =~ ^[0-9]+$ ]]; then
  EXPIRY_DAYS="$DEFAULT_EXPIRY_DAYS"
  EXPIRY_FROM=""
fi
if [[ -n "$EXPIRY_OVERRIDE" ]]; then
  EXPIRY_DAYS="$EXPIRY_OVERRIDE"
  EXPIRY_FROM="--expiry-days"
fi

TRIGGER_LESS="$(cfg_scalar '.trigger_less_stamp_check')"
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

# from_label <source>: how --show-config attributes one effective value.
from_label() {
  if [[ -z "$1" ]]; then
    printf '(bundled default)'
  elif [[ "$1" == --* ]]; then
    printf '(from %s)' "$1"
  else
    printf '(from %s)' "$1"
  fi
}

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  echo "Config layers (later refines earlier):"
  if [[ "${#CFG_LAYERS[@]}" -eq 0 ]]; then
    echo "  (none; bundled defaults)"
  else
    for layer in "${CFG_LAYERS[@]}"; do echo "  $layer"; done
  fi
  echo "Effective: stamp_expiry_days=$EXPIRY_DAYS $(from_label "$EXPIRY_FROM")"
  echo "Effective: trigger_less_stamp_check=$([[ "$TRIGGER_LESS_CHECK" -eq 1 ]] && echo true || echo false) $(from_label "$TRIGGER_LESS_FROM")"
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

# The stamp keyword list is shared with extract-breadcrumbs.sh on purpose: one
# definition of what looks like a stamp, so the inventory and the check agree
# about which lines are candidates.
#
# "read" gets a much tighter window than the explicit stamp verbs. It is an
# ordinary English verb, and at the wide window a corpus run turned lines like
# "a single-source, unconfirmed read of a shipped build" into candidates purely
# because a year appeared later in the sentence. The narrow window still admits
# every real form the corpus uses ("read <ISO>", "read on <ISO>", "read of the
# page on <ISO>") while the prose uses fall out, measured 2026-08-28 over 1,347
# tracked files.
function keyword_window(line,   low, pos, off, kw, wlen) {
  low = tolower(line)
  off = 0
  while (1) {
    if (!match(substr(low, off + 1), \
      /(^|[^a-z-])(verified|re-verified|docs-verified|last-verified|checked|confirmed|probed|measured|read|as[ -]of|current as of)([^a-z]|$)/))
      return ""
    pos = off + RSTART + RLENGTH - 1
    kw = substr(low, off + RSTART, RLENGTH)
    wlen = (kw ~ /read/) ? 30 : 60
    win = substr(low, pos, wlen)
    if (win ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return win
    if (win ~ /[0-9]+\/[0-9]+\/[0-9]+/) return win
    if (win ~ /(january|february|march|april|may|june|july|august|september|october|november|december)/) return win
    if (win ~ /(jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)[^a-z]/) return win
    if (win ~ /(19|20)[0-9][0-9]/) return win
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
  else if (win ~ /(january|february|march|april|may|june|july|august|september|october|november|december)/) d_reason[n_dec] = "month"
  else if (win ~ /(jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)[^a-z]/) d_reason[n_dec] = "month"
  else d_reason[n_dec] = "year"
}

END { flush() }
' ${FILES[@]+"${FILES[@]}"})"

# --- JSON product ----------------------------------------------------------------

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

reason_text() {
  case "$1" in
  month) printf 'unparsed stamp date: month name form, not ISO 8601 (YYYY-MM-DD)' ;;
  slash) printf 'unparsed stamp date: slash form, not ISO 8601 (YYYY-MM-DD)' ;;
  year) printf 'unparsed stamp date: bare year, no month or day' ;;
  invalid) printf 'unparsed stamp date: not a valid calendar date' ;;
  *) printf 'unparsed stamp date' ;;
  esac
}

FINDINGS=()
declare -A DECLINED_COUNT=()
declare -A DECLINED_EXAMPLES=()
parsed=0
declined=0

EXPIRED_RULE="provenance/audit/rule-stamp-expired"
TRIGGERLESS_RULE="provenance/audit/rule-trigger-less-stamp"

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
printf '  "trigger_less_check": %s,\n' "$([[ "$TRIGGER_LESS_CHECK" -eq 1 ]] && echo true || echo false)"

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
for key in month slash year invalid; do
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
