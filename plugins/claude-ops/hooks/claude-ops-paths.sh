# shellcheck shell=bash
# Plugin-local path policy for user-configured repository destinations.

# Resolve a project-relative directory without allowing an absolute path,
# Windows drive/UNC path, `..` traversal, or an existing symlink ancestor to
# escape the physical project root. Prints the candidate on success.
claude_ops::resolve_project_relative_dir() {
  local project_dir="$1" configured="$2" normalized segment candidate ancestor

  [[ -n "$project_dir" && -n "$configured" ]] || return 1

  # Treat both separators consistently on every supported host. Reject rooted
  # paths before joining; `C:foo` is drive-relative on Windows and is rejected
  # with fully qualified drive paths as a portability boundary.
  normalized="${configured//\\//}"
  [[ "$normalized" != /* ]] || return 1
  [[ ! "$normalized" =~ ^[A-Za-z]: ]] || return 1

  IFS='/' read -r -a segments <<<"$normalized"
  for segment in "${segments[@]}"; do
    [[ "$segment" != ".." ]] || return 1
  done

  project_dir="${project_dir%/}"
  candidate="${project_dir}/${normalized}"

  # Validate the nearest existing ancestor before mkdir. This rejects a
  # lexically in-project path whose existing symlink parent resolves outside.
  ancestor="$candidate"
  while [[ ! -e "$ancestor" && "$ancestor" != "/" && "$ancestor" != "." ]]; do
    ancestor=$(dirname -- "$ancestor")
  done

  local physical_project physical_ancestor
  physical_project=$(hook::normalize_path "$(hook::physical_path "$project_dir")")
  physical_project="${physical_project%/}"
  physical_ancestor=$(hook::normalize_path "$(hook::physical_path "$ancestor")")
  if [[ "$physical_ancestor" != "$physical_project" && "$physical_ancestor" != "$physical_project"/* ]]; then
    return 1
  fi

  printf '%s' "$candidate"
}

# Stable slug for a project directory, used to key per-repo stores under
# machine-level bases (${CLAUDE_PLUGIN_DATA}). Physical path, separators and
# reserved bytes folded to '-'.
claude_ops::repo_slug() {
  local p
  p=$(hook::normalize_path "$(hook::physical_path "$1")")
  p="${p//[^A-Za-z0-9._-]/-}"
  printf '%s' "${p:-project}"
}

# Resolve the skill-usage store directory for a scope:
#   repo (default) — skill_usage_dir (default .claude/observability) as a
#     contained project-relative path under the project root.
#   user — the same contained subpath, resolved under $HOME instead
#     (default ~/.claude/observability).
#   data-dir — ${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>; skill_usage_dir
#     does not apply (the data dir is plugin-owned, keyed by repo).
# Prints the destination on success. Returns 1 on an invalid configured dir,
# 2 when the scope's base directory is unavailable.
claude_ops::resolve_skill_usage_dir() {
  local scope="$1" project_dir="$2" rel_dir="$3"
  case "$scope" in
  user)
    [[ -n "${HOME:-}" && -d "${HOME:-}" ]] || return 2
    claude_ops::resolve_project_relative_dir "$HOME" "$rel_dir" || return 1
    ;;
  data-dir)
    [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]] || return 2
    printf '%s' "${CLAUDE_PLUGIN_DATA%/}/skill-usage/$(claude_ops::repo_slug "$project_dir")"
    ;;
  *)
    claude_ops::resolve_project_relative_dir "$project_dir" "$rel_dir" || return 1
    ;;
  esac
}

# Keep `git status` clean when the store lives inside a repo work tree: append
# a root-anchored ignore line for the store dir to the repo's machine-local
# exclude file (git rev-parse --git-path info/exclude — correct in linked
# worktrees too). Idempotent; never touches tracked files or .gitignore; only
# ignore semantics change, so tracked content under the dir is unaffected.
# Disable with skill_usage_git_exclude=false. Best-effort: every failure is a
# silent no-op (the write path must never break on ignore hygiene).
claude_ops::ensure_git_exclude() {
  local project_dir="$1" rel_dir="$2" exclude_file line
  [[ "${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_GIT_EXCLUDE:-true}" == "true" ]] || return 0
  exclude_file=$(git -C "$project_dir" rev-parse --git-path info/exclude 2>/dev/null | tr -d '\r')
  [[ -n "$exclude_file" ]] || return 0
  case "$exclude_file" in
  /* | [A-Za-z]:*) ;;
  *) exclude_file="${project_dir%/}/$exclude_file" ;;
  esac
  line="${rel_dir//\\//}"
  line="/${line%/}/"
  if [[ -f "$exclude_file" ]] && grep -qxF -- "$line" "$exclude_file" 2>/dev/null; then
    return 0
  fi
  mkdir -p "$(dirname -- "$exclude_file")" 2>/dev/null || return 0
  printf '%s\n' "$line" >>"$exclude_file" 2>/dev/null || true
}
