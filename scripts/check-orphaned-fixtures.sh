#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

BASELINE="${FIXTURES_BASELINE:-scripts/orphaned-fixtures-baseline.txt}"

mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

entries=()
if [[ -f "$BASELINE" ]]; then
  read_list::into entries "$BASELINE" --comments inline || exit 2
fi

matched_baseline() {
  local path="$1" entry
  for entry in "${entries[@]}"; do
    if [[ "$path" == "$entry" ]]; then
      printf '%s' "$entry"
      return 0
    fi
  done
  return 1
}

plugin_root_of_to() {
  local rest="${2#plugins/}"
  printf -v "$1" 'plugins/%s' "${rest%%/*}"
}

ere_escape_to() {
  local __s="$2" __out="" __c
  local -i __i
  for ((__i = 0; __i < ${#__s}; __i++)); do
    __c="${__s:__i:1}"
    case "$__c" in
    \\ | '.' | '|' | '$' | '(' | ')' | '[' | ']' | '{' | '}' | '?' | '+' | '*' | '^')
      __out+="\\$__c"
      ;;
    *)
      __out+="$__c"
      ;;
    esac
  done
  printf -v "$1" '%s' "$__out"
}

declare -A EVAL_FILES_VALUES
eval_files_values_to() {
  local __dest="$1" __path="$2"
  if [[ "${EVAL_FILES_VALUES[$__path]+x}" == x ]]; then
    printf -v "$__dest" '%s' "${EVAL_FILES_VALUES[$__path]}"
    return
  fi
  local __v=""
  __v="$(jq -r '.. | objects | .files? // empty | .[]? | select(type == "string")' "$__path" 2>/dev/null)" || __v=""
  EVAL_FILES_VALUES[$__path]="$__v"
  printf -v "$__dest" '%s' "$__v"
}

consumed() {
  local fixture="$1"
  local fixtures_dir evals_dir skill_dir evals_json rel base plugin plugin_rel files_values
  local esc_base base_re test_file line
  local -a skill_tests plugin_other_tests

  fixtures_dir="${fixture%/*}"
  while [[ "$fixtures_dir" == */* && "${fixtures_dir##*/}" != "fixtures" ]]; do
    fixtures_dir="${fixtures_dir%/*}"
  done
  evals_dir="${fixtures_dir%/fixtures}"
  skill_dir="${evals_dir%/evals}"
  evals_json="$evals_dir/evals.json"
  rel="${fixture#"$skill_dir"/}"
  base="${fixture##*/}"

  ere_escape_to esc_base "$base"
  # Not grep -w: it ends a word at ".", so valid.json would match valid.json.bak:
  # https://www.gnu.org/software/grep/manual/grep.html#index-_002dw
  base_re="(^|[^A-Za-z0-9._-])${esc_base}([^A-Za-z0-9._-]|$)"

  if [[ -f "$evals_json" ]]; then
    eval_files_values_to files_values "$evals_json"
    if [[ -n "$files_values" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "$rel" ]] && return 0
      done <<<"$files_values"
      if grep -qE -- "$base_re" <<<"$files_values"; then
        return 0
      fi
    fi
  fi

  local seeder esc_stem stem_re
  local -a seeders=() scaffolds=() plugin_scaffolds=()
  plugin_root_of_to plugin "$fixture"
  if [[ "$evals_dir" != "$plugin/evals" ]]; then
    for seeder in "$plugin"/evals/*/scaffold.sh; do
      [[ -f "$seeder" ]] && plugin_scaffolds+=("$seeder")
    done
    if ((${#plugin_scaffolds[@]} > 0)) && grep -qF -- "${fixture#"$fixtures_dir"/}" "${plugin_scaffolds[@]}"; then
      return 0
    fi
  fi
  for seeder in "$evals_dir"/*/scaffold.sh; do
    [[ -f "$seeder" ]] && scaffolds+=("$seeder")
  done
  if ((${#scaffolds[@]} > 0)); then
    seeders=("${scaffolds[@]}")
    for seeder in "$fixtures_dir"/*.sh; do
      [[ -f "$seeder" && "$seeder" != "$fixture" ]] || continue
      grep -qF -- "${seeder##*/}" "${scaffolds[@]}" && seeders+=("$seeder")
    done
  fi
  if ((${#seeders[@]} > 0)); then
    grep -qE -- "$base_re" "${seeders[@]}" && return 0
    if [[ "$base" == *.txt ]]; then
      ere_escape_to esc_stem "${base%.txt}"
      stem_re="(^|[^A-Za-z0-9._-])${esc_stem}([^A-Za-z0-9._-]|$)"
      grep -qE -- "$stem_re" "${seeders[@]}" && return 0
    fi
  fi

  plugin_rel="${fixture#"$plugin"/}"
  skill_tests=()
  plugin_other_tests=()
  for test_file in "${ALL_TEST_FILES[@]}"; do
    [[ -n "$test_file" ]] || continue
    case "$test_file" in
    "$skill_dir"/*) skill_tests+=("$test_file") ;;
    "$plugin"/*) plugin_other_tests+=("$test_file") ;;
    *) ;;
    esac
  done
  if ((${#skill_tests[@]} > 0)) && grep -qE -- "$base_re" "${skill_tests[@]}"; then
    return 0
  fi
  if ((${#plugin_other_tests[@]} > 0)) && grep -qF -- "$plugin_rel" "${plugin_other_tests[@]}"; then
    return 0
  fi

  return 1
}

mapfile -t -d '' fixtures < <(find plugins -type f -path '*/evals/fixtures/*' -print0 2>/dev/null | sort -z)
mapfile -t -d '' ALL_TEST_FILES < <(find plugins -type f -name '*.test.*' -print0 2>/dev/null)

orphans=0
if [[ "$mode" == "discover" ]]; then
  for f in "${fixtures[@]}"; do
    if consumed "$f"; then
      printf '%-14s %s\n' "CONSUMED" "$f"
    elif matched_baseline "$f" >/dev/null; then
      printf '%-14s %s\n' "GRANDFATHERED" "$f"
    else
      printf '%-14s %s\n' "ORPHAN" "$f"
    fi
  done
  exit 0
fi

for f in "${fixtures[@]}"; do
  if consumed "$f"; then
    continue
  fi
  if p="$(matched_baseline "$f")"; then
    read_list::mark_used "$p"
    continue
  fi
  echo "ORPHANED FIXTURE: $f is under evals/fixtures/ but no eval case references it and no test asserts on it." >&2
  echo "  Reference it from a grader (an eval files[] entry or a test), delete it, or grandfather it in $BASELINE with the owning issue." >&2
  orphans=$((orphans + 1))
done

stale=0
read_list::report_stale entries "$BASELINE" 'no longer shadows any orphaned fixture — remove it.' || stale=1

if ((orphans > 0 || stale > 0)); then
  exit 1
fi
echo "No orphaned eval fixtures (every file under **/evals/fixtures/ is consumed by a grader or grandfathered)."
