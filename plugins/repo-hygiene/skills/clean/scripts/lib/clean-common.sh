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
  */.env*) return 0 ;;
  *".local.json" | *".local.jsonc" | *".local.md") return 0 ;;
  *".csproj.user" | *".sln.docstates.suo" | *".suo") return 0 ;;
  *) ;;
  esac

  for sub in "${CLEAN_PROTECTED_SUBSTRINGS[@]}"; do
    [[ "$norm" == *"$sub"* ]] && return 0
  done

  return 1
}

# Return 0 when a directory contains any protected descendant (tracked file, or
# an untracked file/dir matching a protected class). The selective tiers rm -rf
# whole artifact directories, so the per-target protection check above is not
# enough on its own — a protected file nested inside an unprotected build/cache
# dir would be deleted with it. Callers skip removing a directory this returns
# true for. Read-only.
clean_dir_has_protected_descendant() {
  local repo_root="$1" dir="$2" entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if clean_path_is_protected "$repo_root" "$entry"; then
      return 0
    fi
  done < <(find "$dir" -mindepth 1 2>/dev/null)
  return 1
}

# Return 0 when a path is a configured submodule or lives inside one. A
# submodule's files are tracked by the submodule, not the superproject index, so
# clean_path_is_tracked (which consults only the superproject) treats them as
# untracked — a recursively-found build/cache dir inside a submodule would then
# be deleted with its tracked contents. Callers skip such targets. Read-only.
clean_path_in_submodule() {
  local repo_root="$1" abs="$2" rel sm
  rel="${abs//\\//}"
  rel="${rel#"$repo_root"/}"
  while IFS= read -r sm; do
    [[ -z "$sm" ]] && continue
    if [[ "$rel" == "$sm" || "$rel" == "$sm"/* ]]; then
      return 0
    fi
  done < <(git -C "$repo_root" config --file "$repo_root/.gitmodules" --get-regexp '\.path$' 2>/dev/null | cut -d' ' -f2- | tr -d '\r')
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

# Return 0 when a repo-relative path matches the SECRETS preserve class
# (CLEAN_TREE_PRESERVE_SECRETS — gitignore-style: basename globs, dir/ prefixes,
# and slash-anchored file paths). SSOT check for guards that gate on secret-class
# files outside `git clean -e` (which consumes the array directly).
clean_path_matches_secret_class() {
  local rel="$1" pat base
  rel="${rel//\\//}"
  base="${rel##*/}"
  for pat in "${CLEAN_TREE_PRESERVE_SECRETS[@]}"; do
    if [[ "$pat" == */ ]]; then
      pat="${pat%/}"
      [[ "$rel" == "$pat"/* || "$rel" == *"/$pat/"* ]] && return 0
    elif [[ "$pat" == */* ]]; then
      [[ "$rel" == "$pat" || "$rel" == *"/$pat" ]] && return 0
    else
      # shellcheck disable=SC2254
      case "$base" in
      $pat) return 0 ;;
      *) ;;
      esac
    fi
  done
  return 1
}

# Return 0 when a repo-relative path lies inside a skill-owned data/ directory
# (CLEAN_TREE_PRESERVE_SKILLDATA) — irreplaceable user synthesis the clean skill
# always preserves with no removal flag. Kept separate from the secret matcher
# because the pattern carries a mid-path wildcard (.claude/skills/*/data/): a
# quoted `[[ == ]]` would treat the `*` literally, so match as an unquoted glob.
clean_path_matches_skilldata() {
  local rel="$1" pat
  rel="${rel//\\//}"
  rel="${rel%/}"
  for pat in "${CLEAN_TREE_PRESERVE_SKILLDATA[@]}"; do
    pat="${pat%/}"
    # Match the data dir itself and anything under it, at the repo root or nested
    # (git ls-files may report the ignored dir as a bare path, find reports both).
    # shellcheck disable=SC2254
    case "$rel" in
    $pat | $pat/* | */$pat | */$pat/*) return 0 ;;
    *) ;;
    esac
  done
  return 1
}

# Return 0 when a path is a filesystem reparse point (POSIX symlink, Windows
# junction, or native Windows symlink). bash -L covers what MSYS maps to
# symlinks; fsutil (readable without elevation) catches anything -L misses.
clean_path_is_reparse_point() {
  local path="$1"
  [[ -L "$path" ]] && return 0
  if command -v fsutil >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
    fsutil reparsepoint query "$(cygpath -w "$path")" >/dev/null 2>&1 && return 0
  fi
  return 1
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
