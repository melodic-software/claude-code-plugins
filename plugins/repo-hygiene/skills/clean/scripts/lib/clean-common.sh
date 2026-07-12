# shellcheck shell=bash
# Shared helpers for the clean entry scripts (sourceable; not invoked directly).

# shellcheck source=cleanup-paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cleanup-paths.sh"

clean_repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  printf '%s' "$root"
}

clean_path_is_tracked() {
  local repo_root="$1" rel="$2"
  git -C "$repo_root" ls-files --error-unmatch "$rel" >/dev/null 2>&1
}

clean_path_is_protected() {
  local repo_root="$1" abs="$2"
  local norm="${abs//\\//}"
  local sub

  if clean_path_is_tracked "$repo_root" "${norm#"$repo_root"/}"; then
    return 0
  fi

  # Plain substring-protected segments live in CLEAN_PROTECTED_SUBSTRINGS and are
  # matched by the loop below. This case holds only the patterns that loop cannot
  # express: a mid-path wildcard and anchored file-name / suffix matches.
  case "$norm" in
  *"/.claude/skills/"*"/data/"*) return 0 ;;
  */.env | */.env.*) return 0 ;;
  *".local.json" | *".local.jsonc" | *".local.md") return 0 ;;
  *".csproj.user" | *".sln.docstates.suo" | *".suo") return 0 ;;
  *) ;;
  esac

  for sub in "${CLEAN_PROTECTED_SUBSTRINGS[@]}"; do
    [[ "$norm" == *"$sub"* ]] && return 0
  done

  return 1
}

# Emit `git clean -e <pattern>` args (newline-delimited: alternating `-e` and
# pattern) for the `tree` tier's default-preserve set. SSOT patterns live in
# cleanup-paths.sh. Flags gate the two opt-in tiers:
#   $1 include_deps    (1 = also remove deps; 0 = preserve)
#   $2 include_secrets (1 = also remove secrets; 0 = preserve)
# Skill data is ALWAYS preserved (irreplaceable user synthesis). Caller does:
#   mapfile -t args < <(clean_tree_preserve_args "$d" "$s")
clean_tree_preserve_args() {
  local include_deps="$1" include_secrets="$2" pat
  if [[ "$include_secrets" -ne 1 ]]; then
    for pat in "${CLEAN_TREE_PRESERVE_SECRETS[@]}"; do printf -- '-e\n%s\n' "$pat"; done
  fi
  for pat in "${CLEAN_TREE_PRESERVE_SKILLDATA[@]}"; do printf -- '-e\n%s\n' "$pat"; done
  if [[ "$include_deps" -ne 1 ]]; then
    for pat in "${CLEAN_TREE_PRESERVE_DEPS[@]}"; do printf -- '-e\n%s\n' "$pat"; done
  fi
}

# Restore tracked files that `git clean` deleted by traversing a reparse point
# (Windows directory junction / Unix symlink) that pointed into a tracked dir.
# Cross-platform safety net — needs NO junction detection. SAFE ONLY when a
# `git reset --hard` ran first (no uncommitted tracked state to clobber), which
# the tree flow guarantees. Prints the count of restored files to stdout.
clean_restore_tracked_deletions() {
  local repo_root="$1" count=0 path
  while IFS= read -r -d '' path; do
    [[ -z "$path" ]] && continue
    git -C "$repo_root" restore -- "$path" 2>/dev/null && ((count++)) || true
  done < <(git -C "$repo_root" ls-files -z --deleted 2>/dev/null)
  printf '%s' "$count"
}

clean_branch_matches_protected_pattern() {
  local branch="$1"
  local pat exact

  for exact in "${CLEAN_PROTECTED_BRANCH_EXACT[@]}"; do
    [[ "$branch" == "$exact" ]] && return 0
  done

  for pat in "${CLEAN_PROTECTED_BRANCH_GLOBS[@]}"; do
    # shellcheck disable=SC2254
    case "$branch" in
    $pat) return 0 ;;
    *) ;;
    esac
  done

  return 1
}
