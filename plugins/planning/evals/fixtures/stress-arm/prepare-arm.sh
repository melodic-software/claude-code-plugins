#!/usr/bin/env bash
# Exit: 0 written; 2 a usage error, or a dest that already exists.
set -euo pipefail

usage() {
  echo "usage: prepare-arm.sh <reviewer|devils-advocate|both|auto> <dest> [--degrade-devils-advocate]" >&2
  exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage
value="$1"
dest="$2"
degrade="${3:-}"
case "$value" in
reviewer | devils-advocate | both | auto) ;;
*) usage ;;
esac
[[ -z "$degrade" || "$degrade" == "--degrade-devils-advocate" ]] || usage
if [[ -e "$dest" ]]; then
  echo "prepare-arm.sh: $dest already exists" >&2
  exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

mkdir -p "$dest"
cp -R "$root/." "$dest/"
rm -rf "${dest:?}/evals/results"

fixture="$dest/evals/fixtures/stress-arm"
printf 'verification: standard\nplan_stress_test:\n  plan: %s\n  proposal: %s\n  incumbent: %s\n' "$value" "$value" "$value" >"$fixture/planning.yaml"

if [[ -n "$degrade" ]]; then
  skill="$dest/skills/devils-advocate/SKILL.md"
  frontmatter="$(awk 'NR == 1 || !done { print } NR > 1 && /^---$/ { done = 1 }' "$skill")"
  printf '%s\n\n' "$frontmatter" >"$skill"
  cat "$fixture/devils-advocate-degraded-body.md.txt" >>"$skill"
fi

echo "$dest"
