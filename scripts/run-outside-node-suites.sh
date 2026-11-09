#!/usr/bin/env bash
# Run Node suites that sit outside the sub-projects CI already runs
# (scripts/node-subprojects.txt).
#
#   scripts/run-outside-node-suites.sh
#   scripts/run-outside-node-suites.sh --paths FILE
#
# With no arguments, run `npm test` in every directory listed in
# scripts/outside-node-packages.txt. That file is the package's own test
# command, read from package.json "scripts.test". This script does not guess
# node --test versus vitest. A package's `file:` dependency that has a lockfile
# is installed (`npm ci`) before its tests run. Git reads a fixed test config in
# place of the host's (scripts/lib/test-git-env.sh).
#
# --paths FILE is one repo-relative path per line (the suites affected-tests.sh
# declined). A path is classified, not guessed:
#   * under scripts/outside-node-exclusions.txt: recorded and not run
#   * under a registered package: that package's npm test runs once
#   * *.Tests.ps1: owned by the test-windows Pester lane
#   * under a sub-project owner directory: owned by its existing CI step
#   * a sibling *.test.sh wrapper: owned by run-plugin-tests.sh
#   * anything else: exit 1, so a new suite cannot pass having run nothing
#
# Exit 0 when every selected package test passes, or the list names only
# exclusions and suites another lane owns. Exit 1 on a failing package test or
# an unclassified path. Exit 2 on usage or a missing list file.
# shellcheck disable=SC2310
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# shellcheck source=lib/test-git-env.sh
. scripts/lib/test-git-env.sh
# shellcheck source=lib/read-list.sh
. scripts/lib/read-list.sh || exit 2

PACKAGES_FILE="scripts/outside-node-packages.txt"
EXCLUSIONS_FILE="scripts/outside-node-exclusions.txt"
SUBPROJECTS_FILE="scripts/node-subprojects.txt"
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

# Assigned through a nameref, which shellcheck cannot follow (SC2154).
packages=() exclusions=() subprojects=() subproject_owners=()
read_list::into packages "$PACKAGES_FILE" --comments inline || exit 2
read_list::into exclusions "$EXCLUSIONS_FILE" --comments inline || exit 2
read_list::into subprojects "$SUBPROJECTS_FILE" --comments inline || exit 2
# Each row is `<package> <owner> [<trigger>...]`; only the owner directory matters here.
for row in ${subprojects[@]+"${subprojects[@]}"}; do
  owner=""
  read -r _ owner _ <<<"$row"
  [[ -n "$owner" ]] || {
    echo "outside-node: $SUBPROJECTS_FILE row has no owner directory: $row" >&2
    exit 2
  }
  subproject_owners+=("$owner")
done

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
  install_locked_deps "$pkg" || return 1
  echo "outside-node: npm test in $pkg ($test_cmd)"
  (test_git_env::isolate "$git_config" && cd "$pkg" && npm test)
}

# install_locked_deps <pkg>: `npm ci` each `file:` dependency of <pkg> that has
# a lockfile, once per run, so a suite that loads modules from it finds them.
install_locked_deps() {
  local dep dir
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    dir="$(cd "$1/$dep" && pwd)" || return 1
    [[ -f "$dir/package-lock.json" && -z "${installed[$dir]:-}" ]] || continue
    installed["$dir"]=1
    echo "outside-node: npm ci in $dir, a file: dependency of $1"
    npm ci --ignore-scripts --prefix "$dir" || return 1
  done < <(jq -r '[.dependencies, .devDependencies] | map(. // {}) | add | to_entries[]
      | select(.value | startswith("file:")) | .value | ltrimstr("file:")' "$1/package.json" | tr -d '\r')
}

git_config=$(mktemp)
trap 'rm -f "$git_config"' EXIT
declare -A selected=() installed=()
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
    *.test.js | *.test.mjs | *.test.cjs) sh_wrapper="${path%.test.*}.test.sh" ;;
    *) sh_wrapper="" ;;
    esac
    if under_prefix "$path" ${subproject_owners[@]+"${subproject_owners[@]}"}; then
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

((failed == 0)) || exit 1
echo "outside-node: done"
