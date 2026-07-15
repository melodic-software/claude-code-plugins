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
