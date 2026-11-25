#!/usr/bin/env bash
# GENERATED from lib/scope-resolve.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Exit 0 when a rung resolved, 3 when none did. No mutation.

scope_resolve_fallback() {
  local cwd="${SCOPE_CWD:-$PWD}"
  local ghq_bin="${REPO_FLEET_GHQ_BIN:-ghq}"
  local path root found=0 top dir child count

  for path in "$@"; do
    [[ -n "$path" && -d "$path" ]] || continue
    printf 'repo\t%s\n' "$path"
    found=1
  done
  if [[ "$found" -eq 1 ]]; then
    printf 'provenance\tnamed\n'
    return 0
  fi

  if command -v "$ghq_bin" >/dev/null 2>&1; then
    while IFS= read -r root; do
      root="${root%$'\r'}"
      [[ -n "$root" && -d "$root" ]] || continue
      printf 'root\t%s\n' "$root"
      found=1
    done < <("$ghq_bin" root --all 2>/dev/null || true)
    if [[ "$found" -eq 1 ]]; then
      printf 'provenance\tghq\n'
      return 0
    fi
  fi

  top="$(
    GIT_NO_LAZY_FETCH=1 GIT_OPTIONAL_LOCKS=0 GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
      git -C "$cwd" rev-parse --show-toplevel 2>/dev/null
  )" || top=""
  top="${top%$'\r'}"
  [[ -d "$top" ]] || top=""

  dir="${top:-$cwd}"
  for _ in 1 2 3 4; do
    dir="$(dirname "$dir")"
    count=0
    for child in "$dir"/*/ "$dir"/.[!.]*/ "$dir"/..?*/; do
      [[ -e "${child}.git" ]] && count=$((count + 1))
    done
    if [[ "$count" -ge 2 ]]; then
      printf 'root\t%s\nprovenance\tancestor\n' "$dir"
      return 0
    fi
  done

  if [[ -n "$top" ]]; then
    printf 'repo\t%s\nprovenance\tcwd\n' "$top"
    return 0
  fi
  return 3
}
