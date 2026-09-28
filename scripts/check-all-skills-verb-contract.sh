#!/usr/bin/env bash
# Run skill-quality check 25 (description/verb-contract polarity) across every
# marketplace skill. Changed-file scoping in check-changed-skills.sh only
# guards skills a PR touches; this job keeps the full corpus green (#4586).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

CHECKER="${CHECK_SKILL_BIN:-plugins/skill-quality/scripts/check-skill.sh}"
if [[ ! -f "$CHECKER" ]]; then
  printf 'Error: skill checker not found: %s\n' "$CHECKER" >&2
  exit 2
fi

failed=0
checked=0
while IFS= read -r skill_md; do
  skill_dir="$(dirname "$skill_md")"
  checked=$((checked + 1))
  out="$(CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash "$CHECKER" "$skill_dir" 2>&1)" || true
  if grep -q 'description/verb-contract mismatch' <<<"$out"; then
    printf 'FAIL: %s\n' "$skill_dir" >&2
    grep 'description/verb-contract mismatch' <<<"$out" >&2 || true
    failed=$((failed + 1))
  fi
done < <(find plugins -path '*/skills/*/SKILL.md' | sort)

if ((failed > 0)); then
  printf 'check-all-skills-verb-contract: %d/%d skill(s) failed check 25\n' "$failed" "$checked" >&2
  exit 1
fi
printf 'check-all-skills-verb-contract: PASS (%d skills)\n' "$checked"
exit 0
