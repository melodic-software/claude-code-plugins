#!/usr/bin/env bash
# Static, deterministic report of the SHARED skill-listing character budget
# across one or more skills roots — the aggregate limit `check-skill.sh` never
# checks (see its header: check 2 is a PER-SKILL entry cap, not this).
#
# Claude Code loads a listing of every skill's name + description into context
# each turn. Two independent limits apply to it:
#   - Per-entry cap (skillListingMaxDescChars, default 1536): check-skill.sh
#     check 2 already guards this.
#   - Shared/aggregate cap (skillListingBudgetFraction, default 0.01 = 1% of
#     the model's context window): NOTHING checks this before now. When the
#     aggregate overflows, Claude Code drops descriptions for the
#     least-invoked skills first (name-only), degrading their auto-invocation
#     with no local signal that it happened.
# https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short
# https://code.claude.com/docs/en/settings (skillListingBudgetFraction,
#   skillListingMaxDescChars, SLASH_COMMAND_TOOL_CHAR_BUDGET) — fetched and
#   verified current at authoring time.
#
# What counts, and what deliberately does not:
#   - This models DESCRIPTION characters only. The listing "always contains
#     every skill name" (docs, above), so names are a floor this report does
#     not estimate; the budget is spent on description + when_to_use text,
#     which is what is summed here.
#   - Skills with `disable-model-invocation: true` are SKIPPED. Per
#     https://code.claude.com/docs/en/skills the invocation-control table
#     records "Description not in context" for that frontmatter, and "Hide
#     individual skills" states it "removes the skill from Claude's context
#     entirely" — such a skill spends none of the shared description budget,
#     so counting it overstates the aggregate. (Fetched and verified current
#     when this filter was added.)
#   - A consumer's `skillOverrides` can collapse further entries to
#     `"name-only"`, which also frees their description characters. That is
#     consumer settings.json state, not repository content, so a static check
#     cannot observe it — this report is therefore an UPPER bound for any
#     consumer who sets it.
#
# The aggregate budget is inherently a MACHINE-DEPENDENT estimate: it scales
# with the live model's context window and the resolved
# skillListingBudgetFraction, which a consumer's settings.json can override.
# This script therefore never asserts a live value it cannot observe — it
# reports against a documented, overridable default and always exits 0
# (advisory only, never blocking CI or a pre-commit hook). `/doctor` is the
# live, authoritative source for the resolved value and biggest contributors
# on a given machine and model; this script is the static, reproducible
# proxy that runs without a live session.
#
# The default budget (8000 chars) is the harness's own documented fallback —
# SLASH_COMMAND_TOOL_CHAR_BUDGET's schema description: "The budget scales
# dynamically at 1% of the context window, with a fallback of 8000
# characters." That fallback is exactly contextTokens(200000, the
# non-extended-context default) x ~4 chars/token x skillListingBudgetFraction
# (0.01) — the derivation is reconstructed only when an operator supplies a
# context-window override (below); the default asserts nothing beyond the one
# documented number.
#
# Usage:
#   check-listing-budget.sh [<skills-root> ...]
#   check-listing-budget.sh --help
#
# No args: resolves ONE root via the same convention ladder as check-skill.sh
#   (CHECK_SKILL_SKILLS_ROOT, then ${CLAUDE_PROJECT_DIR}/.claude/skills, then
#   <git-root>/.claude/skills when cwd is inside a git repo) — the shape a
#   single consumer project has. Outside a git repo with no override, that is
#   an environment error (exit 2) naming the missing root, not a silent skip.
#   A resolved root that does not exist is reported as "no skills root found".
# One or more args: EVERY explicit root must exist — a missing one is an
#   environment error (exit 2), never a silent skip, because skipping it
#   would omit a whole plugin subtree and report a falsely low aggregate.
#   Explicit roots do not require a git repository (plugin-cache installs are
#   plain directory trees).
# One or more args: each is scanned as an independent skills root and every
#   skill under every root is pooled into ONE shared aggregate. This is how a
#   consumer who installs multiple plugins actually experiences the listing
#   (every loaded skill shares one budget in a live session) — the intended
#   way to gate a marketplace repo, where each plugin owns its own
#   plugins/<plugin>/skills/ root: e.g. `check-listing-budget.sh plugins/*/skills`.
#
# Overrides (never hardcode a resolved value as ground truth — a consumer's
# settings.json can diverge from every documented default below):
#   CHECK_SKILL_LISTING_BUDGET_CHARS    - fixed aggregate budget in characters
#                                          (default 8000; skips the
#                                          token/fraction reconstruction below)
#   CHECK_SKILL_LISTING_CONTEXT_TOKENS  - reconstructs the budget as
#                                          TOKENS x CHARS_PER_TOKEN x FRACTION
#                                          instead of the flat default; set
#                                          this to match a machine's actual
#                                          model context window (e.g. 1000000
#                                          for a 1M-context model)
#   CHECK_SKILL_LISTING_BUDGET_FRACTION - default 0.01 (skillListingBudgetFraction's
#                                          documented default) — set to match
#                                          a machine's configured value
#   CHECK_SKILL_LISTING_CHARS_PER_TOKEN - default 4 — set only if a more
#                                          precise ratio is known
#   CHECK_SKILL_LISTING_MAX_DESC_CHARS  - per-entry truncation cap applied
#                                          before summing (default 1536,
#                                          matching skillListingMaxDescChars'
#                                          documented default) — the harness
#                                          truncates each entry to this cap
#                                          before the aggregate ever sees it
#   CHECK_SKILL_SKILLS_ROOT              - single-root resolution override,
#                                          only consulted in the no-args form
#
# Every numeric override above is validated as a positive number before use.
# A nonnumeric value is an environment error (exit 2) — never a silent
# coercion to zero, which would fabricate a zero-character budget and an
# overflow WARN out of a typo. An accepted integer override is then forced to
# base 10, so a zero-padded value means what it reads as: `08` is 8, not an
# octal error, and `0123` is 123, not 83.
#
# Exit 0 always (report-only), except a usage/env error (exit 2) — this is an
# advisory rollup, not a pass/fail gate; see the "reported aggregate" framing
# in the issue this script closes.
set -uo pipefail

# The header comment block above IS the --help text. Print from line 2 to the
# last consecutive `#` line rather than a hardcoded range, so editing the
# header can never again silently clip or overrun the help output.
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

# Git is optional. Explicit skill-root args (and CHECK_SKILL_SKILLS_ROOT /
# CLAUDE_PROJECT_DIR) work against plain directory trees such as marketplace
# plugin-cache installs. The git toplevel is only the last-resort default root
# when no args and no override are supplied.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
HAVE_GIT=0
if [[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]]; then
  HAVE_GIT=1
fi

# `skill-frontmatter.sh` is deliberately NOT sourced any more. Its helpers are
# per-call `awk`/`tr` execs, which is what made the pooled run unrunnable (see
# the measurement scan below); their behaviour is ported into that scan's single
# awk program instead. `check-skill.sh` remains the library's consumer, so the
# file itself is unchanged and still shared.

# Reject a nonnumeric override up front. Without this, `awk` coerces a typo to
# 0 and the report exits 0 announcing a zero-character budget and a bogus
# overflow, while the bash-arithmetic call sites die with an undocumented
# exit 1. Both failure modes are routed into the documented env error (exit 2).
# `kind` is `int` for counts and `num` for ratios/fractions, which are decimal.
require_positive_number() {
  local name="$1" val="$2" kind="${3:-int}"
  local pattern='^[0-9]+$'
  [[ "$kind" == "num" ]] && pattern='^([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
  if [[ ! "$val" =~ $pattern ]] || ! awk -v v="$val" 'BEGIN { exit (v > 0) ? 0 : 1 }'; then
    printf 'Error: %s must be a positive number, got: %s\n' "$name" "$val" >&2
    exit 2
  fi
}

# Force a validated integer to base 10 before anything treats it as a number.
# `^[0-9]+$` accepts a zero-padded override, which bash arithmetic and
# `printf %d` then read as OCTAL: `0123` silently becomes 83, and `08` is not a
# number at all — it renders the budget as 0 and reports a bogus OK. Applies to
# integer overrides only; the ratio/fraction overrides are decimal (`0.01` is
# the documented default fraction) and reach only awk, which has no octal input.
to_decimal() {
  printf '%s' "$((10#$1))"
}

MAX_DESC_CHARS="${CHECK_SKILL_LISTING_MAX_DESC_CHARS:-1536}"
require_positive_number CHECK_SKILL_LISTING_MAX_DESC_CHARS "$MAX_DESC_CHARS" int
MAX_DESC_CHARS="$(to_decimal "$MAX_DESC_CHARS")"
JOINER_CHARS=3 # the literal " - " the harness inserts between description and when_to_use

# Precedence matches the documented contract above: a fixed aggregate budget
# SKIPS the token/fraction reconstruction. Checking it first is what makes that
# sentence true.
if [[ -n "${CHECK_SKILL_LISTING_BUDGET_CHARS:-}" ]]; then
  BUDGET_CHARS="$CHECK_SKILL_LISTING_BUDGET_CHARS"
  require_positive_number CHECK_SKILL_LISTING_BUDGET_CHARS "$BUDGET_CHARS" int
  BUDGET_CHARS="$(to_decimal "$BUDGET_CHARS")"
  BUDGET_SOURCE="override (CHECK_SKILL_LISTING_BUDGET_CHARS)"
  if [[ -n "${CHECK_SKILL_LISTING_CONTEXT_TOKENS:-}" ]]; then
    printf 'Note: CHECK_SKILL_LISTING_BUDGET_CHARS takes precedence; ignoring CHECK_SKILL_LISTING_CONTEXT_TOKENS=%s\n' \
      "$CHECK_SKILL_LISTING_CONTEXT_TOKENS" >&2
  fi
elif [[ -n "${CHECK_SKILL_LISTING_CONTEXT_TOKENS:-}" ]]; then
  CONTEXT_TOKENS="$CHECK_SKILL_LISTING_CONTEXT_TOKENS"
  CHARS_PER_TOKEN="${CHECK_SKILL_LISTING_CHARS_PER_TOKEN:-4}"
  FRACTION="${CHECK_SKILL_LISTING_BUDGET_FRACTION:-0.01}"
  require_positive_number CHECK_SKILL_LISTING_CONTEXT_TOKENS "$CONTEXT_TOKENS" int
  CONTEXT_TOKENS="$(to_decimal "$CONTEXT_TOKENS")"
  require_positive_number CHECK_SKILL_LISTING_CHARS_PER_TOKEN "$CHARS_PER_TOKEN" num
  require_positive_number CHECK_SKILL_LISTING_BUDGET_FRACTION "$FRACTION" num
  if ! BUDGET_CHARS="$(awk -v t="$CONTEXT_TOKENS" -v c="$CHARS_PER_TOKEN" -v f="$FRACTION" \
    'BEGIN { printf "%d", t * c * f }' 2>/dev/null)" || [[ -z "$BUDGET_CHARS" ]] || ((BUDGET_CHARS <= 0)); then
    printf 'Error: could not compute a budget from CHECK_SKILL_LISTING_CONTEXT_TOKENS=%s CHECK_SKILL_LISTING_CHARS_PER_TOKEN=%s CHECK_SKILL_LISTING_BUDGET_FRACTION=%s\n' \
      "$CONTEXT_TOKENS" "$CHARS_PER_TOKEN" "$FRACTION" >&2
    exit 2
  fi
  BUDGET_SOURCE="reconstructed: $CONTEXT_TOKENS tokens x $CHARS_PER_TOKEN chars/token x $FRACTION"
else
  BUDGET_CHARS=8000
  BUDGET_SOURCE="documented default (SLASH_COMMAND_TOOL_CHAR_BUDGET fallback)"
fi

# --- Resolve the roots to scan ----------------------------------------------

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

# --- Collect every skill under every root -----------------------------------

CONTRIB_FILE="$(mktemp)"
FILE_LIST="$(mktemp)"
trap 'rm -f "$CONTRIB_FILE" "$FILE_LIST"' EXIT

# Enumerate first, measure once. The bash half below only globs and stats — no
# subshell, no exec — and the whole measurement is ONE awk process.
FOUND_ROOTS=0
SKILL_ENTRIES=()
for root in "${ROOTS[@]}"; do
  if [[ ! -d "$root" ]]; then
    # An EXPLICIT root that does not exist is an environment error: silently
    # skipping it omits a whole subtree and reports a falsely low aggregate
    # under an "OK". The no-args resolved root falls through to the
    # "no skills root found" check below instead.
    if ((EXPLICIT_ROOTS)); then
      printf 'Error: skills root does not exist: %s\n' "$root" >&2
      exit 2
    fi
    continue
  fi
  FOUND_ROOTS=$((FOUND_ROOTS + 1))
  for skill_md in "$root"/*/SKILL.md; do
    [[ -f "$skill_md" ]] || continue
    # Root and path travel together rather than the root being re-derived from
    # the path: the report prints the root STRING the caller passed, and a
    # derivation would have to reproduce its exact spelling (trailing slash,
    # relative vs absolute) to stay byte-identical.
    SKILL_ENTRIES+=("$root"$'\t'"$skill_md")
  done
done
if ((${#SKILL_ENTRIES[@]} > 0)); then
  printf '%s\n' "${SKILL_ENTRIES[@]}" >"$FILE_LIST"
fi

# --- One awk pass over every SKILL.md ---------------------------------------
#
# WHY THIS IS ONE PROCESS. A per-file bash loop spends at least eleven forked
# subshells and five external process execs (4x awk, 1x tr) on EVERY SKILL.md,
# on the order of 2,000 spawns for this repo's ~200 skills. Process creation
# costs roughly two orders of magnitude more on Windows than on Linux, so that
# shape takes `check-listing-budget.sh plugins/*/skills` to 289s there and gets
# it KILLED at the 180s foreground limit with zero output, while CI
# (ubuntu-24.04) never surfaces it. That command is verbatim what #2023's
# procedure and .github/recurring-schedule.json instruct an operator to run
# each cycle, so a report-only drift watch would silently produce nothing on
# the one machine where the routine is actually driven (#2216).
#
# PARITY, NOT A REWRITE. The program below reimplements, behaviour for
# behaviour, the four `skill-frontmatter.sh` helpers:
# `skill_frontmatter::extract`, `::field` (including block-scalar unfolding for
# `|` and `>`, and the quote-aware trailing-comment strip with its
# doubled-single-quote case), `::strip_quotes` (ONE outer layer, double OR
# single, never both), and `normalize_bool`/`trim_ws`. Output is byte-identical
# to composing those helpers per file over this repo's tree — aggregate, entry
# count, every per-file contribution row, and the report text — which is the
# property the test suite pins.
#
# Two command-substitution behaviours a shell caller of those helpers gets for
# free are reproduced EXPLICITLY here, because they are load-bearing rather
# than incidental:
#   - `fm="$(skill_frontmatter::extract ...)"` strips trailing NEWLINES from
#     the extracted frontmatter, so trailing blank lines can never append a
#     separator inside a block scalar. Hence the trailing-empty-line drop after
#     collection, and hence an all-blank block counting as no frontmatter.
#   - `"$(skill_frontmatter::field ...)"` strips trailing newlines from the
#     FIELD's value. Hence strip_trailing_nl() on each result. A folded (`>`)
#     scalar joins with SPACES, which command substitution does not strip, so
#     only newlines are removed — not whitespace generally.
#
# The file list arrives on awk's input rather than as operands: awk treats an
# operand containing `=` as a variable assignment, so a path with `=` in it
# would be silently swallowed instead of read.
#
# `disable-model-invocation: true` keeps a skill's description out of the
# model-visible listing entirely, so it spends none of the shared budget —
# counting it would overstate the aggregate. See the header. Deliberately NOT
# folded, exactly as before: YAML 1.1's `yes` / `on` aliases, because the docs
# only ever spell this field `true` and treating a bare `yes` as the boolean
# risks dropping a skill over a value the harness may read as a plain string.
# A pragmatic normalizer for one known field, not a YAML parser.
if ! AWK_RESULT="$(awk -F'\t' \
  -v max="$MAX_DESC_CHARS" -v joiner_chars="$JOINER_CHARS" -v out="$CONTRIB_FILE" '
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
    if (normalize_bool(fm_field("disable-model-invocation")) == "true") next
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

# --- Report ------------------------------------------------------------------

printf 'Shared listing-budget estimate over %d listing-eligible skill(s) across %d root(s):\n' "$ENTRY_COUNT" "$FOUND_ROOTS"
printf '  aggregate: %d chars\n' "$TOTAL"
printf '  budget:    %d chars (%s)\n' "$BUDGET_CHARS" "$BUDGET_SOURCE"

if ((TOTAL > BUDGET_CHARS)); then
  OVERFLOW=$((TOTAL - BUDGET_CHARS))
  MULT="$(awk -v t="$TOTAL" -v b="$BUDGET_CHARS" 'BEGIN { printf "%.1f", t / b }' 2>/dev/null || echo '?')"
  printf 'WARN: aggregate exceeds the budget by %d chars (~%sx over) — Claude Code drops the\n' "$OVERFLOW" "$MULT"
  printf '      least-invoked skills'"'"' descriptions to name-only when this happens live.\n'
  printf '      Biggest contributors (entry chars, skill, root):\n'
  sort -t $'\t' -k1,1nr "$CONTRIB_FILE" | head -10 | while IFS=$'\t' read -r len name root; do
    printf '        %6d  %s  (%s)\n' "$len" "$name" "$root"
  done
  printf '\nCHECK-LISTING-BUDGET: WARN — aggregate %d/%d chars over budget by %s at the configured budget.\n' \
    "$TOTAL" "$BUDGET_CHARS" "$OVERFLOW"
  printf 'This is an estimate against a configurable default, not a live measurement — run\n'
  # shellcheck disable=SC2016  # single quotes deliberate: the backticks are literal, not shell expansion
  printf '`/doctor` in a live session for the authoritative resolved cost and contributors.\n'
else
  printf 'CHECK-LISTING-BUDGET: OK — aggregate %d/%d chars within budget.\n' "$TOTAL" "$BUDGET_CHARS"
fi

exit 0
