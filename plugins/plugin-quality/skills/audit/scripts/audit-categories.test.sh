#!/usr/bin/env bash
# Pins the three audit categories and which new seams run at low and medium.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/SKILL.md"
AUDITOR="$(cd "$ROOT/../../agents" && pwd)/auditor.md"
FAIL=0

need() {
  local file="$1" needle="$2" label="$3"
  if grep -F -q -- "$needle" "$file"; then
    echo "ok: $label"
  else
    echo "FAIL: $label" >&2
    FAIL=$((FAIL + 1))
  fi
}

need "$SKILL" "**errors**" "skill names errors"
need "$SKILL" "**improvements**" "skill names improvements"
need "$SKILL" "**quality-of-life**" "skill names quality-of-life"
need "$SKILL" "standards-alignment" "skill names the standards seam"
need "$SKILL" "finding-sample" "skill names the finding-sample seam"
need "$SKILL" "open question" "an unmet research bar is an open question"
need "$SKILL" 'convention home unresolved' "unresolved convention home is stated"
need "$AUDITOR" "errors:" "auditor return opens with errors"
need "$AUDITOR" "improvements:" "auditor return opens with improvements"
need "$AUDITOR" "quality-of-life:" "auditor return opens with quality-of-life"
need "$AUDITOR" "nothing found" "an empty category is stated"

# low runs standards-alignment and skips research; medium runs research and the sample.
low=$(awk '/^\| `low` /{print; exit}' "$SKILL")
med=$(awk '/^\| `medium` /{print; exit}' "$SKILL")
need <(printf '%s\n' "$low") "standards-alignment" "low runs standards-alignment"
if [[ "$low" == *"research seam and the finding-sample seam are skipped"* ]]; then
  echo "ok: low skips research and the finding sample"
else
  echo "FAIL: low row does not skip research and the finding sample: $low" >&2
  FAIL=$((FAIL + 1))
fi
need <(printf '%s\n' "$med") "research seam" "medium runs research"
need <(printf '%s\n' "$med") "finding-sample" "medium runs the finding sample"

for lens in "$ROOT"/reference/component-types/*.md; do
  need "$lens" "## Categories" "$(basename "$lens") has a Categories section"
  need "$lens" "quality-of-life" "$(basename "$lens") names quality-of-life"
done

echo "FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
