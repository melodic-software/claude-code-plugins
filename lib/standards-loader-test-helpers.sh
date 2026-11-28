# shellcheck shell=bash
# shellcheck source=org-standards-test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/org-standards-test-helpers.sh"

layered_tree() {
  mkdir -p "$1/docs/conventions" "$1/guidance"
  printf 'guidance_dir: guidance\n' >"$1/docs/conventions/standards.yaml"
  printf -- '---\nstandards-contract: 2.0.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| design | any design decision | design.md |\n' \
    >"$1/docs/standards/README.md"
  printf -- '- Prefer composition over inheritance.\n' >"$1/docs/standards/design.md"
  printf -- '---\nstandards-contract: 2.0.0\n---\n\n| Surface | Applies when | File |\n|---|---|---|\n| design.coupling | splitting modules | coupling.md |\n' \
    >"$1/guidance/README.md"
  printf -- '- Weigh coupling before splitting a module.\n' >"$1/guidance/coupling.md"
}
publish_tree acme/layered layered_tree
LAYERED=$(head_of acme/layered)
user_index $'trusted_owners:\n  - acme\nstandards_repositories:\n  - repo: acme/layered\n'
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
  local plugin="$SCRIPT_DIR/../plugins/$1" stage="$1/$2" layer checkout index guidance
  IFS=$'\t' read -r layer checkout index guidance < <(bash "$plugin/scripts/org-standards.sh" subscriptions --root "$STAGE_REPO" 2>/dev/null)
  assert_eq "$stage: the plugin's org-standards.sh copy prints the subscribed layer" "acme/layered@$LAYERED" "${layer:-}"
  assert_eq "$stage: the printed index lists the standards file inside the layer's checkout" 1 \
    "$(grep -cxF "| design | any design decision | ${checkout:-none}/docs/standards/design.md |" "${index:-/dev/null}" 2>/dev/null)"
  assert_eq "$stage: the fourth field is the layer's printed guidance index, marked kind: guidance, listing its file inside the checkout" "1|1" \
    "$(grep -cx 'kind: guidance' "${guidance:-/dev/null}" 2>/dev/null)|$(grep -cxF "| design.coupling | splitting modules | ${checkout:-none}/guidance/coupling.md |" "${guidance:-/dev/null}" 2>/dev/null)"
  assert_eq "$stage: the plugin's binding copy carries the Resolution ladder and its guidance rule" "yes|yes" \
    "$(grep -qx '## Resolution ladder' "$plugin/reference/standards-contract.md" 2>/dev/null && echo yes)|$(grep -qF '**Guidance layer (every rung)' "$plugin/reference/standards-contract.md" 2>/dev/null && echo yes)"
  assert_eq "$stage: the skill body points at the binding's Resolution ladder" yes \
    "$(paragraph_with "$plugin/$2" 'reference/standards-contract.md' 'Resolution ladder' && echo yes)"
  assert_eq "$stage: the skill body points at the binding's guidance rule" yes \
    "$(paragraph_with "$plugin/$2" '"Guidance layer (every rung)"' && echo yes)"
}
