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
#   <git-root>/.claude/skills) — the shape a single consumer project has.
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
# Exit 0 always (report-only), except a usage/env error (exit 2) — this is an
# advisory rollup, not a pass/fail gate; see the "reported aggregate" framing
# in the issue this script closes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  sed -n '2,80p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT" ]]; then
  printf 'Error: not in a git repo\n' >&2
  exit 2
fi

# shellcheck source=./skill-frontmatter.sh
source "$SCRIPT_DIR/skill-frontmatter.sh"

MAX_DESC_CHARS="${CHECK_SKILL_LISTING_MAX_DESC_CHARS:-1536}"
JOINER_CHARS=3 # the literal " - " the harness inserts between description and when_to_use

if [[ -n "${CHECK_SKILL_LISTING_CONTEXT_TOKENS:-}" ]]; then
  CONTEXT_TOKENS="$CHECK_SKILL_LISTING_CONTEXT_TOKENS"
  CHARS_PER_TOKEN="${CHECK_SKILL_LISTING_CHARS_PER_TOKEN:-4}"
  FRACTION="${CHECK_SKILL_LISTING_BUDGET_FRACTION:-0.01}"
  if ! BUDGET_CHARS="$(awk -v t="$CONTEXT_TOKENS" -v c="$CHARS_PER_TOKEN" -v f="$FRACTION" \
    'BEGIN { printf "%d", t * c * f }' 2>/dev/null)" || [[ -z "$BUDGET_CHARS" ]]; then
    printf 'Error: could not compute a budget from CHECK_SKILL_LISTING_CONTEXT_TOKENS=%s CHECK_SKILL_LISTING_CHARS_PER_TOKEN=%s CHECK_SKILL_LISTING_BUDGET_FRACTION=%s\n' \
      "$CONTEXT_TOKENS" "$CHARS_PER_TOKEN" "$FRACTION" >&2
    exit 2
  fi
  BUDGET_SOURCE="reconstructed: $CONTEXT_TOKENS tokens x $CHARS_PER_TOKEN chars/token x $FRACTION"
else
  BUDGET_CHARS="${CHECK_SKILL_LISTING_BUDGET_CHARS:-8000}"
  BUDGET_SOURCE="documented default (SLASH_COMMAND_TOOL_CHAR_BUDGET fallback)"
fi

# --- Resolve the roots to scan ----------------------------------------------

ROOTS=()
if (($# > 0)); then
  ROOTS=("$@")
else
  if [[ -n "${CHECK_SKILL_SKILLS_ROOT:-}" ]]; then
    SINGLE_ROOT="$CHECK_SKILL_SKILLS_ROOT"
  elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    SINGLE_ROOT="$CLAUDE_PROJECT_DIR/.claude/skills"
  else
    SINGLE_ROOT="$REPO_ROOT/.claude/skills"
  fi
  if [[ "$SINGLE_ROOT" != /* && ! "$SINGLE_ROOT" =~ ^[A-Za-z]:[\\/] ]]; then
    SINGLE_ROOT="${CLAUDE_PROJECT_DIR:-$REPO_ROOT}/$SINGLE_ROOT"
  fi
  ROOTS=("$SINGLE_ROOT")
fi

# --- Collect every skill under every root -----------------------------------

TOTAL=0
ENTRY_COUNT=0
CONTRIB_FILE="$(mktemp)"
trap 'rm -f "$CONTRIB_FILE"' EXIT

found_any_root=0
for root in "${ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  found_any_root=1
  for skill_md in "$root"/*/SKILL.md; do
    [[ -f "$skill_md" ]] || continue
    skill_name="${skill_md%/SKILL.md}"
    skill_name="${skill_name##*/}"
    fm="$(skill_frontmatter::extract <"$skill_md")"
    [[ -n "$fm" ]] || continue
    desc="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$fm")")"
    wtu="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field when_to_use <<<"$fm")")"
    desc_len=${#desc}
    wtu_len=${#wtu}
    joiner=0
    ((wtu_len > 0)) && joiner=$JOINER_CHARS
    entry_len=$((desc_len + joiner + wtu_len))
    # The harness truncates each entry to the per-skill cap BEFORE the shared
    # budget ever sees it — mirror that here so an already-oversized single
    # entry (check 2's own FAIL) does not inflate this aggregate beyond what
    # Claude Code would actually load.
    ((entry_len > MAX_DESC_CHARS)) && entry_len=$MAX_DESC_CHARS
    TOTAL=$((TOTAL + entry_len))
    ENTRY_COUNT=$((ENTRY_COUNT + 1))
    printf '%d\t%s\t%s\n' "$entry_len" "$skill_name" "$root" >>"$CONTRIB_FILE"
  done
done

if ((found_any_root == 0)); then
  printf 'Error: no skills root found among: %s\n' "${ROOTS[*]}" >&2
  exit 2
fi

if ((ENTRY_COUNT == 0)); then
  printf 'No skills found under: %s\n' "${ROOTS[*]}"
  printf '\nCHECK-LISTING-BUDGET: 0 skills, nothing to report\n'
  exit 0
fi

# --- Report ------------------------------------------------------------------

printf 'Shared listing-budget estimate over %d skill(s) across %d root(s):\n' "$ENTRY_COUNT" "${#ROOTS[@]}"
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
