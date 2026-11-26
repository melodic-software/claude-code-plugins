# shellcheck shell=bash
# shellcheck source=org-standards-test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/org-standards-test-helpers.sh"

ADOPTED_ID=composition-over-inheritance
adopted_tree() {
  printf -- '---\nstandards-contract: 1.3.1\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| design | any design decision | design.md |\n' \
    >"$1/docs/standards/README.md"
  printf -- "- Prefer composition over inheritance (\`%s\`).\n" "$ADOPTED_ID" >"$1/docs/standards/design.md"
}
publish_tree acme/adopted adopted_tree
ADOPTED=$(head_of acme/adopted)
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/adopted\n'
STAGE_REPO=$(target stage-repo 'pr_open_state: ready\n')

paragraph_with() {
  local file="$1"
  shift
  awk -v want="$(printf '%s\034' "$@")" '
    BEGIN { RS = ""; n = split(want, w, "\034") - 1 }
    { gsub(/[[:space:]]+/, " "); hit = 1; for (i = 1; i <= n; i++) if (index($0, w[i]) == 0) hit = 0; if (hit) found = 1 }
    END { exit !found }
  ' "$file"
}

check_stage() {
  local plugin="$SCRIPT_DIR/../plugins/$1" stage="$1/$2" layer checkout index
  IFS=$'\t' read -r layer checkout index < <(bash "$plugin/scripts/org-standards.sh" subscriptions --root "$STAGE_REPO" 2>/dev/null)
  assert_eq "$stage: the plugin's org-standards.sh copy prints the subscribed layer" "acme/adopted@$ADOPTED" "${layer:-}"
  assert_eq "$stage: the printed index lists the adopted standards file inside the layer's checkout" 1 \
    "$(grep -cxF "| design | any design decision | ${checkout:-none}/docs/standards/design.md |" "${index:-/dev/null}" 2>/dev/null)"
  assert_eq "$stage: the listed file holds the adopted concept id" 1 \
    "$(grep -cF "\`$ADOPTED_ID\`" "${checkout:-none}/docs/standards/design.md" 2>/dev/null)"
  assert_eq "$stage: the plugin's binding copy carries the Resolution ladder and its adopted-concepts rule" "yes|yes" \
    "$(grep -qx '## Resolution ladder' "$plugin/reference/standards-contract.md" 2>/dev/null && echo yes)|$(grep -qF '**Adopted shipped concepts' "$plugin/reference/standards-contract.md" 2>/dev/null && echo yes)"
  assert_eq "$stage: the skill body points at the binding's Resolution ladder" yes \
    "$(paragraph_with "$plugin/$2" 'reference/standards-contract.md' 'Resolution ladder' && echo yes)"
  assert_eq "$stage: the skill body points at the binding's adopted-concepts rule, the plugin marked (if enabled)" yes \
    "$(paragraph_with "$plugin/$2" 'Adopted shipped concepts' '/engineering-concepts:lookup` (if enabled)' && echo yes)"
}
