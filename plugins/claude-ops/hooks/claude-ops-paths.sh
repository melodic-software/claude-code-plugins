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

# Stable, collision-resistant slug for a project directory, used to key
# per-repo stores under machine-level bases (${CLAUDE_PLUGIN_DATA}) and to
# identify the repo in cross-repo store rows. Readable basename + an 8-char
# digest of the full physical path — folding alone is lossy (/tmp/a-b and
# /tmp/a/b would collide), so the digest carries the uniqueness. sha1sum ships
# with Git Bash and Linux; cksum is the POSIX fallback.
claude_ops::repo_slug() {
  local p base hash
  p=$(hook::normalize_path "$(hook::physical_path "$1")")
  base="${p##*/}"
  base="${base//[^A-Za-z0-9._-]/-}"
  hash=$(printf '%s' "$p" | sha1sum 2>/dev/null | cut -c1-8)
  [[ -n "$hash" ]] || hash=$(printf '%s' "$p" | cksum 2>/dev/null | cut -d' ' -f1)
  printf '%s' "${base:-project}${hash:+-$hash}"
}

# Collapse a configured relative dir to clean segments: both separators to '/',
# empty and '.' segments dropped. The resolver tolerates ./x and x//y when
# writing (mkdir normalizes), but a git ignore pattern is matched literally, so
# the exclude line must be canonical.
claude_ops::normalize_rel_segments() {
  local raw="${1//\\//}" out="" seg
  local -a segs
  IFS='/' read -r -a segs <<<"$raw"
  for seg in "${segs[@]}"; do
    [[ -z "$seg" || "$seg" == "." ]] && continue
    out+="${seg}/"
  done
  printf '%s' "${out%/}"
}

# Backslash-escape gitignore glob metacharacters (* ? [) and a literal
# backslash so a configured dir like `telemetry*` writes a LITERAL exclude
# pattern, not a glob that over-matches sibling dirs. Leading #/! need no
# handling: the exclude line always begins with the root anchor `/`, so the
# comment/negation meaning (first-char-only) never applies.
claude_ops::gitignore_escape() {
  local s="$1" out="" ch i
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    # shellcheck disable=SC1003  # '\' is a literal single-backslash case pattern, not a botched quote escape
    case "$ch" in
    '*' | '?' | '[' | '\') out+='\' ;;
    *) ;;
    esac
    out+="$ch"
  done
  printf '%s' "$out"
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
# a root-anchored ignore line to the repo's machine-local exclude file (git
# rev-parse --git-path info/exclude — correct in linked worktrees too).
# Normally ignores the store DIR (`/<dir>/`); when the configured dir resolves
# to the repo root itself (e.g. skill_usage_dir=.), the store is a bare file at
# the root, so ignore just that FILE (`/<store_file>`) rather than the whole
# repo. Idempotent; never touches tracked files or .gitignore; only ignore
# semantics change, so tracked content is unaffected. Disable with
# skill_usage_git_exclude=false. Best-effort: every failure is a silent no-op
# (the write path must never break on ignore hygiene).
claude_ops::ensure_git_exclude() {
  local project_dir="$1" rel_dir="$2" store_file="${3:-skill-usage.jsonl}" exclude_file dir line
  [[ "${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_GIT_EXCLUDE:-true}" == "true" ]] || return 0
  exclude_file=$(git -C "$project_dir" rev-parse --git-path info/exclude 2>/dev/null | tr -d '\r')
  [[ -n "$exclude_file" ]] || return 0
  case "$exclude_file" in
  /* | [A-Za-z]:*) ;;
  *) exclude_file="${project_dir%/}/$exclude_file" ;;
  esac
  dir="$(claude_ops::normalize_rel_segments "$rel_dir")"
  if [[ -n "$dir" ]]; then
    line="/$(claude_ops::gitignore_escape "$dir")/"
  else
    # Store dir IS the repo root — ignore the specific store file, not the tree.
    line="/$(claude_ops::gitignore_escape "$store_file")"
  fi
  if [[ -f "$exclude_file" ]] && grep -qxF -- "$line" "$exclude_file" 2>/dev/null; then
    return 0
  fi
  mkdir -p "$(dirname -- "$exclude_file")" 2>/dev/null || return 0
  printf '%s\n' "$line" >>"$exclude_file" 2>/dev/null || true
}
