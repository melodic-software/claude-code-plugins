#!/usr/bin/env bash
# Resolve the ENFORCEMENT pattern for a source-control convention key
# (`subject_pattern` / `pr_title_pattern`) to a POSIX-ERE regex a hook can hand
# straight to `[[ =~ ]]` or `grep -E`, cross-platform.
#
# WHY THIS EXISTS: the convention surface (`.claude/source-control.md`, one
# `## <key>` H2 per key) is authored for a MODEL to read — its `subject_pattern`
# value may be the keyword `Conventional Commits` or a regex in PCRE dialect
# (`(?:…)`, `\d`). A blocking hook cannot evaluate that: `grep -E` chokes on
# `(?:`, and neither ERE engine knows `\d`. This centralizes the read + the
# dialect normalization once, so `block-noncanonical-commit`, the CC-layer
# content gate, and the opt-in `commit-msg` hook all enforce the SAME pattern
# the SAME way — no per-hook re-fork, no drift.
#
# ENFORCEMENT ≠ DRAFTING — the policy-floor contract:
#   Enforcement reads the TEAM-TRACKED layer ONLY:
#   `${REPO_ROOT}/.claude/source-control.md`. The user-global
#   (`~/.claude/source-control.md`) and gitignored local
#   (`.claude/source-control.local.md`) overlays are DRAFTING inputs the model
#   merges per `reference/config-resolution.md`; a blocking gate never reads
#   them. That is the floor by construction: a personal/gitignored file cannot
#   weaken what the gate enforces because the gate never looks at it, and
#   "is regex A stricter than B" is undecidable so no merge could honor "tighten
#   only" anyway. A team with no tracked pattern gets NO enforcement (never the
#   bundled Conventional Commits default — that default is not lane-1-eligible,
#   so gating an un-opted-in repo against it violates the two-lane posture).
#
# SINGLE SOURCE OF TRUTH: lib/resolve-convention-pattern.sh at the marketplace
# repo root. Copies materialized into consuming plugins exist only because
# installed plugins are cache-isolated and must be self-contained — never edit a
# copy. Edit the source and run scripts/sync-resolve-convention-pattern.sh; CI
# rejects drifted copies. Owner contract: docs/conventions/commit-convention/.
#
# Usage:
#   resolve-convention-pattern.sh <repo_root> <subject_pattern|pr_title_pattern>
#
# Output: the resolved ERE regex on stdout (no trailing newline sensitivity), or
#   NOTHING when the key is unresolved OR resolves to a pattern that cannot be
#   expressed in ERE. A non-enforceable pattern additionally writes a one-line
#   diagnostic to stderr. Exit status:
#     0  a pattern was emitted (enforce it)
#     1  no enforcement (unresolved, or non-ERE-expressible — stdout empty)
#     2  usage error
set -uo pipefail

# The bundled Conventional Commits pattern — the ONE place the `Conventional
# Commits` keyword expands, so the model's interpretation and every hook's regex
# cannot drift. Mirrors /source-control:commit's documented expansion and is
# already pure ERE (capturing groups, no `\d`).
readonly CC_ERE='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+'
# shellcheck disable=SC2016  # backticks are a literal part of the deferral marker, not a substitution
readonly PR_DEFERRAL='Same as `subject_pattern`.'

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi

repo_root="${1:-}"
key="${2:-}"

if [[ -z "$repo_root" || -z "$key" ]]; then
  echo "resolve-convention-pattern: usage: resolve-convention-pattern.sh <repo_root> <subject_pattern|pr_title_pattern>" >&2
  exit 2
fi
case "$key" in
subject_pattern | pr_title_pattern) ;;
*)
  echo "resolve-convention-pattern: key must be subject_pattern or pr_title_pattern, got '$key'" >&2
  exit 2
  ;;
esac

# Team-tracked layer only — the enforcement authority (see header).
readonly TEAM_FILE="$repo_root/.claude/source-control.md"

# First non-empty body line under `## <key>`, CR-stripped. Empty when the
# section is absent or bodyless. Awk over sed: needs section-state, not a line
# match.
h2_value() {
  local file="$1" k="$2"
  [[ -f "$file" ]] || return 0
  awk -v key="$k" '
    BEGIN { in_section = 0 }
    /^##[[:space:]]/ {
      # A new H2 ends the target section.
      hdr = $0; sub(/^##[[:space:]]+/, "", hdr); sub(/[[:space:]]+$/, "", hdr)
      in_section = (hdr == key) ? 1 : 0
      next
    }
    in_section {
      line = $0; gsub(/\r/, "", line)
      if (line ~ /^[[:space:]]*$/) next          # skip blank lines before the value
      sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      print line; exit                            # first non-empty body line wins
    }
  ' "$file"
}

# Enforcement patterns are POSIX ERE, NOT PCRE. The resolver does not translate
# a pattern (translating PCRE->ERE by string rewriting is unsound — bracket
# expressions, POSIX classes, and escaped backslashes all break naive
# substitution); it accepts a value that is already ERE and rejects one that
# uses a PCRE-only construct, so a pattern the ERE engines would misread takes
# the documented no-enforcement path instead of silently enforcing the wrong
# thing. A team wanting a digit class writes `[0-9]`, not `\d`.
is_non_ere() {
  local p="$1"
  # Any `(?...)` group — non-capturing `(?:`, lookaround `(?=`/`(?!`, named
  # `(?<`/`(?P<`. POSIX ERE has none of these.
  [[ "$p" == *'(?'* ]] && return 0
  # Any backslash followed by a letter or digit: the shorthand classes
  # \d \w \s \D \S \W, the anchors \A \Z \z \b \B, control escapes \t \n \r …,
  # and backreferences \1..\9. POSIX ERE reads each as the literal character.
  # A backslash before a metacharacter (`\.`, `\(`, `\+`) is valid ERE and stays
  # allowed.
  [[ "$p" =~ \\[a-zA-Z0-9] ]] && return 0
  return 1
}

# Resolve one key's raw value from the team layer, expanding the CC keyword.
raw_value() {
  local k="$1" v
  v="$(h2_value "$TEAM_FILE" "$k")"
  [[ -n "$v" ]] || return 0
  if [[ "$v" == "Conventional Commits" ]]; then
    printf '%s' "$CC_ERE"
  else
    printf '%s' "$v"
  fi
}

value="$(raw_value "$key")"

# pr_title_pattern deferral: `Same as `subject_pattern`.` enforces the effective
# subject pattern. Resolve against the raw (pre-expansion) pr_title value.
if [[ "$key" == "pr_title_pattern" ]]; then
  raw_pr="$(h2_value "$TEAM_FILE" "pr_title_pattern")"
  if [[ "$raw_pr" == "$PR_DEFERRAL" ]]; then
    value="$(raw_value "subject_pattern")"
  fi
fi

# Unresolved -> no enforcement (exit 1, stdout empty). Never fall back to CC_ERE.
[[ -n "$value" ]] || exit 1

if is_non_ere "$value"; then
  printf '%s\n' "resolve-convention-pattern: $key is not POSIX ERE (a PCRE-only construct: a (?...) group, or a backslash-letter/backslash-digit escape such as \\d \\A \\t \\1); enforcement disabled -- author the pattern in POSIX ERE (e.g. [0-9] not \\d) to enable the gate." >&2
  exit 1
fi

# Safety net: reject anything that still does not compile as POSIX ERE (e.g. an
# unbalanced `^[$`) so a bad config takes the no-enforcement path, never a hook
# that would then error or wrongly block on it. grep -E exits >=2 on an invalid
# expression, 0/1 on a valid one.
grep -E -- "$value" </dev/null >/dev/null 2>&1
if (($? >= 2)); then
  printf '%s\n' "resolve-convention-pattern: $key does not compile as POSIX ERE; enforcement disabled." >&2
  exit 1
fi

printf '%s\n' "$value"
exit 0
