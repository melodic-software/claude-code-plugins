#!/usr/bin/env bash
# Run Node suites that sit outside the four sub-projects CI already runs.
#
#   scripts/run-outside-node-suites.sh
#   scripts/run-outside-node-suites.sh --paths FILE
#
# With no arguments, run `npm test` in every directory listed in
# scripts/outside-node-packages.txt. That file is the package's own test
# command, read from package.json "scripts.test". This script does not guess
# node --test versus vitest.
#
# --paths FILE is one repo-relative path per line (the suites affected-tests.sh
# declined). A path is classified, not guessed:
#   * under scripts/outside-node-exclusions.txt: recorded and not run
#   * under a registered package: that package's npm test runs once
#   * *.Tests.ps1: owned by the test-windows Pester lane
#   * under the four sub-projects: owned by their existing CI steps
#   * a sibling *.test.sh wrapper: owned by run-plugin-tests.sh
#   * anything else: exit 1, so a new suite cannot pass having run nothing
#
# Exit 0 when every selected package test passes, or the list names only
# exclusions and suites another lane owns. Exit 1 on a failing package test or
# an unclassified path. Exit 2 on usage.
# shellcheck disable=SC2310
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

PACKAGES_FILE="scripts/outside-node-packages.txt"
EXCLUSIONS_FILE="scripts/outside-node-exclusions.txt"
paths_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths)
    paths_file="${2:?usage: run-outside-node-suites.sh [--paths FILE]}"
    shift 2
    ;;
  *)
    echo "usage: scripts/run-outside-node-suites.sh [--paths FILE]" >&2
    exit 2
    ;;
  esac
done

read_list() {
  local file="$1" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line%"${line##*[![:space:]]}"}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] || continue
    printf '%s\n' "$line"
  done <"$file"
}

mapfile -t packages < <(read_list "$PACKAGES_FILE")
mapfile -t exclusions < <(read_list "$EXCLUSIONS_FILE")

four_prefixes=(
  "plugins/miro/"
  "plugins/ai-briefing/skills/generate/"
  "plugins/knowledge/skills/video-digest/"
  "plugins/knowledge/skills/course-digest/"
)

under_prefix() {
  local path="$1" prefix
  shift
  for prefix in "$@"; do
    [[ "$path" == "$prefix"* ]] && return 0
  done
  return 1
}

package_of() {
  local path="$1" pkg
  for pkg in "${packages[@]}"; do
    [[ "$path" == "$pkg" || "$path" == "$pkg"/* ]] && {
      printf '%s\n' "$pkg"
      return 0
    }
  done
  return 1
}

run_package() {
  local pkg="$1" test_cmd
  if [[ ! -f "$pkg/package.json" ]]; then
    echo "outside-node: $pkg has no package.json" >&2
    return 1
  fi
  test_cmd="$(jq -r '.scripts.test // empty' "$pkg/package.json")"
  if [[ -z "$test_cmd" ]]; then
    echo "outside-node: $pkg/package.json has no scripts.test; refusing to guess a runner" >&2
    return 1
  fi
  echo "outside-node: npm test in $pkg ($test_cmd)"
  (cd "$pkg" && npm test)
}

declare -A selected=()
failed=0

if [[ -z "$paths_file" ]]; then
  for pkg in "${packages[@]}"; do
    selected["$pkg"]=1
  done
else
  [[ -f "$paths_file" ]] || {
    echo "outside-node: paths file not found: $paths_file" >&2
    exit 2
  }
  while IFS= read -r path || [[ -n "$path" ]]; do
    [[ -n "$path" ]] || continue
    if under_prefix "$path" "${exclusions[@]}"; then
      echo "EXCLUDED: $path (eval fixture, not a suite; scripts/outside-node-exclusions.txt)"
      continue
    fi
    if pkg="$(package_of "$path")"; then
      selected["$pkg"]=1
      continue
    fi
    case "$path" in
    *.Tests.ps1)
      echo "PESER: $path is run by the test-windows Pester lane"
      continue
      ;;
    *.test.js) sh_wrapper="${path%.test.js}.test.sh" ;;
    *.test.mjs) sh_wrapper="${path%.test.mjs}.test.sh" ;;
    *.test.cjs) sh_wrapper="${path%.test.cjs}.test.sh" ;;
    *) sh_wrapper="" ;;
    esac
    if under_prefix "$path" "${four_prefixes[@]}"; then
      echo "OWNED: $path is run by its sub-project CI step"
      continue
    fi
    if [[ -n "$sh_wrapper" && -f "$sh_wrapper" ]]; then
      echo "OWNED: $path is run through $sh_wrapper"
      continue
    fi
    echo "outside-node: no package test command for $path" >&2
    failed=1
  done <"$paths_file"
fi

for pkg in "${packages[@]}"; do
  [[ -n "${selected[$pkg]:-}" ]] || continue
  run_package "$pkg" || failed=1
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
echo "outside-node: done"
