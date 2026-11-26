#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
Report the shared skill-listing character budget across one or more skills roots (advisory).

Usage:
  check-listing-budget.sh [--from-settings] [<skills-root> ...]
  check-listing-budget.sh --help

  --from-settings                      report the budget this machine resolves instead of the documented default:
                                       SLASH_COMMAND_TOOL_CHAR_BUDGET, else skillListingBudgetFraction from the
                                       first of .claude/settings.local.json, .claude/settings.json and
                                       ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json that sets it
  <skills-root>                        pooled into one aggregate; with none, one root resolves as check-skill.sh does
  CHECK_SKILL_LISTING_BUDGET_CHARS     fixed aggregate budget in characters (default 8000)
  CHECK_SKILL_LISTING_CONTEXT_TOKENS   context window to derive the budget from
  CHECK_SKILL_LISTING_BUDGET_FRACTION  budget fraction (default 0.01)
  CHECK_SKILL_LISTING_CHARS_PER_TOKEN  characters per token (default 4)
  CHECK_SKILL_LISTING_MAX_DESC_CHARS   per-entry cap applied before summing (default 1536)
  CHECK_SKILL_SKILLS_ROOT              single-root override for the no-argument form

Exit 0 always (report-only), except a usage/env error (exit 2).
EOF
}

FROM_SETTINGS=0
while [[ "${1:-}" == -* ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --from-settings) FROM_SETTINGS=1 ;;
  *)
    printf 'Error: unknown option: %s (run with --help)\n' "$1" >&2
    exit 2
    ;;
  esac
  shift
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
HAVE_GIT=0
if [[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]]; then
  HAVE_GIT=1
fi

require_positive_number() {
  local name="$1" val="$2" kind="${3:-int}"
  local pattern='^[0-9]+$'
  [[ "$kind" == "num" ]] && pattern='^([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
  if [[ ! "$val" =~ $pattern ]] || ! awk -v v="$val" 'BEGIN { exit (v > 0) ? 0 : 1 }'; then
    printf 'Error: %s must be a positive number, got: %s\n' "$name" "$val" >&2
    exit 2
  fi
}

to_decimal() {
  printf '%s' "$((10#$1))"
}

MAX_DESC_CHARS="${CHECK_SKILL_LISTING_MAX_DESC_CHARS:-1536}"
require_positive_number CHECK_SKILL_LISTING_MAX_DESC_CHARS "$MAX_DESC_CHARS" int
MAX_DESC_CHARS="$(to_decimal "$MAX_DESC_CHARS")"
JOINER_CHARS=3 # the literal " - " the harness inserts between description and when_to_use

BUDGETS=()
SOURCES=()
BUDGET_IS_DEFAULT=0
FRACTION=""
FRACTION_SOURCE=""

add_reconstructed_row() {
  local tokens="$1" chars
  require_positive_number CHECK_SKILL_LISTING_CHARS_PER_TOKEN "$CHARS_PER_TOKEN" num
  if ! chars="$(awk -v t="$tokens" -v c="$CHARS_PER_TOKEN" -v f="$FRACTION" \
    'BEGIN { printf "%d", t * c * f }' 2>/dev/null)" || [[ -z "$chars" ]] || ((chars <= 0)); then
    printf 'Error: could not compute a budget from %s tokens x %s chars/token x %s\n' \
      "$tokens" "$CHARS_PER_TOKEN" "$FRACTION" >&2
    exit 2
  fi
  BUDGETS+=("$chars")
  SOURCES+=("reconstructed: $tokens tokens x $CHARS_PER_TOKEN chars/token x $FRACTION")
}

read_settings_fraction() {
  local project_dir="${CLAUDE_PROJECT_DIR:-}" config_dir="${CLAUDE_CONFIG_DIR:-}" f hit
  local candidates=() existing=()
  [[ -z "$project_dir" && "$HAVE_GIT" == 1 ]] && project_dir="$REPO_ROOT"
  [[ -n "$project_dir" ]] && candidates+=("$project_dir/.claude/settings.local.json" "$project_dir/.claude/settings.json")
  [[ -z "$config_dir" && -n "${HOME:-}" ]] && config_dir="$HOME/.claude"
  [[ -n "$config_dir" ]] && candidates+=("$config_dir/settings.json")
  for f in "${candidates[@]}"; do
    [[ -f "$f" ]] && existing+=("$f")
  done
  FRACTION="0.01"
  FRACTION_SOURCE="documented default (no settings file read sets skillListingBudgetFraction)"
  ((${#existing[@]} > 0)) || return 0
  if ! command -v jq >/dev/null 2>&1; then
    printf 'Error: --from-settings needs jq to read %s\n' "${existing[*]}" >&2
    exit 2
  fi
  if ! hit="$(jq -r 'objects | select((.skillListingBudgetFraction | type) == "number")
      | "\(input_filename)\t\(.skillListingBudgetFraction)"' "${existing[@]}" | tr -d '\r')"; then
    printf 'Error: could not parse settings JSON among: %s\n' "${existing[*]}" >&2
    exit 2
  fi
  hit="${hit%%$'\n'*}"
  [[ -n "$hit" ]] || return 0
  FRACTION="${hit##*$'\t'}"
  FRACTION_SOURCE="settings:${hit%$'\t'*}"
  require_positive_number "skillListingBudgetFraction in ${hit%$'\t'*}" "$FRACTION" num
}

if [[ -n "${CHECK_SKILL_LISTING_BUDGET_CHARS:-}" ]]; then
  require_positive_number CHECK_SKILL_LISTING_BUDGET_CHARS "$CHECK_SKILL_LISTING_BUDGET_CHARS" int
  BUDGETS+=("$(to_decimal "$CHECK_SKILL_LISTING_BUDGET_CHARS")")
  SOURCES+=("override (CHECK_SKILL_LISTING_BUDGET_CHARS)")
  if [[ -n "${CHECK_SKILL_LISTING_CONTEXT_TOKENS:-}" ]]; then
    printf 'Note: CHECK_SKILL_LISTING_BUDGET_CHARS takes precedence; ignoring CHECK_SKILL_LISTING_CONTEXT_TOKENS=%s\n' \
      "$CHECK_SKILL_LISTING_CONTEXT_TOKENS" >&2
  fi
elif ((FROM_SETTINGS)) && [[ -n "${SLASH_COMMAND_TOOL_CHAR_BUDGET:-}" ]]; then
  require_positive_number SLASH_COMMAND_TOOL_CHAR_BUDGET "$SLASH_COMMAND_TOOL_CHAR_BUDGET" int
  BUDGETS+=("$(to_decimal "$SLASH_COMMAND_TOOL_CHAR_BUDGET")")
  SOURCES+=("env:SLASH_COMMAND_TOOL_CHAR_BUDGET")
else
  CHARS_PER_TOKEN="${CHECK_SKILL_LISTING_CHARS_PER_TOKEN:-4}"
  if [[ -n "${CHECK_SKILL_LISTING_BUDGET_FRACTION:-}" ]]; then
    FRACTION="$CHECK_SKILL_LISTING_BUDGET_FRACTION"
    FRACTION_SOURCE="override (CHECK_SKILL_LISTING_BUDGET_FRACTION)"
    require_positive_number CHECK_SKILL_LISTING_BUDGET_FRACTION "$FRACTION" num
  elif ((FROM_SETTINGS)); then
    read_settings_fraction
    [[ "$FRACTION_SOURCE" == documented* ]] && BUDGET_IS_DEFAULT=1
  fi
  if [[ -n "${CHECK_SKILL_LISTING_CONTEXT_TOKENS:-}" ]]; then
    require_positive_number CHECK_SKILL_LISTING_CONTEXT_TOKENS "$CHECK_SKILL_LISTING_CONTEXT_TOKENS" int
    [[ -n "$FRACTION" ]] || FRACTION="0.01"
    BUDGET_IS_DEFAULT=0
    add_reconstructed_row "$(to_decimal "$CHECK_SKILL_LISTING_CONTEXT_TOKENS")"
  elif [[ -n "$FRACTION" ]]; then
    add_reconstructed_row 200000
    add_reconstructed_row 1000000
  else
    BUDGETS+=(8000)
    SOURCES+=("documented default (SLASH_COMMAND_TOOL_CHAR_BUDGET fallback)")
    BUDGET_IS_DEFAULT=1
  fi
fi

ROOTS=()
EXPLICIT_ROOTS=0
if (($# > 0)); then
  ROOTS=("$@")
  EXPLICIT_ROOTS=1
else
  if [[ -n "${CHECK_SKILL_SKILLS_ROOT:-}" ]]; then
    SINGLE_ROOT="$CHECK_SKILL_SKILLS_ROOT"
  elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    SINGLE_ROOT="$CLAUDE_PROJECT_DIR/.claude/skills"
  elif [[ "$HAVE_GIT" == 1 ]]; then
    SINGLE_ROOT="$REPO_ROOT/.claude/skills"
  else
    printf 'Error: not in a git repo and no skills root set — set CHECK_SKILL_SKILLS_ROOT (or CLAUDE_PROJECT_DIR), pass an explicit skills root, or run from inside a git repository\n' >&2
    exit 2
  fi
  if [[ "$SINGLE_ROOT" != /* && ! "$SINGLE_ROOT" =~ ^[A-Za-z]:[\\/] ]]; then
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
      SINGLE_ROOT="$CLAUDE_PROJECT_DIR/$SINGLE_ROOT"
    elif [[ "$HAVE_GIT" == 1 ]]; then
      SINGLE_ROOT="$REPO_ROOT/$SINGLE_ROOT"
    else
      printf 'Error: relative skills root %s needs CLAUDE_PROJECT_DIR or a git repository to anchor against\n' "$SINGLE_ROOT" >&2
      exit 2
    fi
  fi
  ROOTS=("$SINGLE_ROOT")
fi

CONTRIB_FILE="$(mktemp)"
FILE_LIST="$(mktemp)"
trap 'rm -f "$CONTRIB_FILE" "$FILE_LIST"' EXIT

FOUND_ROOTS=0
SKILL_ENTRIES=()
for root in "${ROOTS[@]}"; do
  if [[ ! -d "$root" ]]; then
    if ((EXPLICIT_ROOTS)); then
      printf 'Error: skills root does not exist: %s\n' "$root" >&2
      exit 2
    fi
    continue
  fi
  FOUND_ROOTS=$((FOUND_ROOTS + 1))
  for skill_md in "$root"/*/SKILL.md; do
    [[ -f "$skill_md" ]] || continue
    SKILL_ENTRIES+=("$root"$'\t'"$skill_md")
  done
done
if ((${#SKILL_ENTRIES[@]} > 0)); then
  printf '%s\n' "${SKILL_ENTRIES[@]}" >"$FILE_LIST"
fi

if ! AWK_RESULT="$(awk -F'\t' \
  -v max="$MAX_DESC_CHARS" -v joiner_chars="$JOINER_CHARS" -v out="$CONTRIB_FILE" '
  BEGIN { FM_TRUE["true"]; FM_TRUE["yes"]; FM_TRUE["on"]; FM_TRUE["1"] }
  function trim_ws(v) {
    sub(/^[[:space:]]+/, "", v)
    sub(/[[:space:]]+$/, "", v)
    return v
  }
  # ONE outer quote layer, double OR single, not both — and never a lone quote
  # character, which the shell pattern `"*"` could not match either.
  function strip_quotes(s,   n, q) {
    n = length(s)
    if (n < 2) return s
    q = substr(s, 1, 1)
    if ((q == "\"" || q == "\047") && substr(s, n, 1) == q) return substr(s, 2, n - 2)
    return s
  }
  function normalize_bool(v) { return tolower(trim_ws(strip_quotes(trim_ws(v)))) }
  function strip_trailing_nl(v) { sub(/\n+$/, "", v); return v }
  # Cut a trailing YAML comment from a plain or flow scalar. A quoted scalar
  # ends at its closing quote and anything after it is comment; a plain scalar
  # ends at the first whitespace-preceded `#`. An unterminated quote is left
  # whole, because malformed YAML is not for this helper to guess at.
  # \047 is a single quote: the program is single-quoted by the shell, so
  # spelling the character out would end it mid-expression.
  function fm_strip_comment(v,   n, q, i, ch) {
    n = length(v)
    if (n == 0) return v
    q = substr(v, 1, 1)
    if (q == "\"" || q == "\047") {
      i = 2
      while (i <= n) {
        ch = substr(v, i, 1)
        if (q == "\"" && ch == "\\") { i += 2; continue }
        if (ch == q) {
          # A single-quoted YAML scalar escapes one quote by doubling it.
          if (q == "\047" && substr(v, i + 1, 1) == "\047") { i += 2; continue }
          return substr(v, 1, i)
        }
        i++
      }
      return v
    }
    # A value that opens with `#` is all comment: the scalar is empty.
    if (q == "#") return ""
    if (match(v, /[[:space:]]+#/)) return substr(v, 1, RSTART - 1)
    return v
  }
  # Text capture for the budget count, not a full YAML parser: a frontmatter key
  # sits at column 0, so every indented line is block content and the first
  # column-0 line is the next key. Collecting on that boundary ignores the
  # indent indicator entirely, so an explicit indent smaller than the first
  # content line cannot drop later lines. Leading indent is stripped per line
  # (irrelevant to a character count). Literal (`|`) joins with newlines,
  # folded (`>`) with spaces.
  function fm_field(k,   i, val, fold, acc, started, ln, j) {
    for (i = 1; i <= FN; i++) {
      if (FM[i] ~ "^" k ":[[:space:]]*") {
        val = FM[i]
        sub("^" k ":[[:space:]]*", "", val)
        if (val ~ /^[|>]([0-9][+-]?|[+-][0-9]?)?[[:space:]]*(#.*)?$/) {
          fold = (val ~ /^>/)
          acc = ""; started = 0
          for (j = i + 1; j <= FN; j++) {
            ln = FM[j]
            if (ln ~ /^[[:space:]]*$/) { if (started) acc = acc (fold ? " " : "\n"); continue }
            if (ln !~ /^[[:space:]]/) break
            sub(/^[[:space:]]+/, "", ln)
            if (started) acc = acc (fold ? " " : "\n")
            acc = acc ln
            started = 1
          }
          return acc
        }
        return fm_strip_comment(val)
      }
    }
    return ""
  }
  {
    root = $1; path = $2
    # Frontmatter: the opening fence MUST be line 1 — content before it is not
    # frontmatter, so a stray `---` further down cannot be mistaken for the
    # block start. FM is only ever read up to FN, so stale entries from a
    # previous, longer file are unreachable and need no delete.
    FN = 0; nr = 0; fence = 0
    while ((getline ln < path) > 0) {
      nr++
      if (nr == 1 && ln !~ /^---[[:space:]]*$/) break
      if (ln ~ /^---[[:space:]]*$/) {
        fence++
        if (fence == 1) continue
        break
      }
      if (fence == 1) FM[++FN] = ln
    }
    close(path)
    while (FN > 0 && FM[FN] == "") FN--
    if (FN == 0) next
    # No strip_trailing_nl on this one, and the asymmetry with the next two
    # lines is deliberate rather than an oversight: normalize_bool opens with
    # trim_ws, whose trailing sub uses [[:space:]] — which matches a newline —
    # so it already subsumes the strip. The description and when_to_use lines DO
    # need it, because strip_quotes trims nothing: a value still ending in a
    # newline has that newline as its last character, so the closing quote never
    # matches and the quote marks survive into the measured length.
    if (normalize_bool(fm_field("disable-model-invocation")) in FM_TRUE) next
    desc = strip_quotes(strip_trailing_nl(fm_field("description")))
    wtu = strip_quotes(strip_trailing_nl(fm_field("when_to_use")))
    desc_len = length(desc); wtu_len = length(wtu)
    entry_len = desc_len + (wtu_len > 0 ? joiner_chars : 0) + wtu_len
    # The harness truncates each entry to the per-skill cap BEFORE the shared
    # budget ever sees it — mirror that here so an already-oversized single
    # entry — the FAIL check 2 already raises — does not inflate this aggregate
    # beyond what Claude Code would actually load.
    if (entry_len > max) entry_len = max
    total += entry_len; count++
    name = path
    sub(/\/SKILL\.md$/, "", name)
    sub(/^.*\//, "", name)
    printf "%d\t%s\t%s\n", entry_len, name, root > out
  }
  END { close(out); printf "%d %d\n", total, count }
  ' "$FILE_LIST")"; then
  printf 'Error: the single-pass frontmatter scan failed; refusing to report a partial aggregate\n' >&2
  exit 2
fi
TOTAL="${AWK_RESULT%% *}"
ENTRY_COUNT="${AWK_RESULT##* }"

if ((FOUND_ROOTS == 0)); then
  printf 'Error: no skills root found among: %s\n' "${ROOTS[*]}" >&2
  exit 2
fi

if ((ENTRY_COUNT == 0)); then
  printf 'No listing-eligible skills found under: %s\n' "${ROOTS[*]}"
  printf '\nCHECK-LISTING-BUDGET: 0 skills, nothing to report\n'
  exit 0
fi

printf 'Shared listing-budget estimate over %d listing-eligible skill(s) across %d root(s):\n' "$ENTRY_COUNT" "$FOUND_ROOTS"
printf '  aggregate: %d chars\n' "$TOTAL"
BAND=0
((${#BUDGETS[@]} > 1)) && BAND=1
if ((BAND || FROM_SETTINGS)) && [[ -n "$FRACTION_SOURCE" ]]; then
  printf '  fraction:  %s (%s)\n' "$FRACTION" "$FRACTION_SOURCE"
fi
if ((FROM_SETTINGS)); then
  printf '  note:      managed policy and settings env blocks are not read; /doctor shows the resolved budget\n'
fi
BUDGET_CHARS="${BUDGETS[0]}"
OVER_ROWS=0
for i in "${!BUDGETS[@]}"; do
  verdict="OK"
  if ((TOTAL > BUDGETS[i])); then
    verdict="WARN, over by $((TOTAL - BUDGETS[i])) chars"
    OVER_ROWS=$((OVER_ROWS + 1))
  fi
  if ((BAND)); then
    printf '  budget:    %d chars (%s): %s\n' "${BUDGETS[i]}" "${SOURCES[i]}" "$verdict"
  else
    printf '  budget:    %d chars (%s)\n' "${BUDGETS[i]}" "${SOURCES[i]}"
  fi
done
BASIS="configured"
((BUDGET_IS_DEFAULT)) && BASIS="documented default"
BUDGET_NOUN="the budget"
((BAND)) && BUDGET_NOUN="the smallest budget"

if ((TOTAL > BUDGET_CHARS)); then
  OVERFLOW=$((TOTAL - BUDGET_CHARS))
  MULT="$(awk -v t="$TOTAL" -v b="$BUDGET_CHARS" 'BEGIN { printf "%.1f", t / b }' 2>/dev/null || echo '?')"
  printf 'WARN: aggregate exceeds %s by %d chars (~%sx over) — Claude Code drops the\n' "$BUDGET_NOUN" "$OVERFLOW" "$MULT"
  printf '      least-invoked skills'"'"' descriptions to name-only when this happens live.\n'
  printf '      Biggest contributors (entry chars, skill, root):\n'
  sort -t $'\t' -k1,1nr "$CONTRIB_FILE" | head -10 | while IFS=$'\t' read -r len name root; do
    printf '        %6d  %s  (%s)\n' "$len" "$name" "$root"
  done
  if ((BAND)); then
    printf '\nCHECK-LISTING-BUDGET: WARN — aggregate %d chars over %d of %d budgets at the %s fraction %s (smallest %d chars, over by %d).\n' \
      "$TOTAL" "$OVER_ROWS" "${#BUDGETS[@]}" "$BASIS" "$FRACTION" "$BUDGET_CHARS" "$OVERFLOW"
  else
    printf '\nCHECK-LISTING-BUDGET: WARN — aggregate %d/%d chars over budget by %s at the %s budget.\n' \
      "$TOTAL" "$BUDGET_CHARS" "$OVERFLOW" "$BASIS"
  fi
  printf 'This is an estimate against a configurable default, not a live measurement — run\n'
  # shellcheck disable=SC2016  # single quotes deliberate: the backticks are literal, not shell expansion
  printf '`/doctor` in a live session for the authoritative resolved cost and contributors.\n'
elif ((BAND)); then
  printf 'CHECK-LISTING-BUDGET: OK — aggregate %d chars within every budget (smallest %d chars).\n' "$TOTAL" "$BUDGET_CHARS"
else
  printf 'CHECK-LISTING-BUDGET: OK — aggregate %d/%d chars within budget.\n' "$TOTAL" "$BUDGET_CHARS"
fi

exit 0
