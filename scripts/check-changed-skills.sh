#!/usr/bin/env bash
# Deterministic skill-regression gate for the skills a PR changes.
#
#   scripts/check-changed-skills.sh <base-ref>
#
# For every skill under plugins/*/skills/** touched vs <base-ref>, run the
# skill-quality static contract gate (plugins/skill-quality/scripts/check-skill.sh
# — trigger-keyword preservation vs the base ref, frontmatter, listing-budget
# and line caps, broken internal refs, evals presence, committed artifacts).
# Any FAIL fails this gate. It replaces the work lane's manual high-blast-radius
# skill-diff read with a deterministic check, and is the first lane to invoke the
# otherwise-uninvoked skill-quality checker.
#
# <base-ref> (e.g. origin/main) is BOTH the changed-file diff base and
# CHECK_SKILL_BASE_REF, so the checker's git-backed checks compare the PR head
# against the same base a reviewer would — a rewrite that silently drops a
# `description` trigger phrase is caught here, not at merge.
#
# markdownlint (check 6) is skipped here (CHECK_SKILL_SKIP_MARKDOWNLINT=1):
# SKILL.md markdown is already gated by the hygiene lane's markdown check, and
# `npx --no-install markdownlint-cli2` would only WARN-skip on a hosted runner
# without the package. Eval-schema validation (validate-evals) is a separate CI
# step — the check-jsonschema composite action over every evals.json.
#
# Exit 0 = every changed skill passes (or none changed); 1 = one or more failed;
# 2 = usage / environment error (fail closed — never a silent skip).
#
# CHECK_SKILL_BIN overrides the checker path (test injection).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

BASE="${1:?usage: check-changed-skills.sh <base-ref>}"

if ! git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
  printf 'Error: base ref %s is not a valid commit\n' "$BASE" >&2
  exit 2
fi

CHECKER="${CHECK_SKILL_BIN:-plugins/skill-quality/scripts/check-skill.sh}"
if [[ ! -f "$CHECKER" ]]; then
  printf 'Error: skill checker not found: %s\n' "$CHECKER" >&2
  exit 2
fi

# Changed skill dirs, mapped from any touched path (including vendor/ subtrees)
# to the owning plugins/<plugin>/skills/<skill> dir and de-duplicated.
mapfile -t changed < <(
  git diff --name-only "$BASE" -- 'plugins/' |
    sed -nE 's#^(plugins/[^/]+/skills/[^/]+)/.*#\1#p' |
    sort -u
)

checked=0
failed=0

for skill_dir in "${changed[@]}"; do
  # A deletion/rename-away leaves no SKILL.md in the tree — not a regression to
  # gate (and the checker would FAIL "not found"). Skip those.
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  skills_root="${skill_dir%/*}" # plugins/<plugin>/skills
  skill_name="${skill_dir##*/}" # <skill>
  checked=$((checked + 1))
  printf '=== %s ===\n' "$skill_dir"
  if CHECK_SKILL_SKILLS_ROOT="$PWD/$skills_root" \
    CHECK_SKILL_BASE_REF="$BASE" \
    CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
    bash "$CHECKER" "$skill_name"; then
    :
  else
    failed=$((failed + 1))
  fi
done

if ((checked == 0)); then
  echo "No changed skills under plugins/*/skills/ — nothing to gate."
  exit 0
fi

printf '\n%d skill(s) checked, %d failed.\n' "$checked" "$failed"
((failed == 0))
