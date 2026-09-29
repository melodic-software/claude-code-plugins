#!/usr/bin/env bash
# Shared no-scope ladder for repo-fleet-hygiene.
#
# Rungs, first hit wins, after the caller has already applied explicit
# arguments and fleet config:
#   1. named paths (conversation paths the skill passes through)
#   2. every ghq root (`ghq root --all`), when ghq is installed
#   3. the current working directory, when it is a Git checkout
#   4. ancestor: the nearest of the 4 parents above the working directory
#      that directly holds 2 or more Git repositories
#   5. exit 3
#
# Prints tab-separated lines: repo|root <path>, then provenance <label>.
# Exit 0 when a rung resolved, 3 when none did. No mutation.

scope_resolve_fallback() {
  local cwd="${SCOPE_CWD:-$PWD}"
  local ghq_bin="${REPO_FLEET_GHQ_BIN:-ghq}"
  local path root found=0 line

  if [[ "$#" -gt 0 ]]; then
    for path in "$@"; do
      [[ -n "$path" && -d "$path" ]] || continue
      printf 'repo\t%s\n' "$path"
      found=1
    done
    if [[ "$found" -eq 1 ]]; then
      printf 'provenance\tnamed\n'
      return 0
    fi
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

  # Same containment the fleet collector uses for a read-only git probe, so a
  # test double that refuses an unconstrained git still answers here.
  if line="$(
    GIT_NO_LAZY_FETCH=1 GIT_OPTIONAL_LOCKS=0 GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0 \
      git -C "$cwd" rev-parse --show-toplevel 2>/dev/null
  )"; then
    line="${line%$'\r'}"
    if [[ -n "$line" && -d "$line" ]]; then
      printf 'repo\t%s\n' "$line"
      printf 'provenance\tcwd\n'
      return 0
    fi
  fi

  local dir="$cwd" child count
  for _ in 1 2 3 4; do
    dir="$(dirname "$dir")"
    count=0
    for child in "$dir"/*/; do
      [[ -e "${child}.git" ]] && count=$((count + 1))
    done
    if [[ "$count" -ge 2 ]]; then
      printf 'root\t%s\n' "$dir"
      printf 'provenance\tancestor\n'
      return 0
    fi
  done
  return 3
}
