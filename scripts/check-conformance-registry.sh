#!/usr/bin/env bash
# Check that every row of docs/conformance-dimensions.md points at things that
# exist, so the conformance registry cannot cite a check nobody runs.
#
#   scripts/check-conformance-registry.sh          discover: list every finding
#   scripts/check-conformance-registry.sh --check  same, explicit gate form
#
# A row is `| id | concern | owner | lane | checks | ci | scope |`. Per row:
#
#   - `id` is unique; `lane` and `checks` are non-empty (a row nobody runs is
#     the phantom citation this registry replaces);
#   - `owner` is `path#Heading text`: the file exists and holds that text as a
#     level-2 or level-3 heading (matched as text, never used as a link anchor);
#   - every repo path in `lane` or `checks` (scripts/, plugins/, docs/,
#     .github/ with an extension) exists;
#   - every backticked `/plugin:leaf` in `checks` resolves to
#     plugins/<plugin>/skills/<leaf>/SKILL.md, and `/leaf` to
#     .claude/skills/<leaf>/SKILL.md;
#   - `ci` is yes, indirect or no; `yes` means .github/workflows/pr-require-checks.yml names
#     every scripts/ path in `checks`;
#   - `scope` is plugin or fleet.
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one `registry: id: reason` finding per line on stderr, the
# clean-run statement on stdout. Exit: 0 clean, 1 any finding, 2 environment
# or usage (registry missing, bad argument).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

REGISTRY=docs/conformance-dimensions.md
CI_FILE=.github/workflows/pr-require-checks.yml
if [[ ! -f "$REGISTRY" ]]; then
  printf 'check-conformance-registry: %s not found, nothing inspected\n' "$REGISTRY" >&2
  exit 2
fi

findings=()
finding() { findings+=("$REGISTRY: $1: $2"); }
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

declare -A seen=()
rows=0
while IFS= read -r line; do
  [[ "$line" == '| dim-'* ]] || continue
  rows=$((rows + 1))
  IFS='|' read -r _ id _ owner lane checks ci scope _ <<<"$line"
  id="$(trim "$id")" owner="$(trim "$owner")" lane="$(trim "$lane")"
  checks="$(trim "$checks")" ci="$(trim "$ci")" scope="$(trim "$scope")"

  [[ -n "${seen[$id]:-}" ]] && finding "$id" "duplicate id"
  seen[$id]=1
  [[ -z "$lane" ]] && finding "$id" "empty lane"
  [[ -z "$checks" ]] && finding "$id" "empty checks"

  if [[ "$owner" != *'#'* ]]; then
    finding "$id" "owner '$owner' is not path#Heading"
  else
    owner_file="${owner%%#*}" owner_head="${owner#*#}"
    if [[ ! -f "$owner_file" ]]; then
      finding "$id" "owner file $owner_file not found"
    elif ! grep -qFx -e "## $owner_head" -e "### $owner_head" "$owner_file"; then
      finding "$id" "owner heading '$owner_head' not in $owner_file"
    fi
  fi

  while IFS= read -r path; do
    [[ -e "$path" ]] || finding "$id" "path $path not found"
  done < <(grep -oE '(scripts|plugins|docs|\.github)/[A-Za-z0-9_./-]*\.[a-z]+' <<<"$lane $checks" || true)

  while IFS= read -r ref; do
    ref="${ref//\`/}"
    if [[ "$ref" =~ ^/([a-z0-9-]+):([a-z0-9-]+)$ ]]; then
      [[ -f "plugins/${BASH_REMATCH[1]}/skills/${BASH_REMATCH[2]}/SKILL.md" ]] ||
        finding "$id" "skill $ref not found"
    elif [[ "$ref" =~ ^/([a-z0-9-]+)$ ]]; then
      [[ -f ".claude/skills/${BASH_REMATCH[1]}/SKILL.md" ]] ||
        finding "$id" "skill $ref not found"
    fi
  done < <(grep -oE "\`[^\`]+\`" <<<"$checks" || true)

  case "$ci" in
  yes)
    while IFS= read -r path; do
      grep -qF -- "$path" "$CI_FILE" 2>/dev/null || finding "$id" "ci is yes but $CI_FILE does not run $path"
    done < <(grep -oE 'scripts/[A-Za-z0-9_./-]*\.[a-z]+' <<<"$checks" || true)
    ;;
  indirect | no) ;;
  *) finding "$id" "ci '$ci' is not yes, indirect or no" ;;
  esac

  case "$scope" in
  plugin | fleet) ;;
  *) finding "$id" "scope '$scope' is not plugin or fleet" ;;
  esac
done <"$REGISTRY"

((rows > 0)) || finding "registry" "no rows"

if ((${#findings[@]} > 0)); then
  printf '%s\n' "${findings[@]}" >&2
  exit 1
fi
printf 'check-conformance-registry: %d rows, every owner, path and skill resolves\n' "$rows"
