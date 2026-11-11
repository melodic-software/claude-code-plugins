#!/usr/bin/env bash
# Check, online, the external links a pull request adds or changes in markdown.
#
#   check-changed-links-online.sh [--list] <base-ref>
#
# Reads the added lines of `git diff <base-ref>...HEAD` in tracked .md files,
# takes every http(s) URL on them, and runs lychee with the network on over
# just those, through lychee.toml (its accept list keeps a 429, a 5xx or a
# timeout from failing; its excludes and remaps apply). The offline lane checks
# local files and anchors; the weekly online run catches drift after merge.
# --list prints the URLs and runs nothing. LYCHEE names the binary (default
# lychee); LYCHEE_CONFIG the ruleset (default lychee.toml).
set -euo pipefail

list=0
if [[ ${1:-} == --list ]]; then
  list=1
  shift
fi
if [[ $# -ne 1 || -z $1 ]]; then
  echo "usage: $0 [--list] <base-ref>" >&2
  exit 2
fi
base=$1

# Test data whose links are meant not to resolve, as the offline lane excludes.
mapfile -t urls < <(
  git diff -U0 --no-color --no-ext-diff --dst-prefix=b/ "$base...HEAD" -- '*.md' \
    ':(exclude)plugins/attribution/skills/audit/evals/fixtures/golden/**' \
    ':(exclude)scripts/fixtures/hooks-lifecycle-table.md' |
    grep -vE '^\+\+\+ (b/|/dev/null)' | sed -n 's/^+//p' |
    grep -oE 'https?://[^][[:space:]<>()"`'"'"']+' |
    sed -E 's/[.,;:!?*_]+$//' |
    LC_ALL=C sort -u || true
)

if ((list)); then
  ((${#urls[@]})) && printf '%s\n' "${urls[@]}"
  exit 0
fi
if ((${#urls[@]} == 0)); then
  echo "No external links added or changed in markdown."
  exit 0
fi

echo "Checking ${#urls[@]} added or changed external link(s) online."
input=$(mktemp --suffix=.md)
trap 'rm -f "$input"' EXIT
printf '<%s>\n' "${urls[@]}" >"$input"
"${LYCHEE:-lychee}" --no-progress --config "${LYCHEE_CONFIG:-lychee.toml}" "$input"
