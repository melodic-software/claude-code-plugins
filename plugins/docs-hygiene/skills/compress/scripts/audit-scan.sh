#!/usr/bin/env bash
# Mechanical audit scan for /docs-hygiene:compress audit action.
# Implements the six-signal heuristic in context/target-types.md as a script
# so runs do not re-implement awk/grep counting in-session (auditor M7).
#
# Output: one markdown table row per file, then an aggregate line.
# Exit: 0 on scan paths; 2 on unknown args.
set -uo pipefail

usage() {
  cat <<'EOF'
audit-scan.sh — classify markdown targets SKIP/COMPRESS/UNCERTAIN.

Usage:
  audit-scan.sh <file.md>...
  audit-scan.sh --help

Exit: 0 on scan, 2 on unknown arguments.
EOF
}

TARGETS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    echo "audit-scan.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  *)
    TARGETS+=("$1")
    shift
    ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "audit-scan.sh: pass one or more .md paths" >&2
  exit 2
fi

# Curated flavor-token list for signal 6 — OWNED here (superset/subset of
# Phase A LATITUDE; not claimed to be identical). Keep in sync intentionally.
FLAVOR_RE='just|really|basically|actually|simply|perhaps|somewhat|very|quite|might|in order to|due to the fact that|make use of|it is important to|note that|keep in mind'

is_signal1_path() {
  local f="$1" base
  base="$(basename "$f")"
  [[ "$f" == *'/.claude/rules/'* ]] && return 0
  [[ "$base" == 'AGENTS.md' || "$base" == 'CLAUDE.md' || "$base" == 'SKILL.md' ]] && return 0
  return 1
}

word_count() {
  # Floor small files: densities on <50 words are unstable.
  local n
  n=$(wc -w <"$1" | tr -d ' ')
  if [[ "$n" -lt 50 ]]; then
    echo 50
  else
    echo "$n"
  fi
}

classify_file() {
  local file="$1"
  local words tick_pairs path_hits flavor_hits
  if [[ ! -f "$file" ]]; then
    # shellcheck disable=SC2016 # intentional backticks in markdown table cells
    printf '| `%s` | — | SKIP | reason=missing |\n' "$file"
    return 0
  fi
  words=$(word_count "$file")

  if is_signal1_path "$file"; then
    # shellcheck disable=SC2016 # intentional backticks in markdown table cells
    printf '| `%s` | ≤3%% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3%% diff |\n' "$file"
    return 0
  fi
  if grep -Fq 'Prose compression discipline' "$file" 2>/dev/null; then
    # shellcheck disable=SC2016 # intentional backticks in markdown table cells
    printf '| `%s` | ≤3%% | SKIP | author-time-disciplined; signal 4 cite; empirical baseline 3/3 reverted; use `--force` only for targeted sub-3%% diff |\n' "$file"
    return 0
  fi

  tick_pairs=$(grep -o '`' "$file" 2>/dev/null | wc -l | tr -d ' ')
  tick_pairs=$((tick_pairs / 2))
  path_hits=$(grep -Eoc '(@|[a-z][a-z0-9._/-]+\.(md|cs|sh|json|yaml))' "$file" 2>/dev/null || echo 0)
  path_hits=${path_hits//$'\n'/}
  flavor_hits=$(grep -oiwE "$FLAVOR_RE" "$file" 2>/dev/null | wc -l | tr -d ' ')

  local tick_dens path_dens flavor_dens
  tick_dens=$((tick_pairs * 1000 / words))
  path_dens=$((path_hits * 1000 / words))
  flavor_dens=$((flavor_hits * 1000 / words))

  if [[ "$flavor_dens" -lt 5 ]]; then
    # shellcheck disable=SC2016 # intentional backticks in markdown table cells
    printf '| `%s` | ≤3%% | SKIP | flavor-token density %s/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4%% |\n' "$file" "$flavor_dens"
    return 0
  fi
  if [[ "$tick_dens" -gt 10 || "$path_dens" -gt 8 ]]; then
    # shellcheck disable=SC2016 # intentional backticks in markdown table cells
    printf '| `%s` | 3-7%% | UNCERTAIN | inline-code density %s/kw AND/OR cross-ref density %s/kw; flavor band narrow |\n' "$file" "$tick_dens" "$path_dens"
    return 0
  fi
  # shellcheck disable=SC2016 # intentional backticks in markdown table cells
  printf '| `%s` | 5-15%% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |\n' "$file"
}

printf '| target | expected_yield_pct | classify | reason |\n'
printf '|---|---|---|---|\n'

skips=0 compress=0 uncertain=0
mapfile -t SORTED < <(printf '%s\n' "${TARGETS[@]}" | LC_ALL=C sort -u)
rows=()
for f in "${SORTED[@]}"; do
  row="$(classify_file "$f")"
  rows+=("$row")
  case "$row" in
  *'| SKIP |'*) skips=$((skips + 1)) ;;
  *'| COMPRESS |'*) compress=$((compress + 1)) ;;
  *'| UNCERTAIN |'*) uncertain=$((uncertain + 1)) ;;
  *) ;;
  esac
done
printf '%s\n' "${rows[@]}"
printf '\nTotal: %s skips, %s compress-recommended, %s uncertain\n' "$skips" "$compress" "$uncertain"
exit 0
