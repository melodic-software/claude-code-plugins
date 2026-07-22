# shellcheck shell=bash
# Shared helpers for the clean entry scripts (sourceable; not invoked directly).

# shellcheck source=cleanup-paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cleanup-paths.sh"

# Resolve the OS once at source time. clean_path_key runs twice per repo across a
# batch (toplevel + each skip comparison), so forking uname on every call is
# hundreds of needless subprocesses on a large fleet — worst on Windows/MSYS
# where process creation is slow.
_CLEAN_OS="$(uname -s 2>/dev/null || true)"

clean_repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  printf '%s' "$root"
}

# Normalize a filesystem path to a comparison key: backslashes -> forward
# slashes, collapse trailing slashes, and lowercase on case-insensitive
# platforms (Windows via MSYS/Cygwin). This is the exact fix for the multi-repo
# batch skip-list data-loss incident: a skip entry written with Windows
# backslashes must compare equal to a repo path that git enumerated with forward
# slashes (git rev-parse always emits forward slashes) and vice versa. Never
# string-match raw paths across the two conventions.
clean_path_key() {
  local value="${1//\\//}"
  while [[ "$value" == */ && "$value" != "/" ]]; do value="${value%/}"; done
  case "$_CLEAN_OS" in
  MINGW* | MSYS* | CYGWIN*) printf '%s' "$value" | tr '[:upper:]' '[:lower:]' ;;
  *) printf '%s' "$value" ;;
  esac
}

# Return 0 when a canonical repo key (a rev-parse --show-toplevel path already
# run through clean_path_key) matches a skip-list entry, separator-agnostic and
# (on Windows) case-insensitive. The entry may be an absolute path or a trailing
# path-segment sequence (owner/repo or repo); matching is anchored on segment
# boundaries so a skip of "repo" never silently matches ".../other-repo".
clean_skip_matches() {
  local repo_key="$1" skip_key
  skip_key="$(clean_path_key "$2")"
  [[ -n "$skip_key" ]] || return 1
  [[ "$repo_key" == "$skip_key" ]] && return 0
  [[ "$repo_key" == *"/$skip_key" ]] && return 0
  return 1
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

# --- enumeration + manifest engine -------------------------------------------
#
# The selective build/caches tiers formerly ran one unpruned full-tree `find`
# per pattern (~10 walks/repo); the `! -path` exclusions filtered output but did
# not `-prune`, so every walk still descended `.git/`, `node_modules/`, `.venv/`.
# The engine below replaces that with ONE pruned walk per tier that never
# descends those three trees, then classifies, sizes, and manifests the result.
# Measured on a large .NET + node repo (Windows/NTFS): one pruned walk incl. `du`
# sizing ~17s vs a 10-walk unpruned dry-run that exceeded 10 min (killed).

# Single pruned walk. Prunes .git / node_modules / .venv (never descended),
# then `-print`s directory-name and file-glob matches. Tier-agnostic:
#   clean_enumerate ROOT dirname… -- fileglob…
# `du -sk` (POSIX) handles sizing downstream; GNU-only `find -printf` is avoided
# for BSD/macOS portability.
clean_enumerate() {
  local root="$1"
  shift
  local -a dir_names=() file_globs=()
  local bucket=dirs tok
  for tok in "$@"; do
    if [[ "$tok" == "--" ]]; then
      bucket=globs
      continue
    fi
    if [[ "$bucket" == dirs ]]; then dir_names+=("$tok"); else file_globs+=("$tok"); fi
  done

  local -a args=("$root" '(' -name .git -o -name node_modules -o -name .venv ')' -prune -o '(')
  local -a match=()
  local i
  if ((${#dir_names[@]})); then
    match+=(-type d '(')
    for i in "${!dir_names[@]}"; do
      ((i)) && match+=(-o)
      match+=(-name "${dir_names[$i]}")
    done
    match+=(')')
  fi
  if ((${#file_globs[@]})); then
    ((${#dir_names[@]})) && match+=(-o)
    match+=(-type f '(')
    for i in "${!file_globs[@]}"; do
      ((i)) && match+=(-o)
      match+=(-name "${file_globs[$i]}")
    done
    match+=(')')
  fi
  args+=("${match[@]}" ')' -print)
  find "${args[@]}" 2>/dev/null
}

# Candidate absolute paths for the caches / build tiers (explicit repo-root
# paths + one pruned walk). SSOT for both the standalone scripts and the
# build-tier's --include-caches path, so the two never drift.
clean_caches_candidates() {
  local root="$1" rel
  for rel in "${CLEAN_CACHE_EXPLICIT[@]}"; do printf '%s\n' "$root/$rel"; done
  for rel in "${CLEAN_CACHE_EXPLICIT_FILES[@]}"; do printf '%s\n' "$root/$rel"; done
  clean_enumerate "$root" "${CLEAN_CACHE_FIND_DIR_NAMES[@]}" -- "${CLEAN_CACHE_FIND_FILE_GLOBS[@]}"
}

clean_build_candidates() {
  local root="$1"
  clean_enumerate "$root" "${CLEAN_BUILD_DIR_NAMES[@]}" -- "${CLEAN_BUILD_FILE_GLOBS[@]}"
}

# Return 0 when an existing absolute path is eligible for removal; otherwise
# print the reason as a `Skip (…)` line on stdout and return 1. This same gate
# runs at both dry-run (building the manifest) and --apply (the staleness guard:
# a path that became protected between the two is not removed). Assumes the path
# exists — callers handle absence (a walk match always exists; an already-removed
# manifest entry is idempotent-success, handled in clean_apply_manifest).
clean_target_eligible() {
  local root="$1" abs="$2" rel="${2#"$1"/}"
  if clean_path_is_protected "$root" "$abs"; then
    printf 'Skip (protected): %s\n' "$rel"
    return 1
  fi
  if clean_path_in_submodule "$root" "$abs"; then
    printf 'Skip (submodule): %s\n' "$rel"
    return 1
  fi
  if [[ -d "$abs" ]] && clean_dir_has_protected_descendant "$root" "$abs"; then
    printf 'Skip (protected descendant): %s\n' "$rel"
    return 1
  fi
  return 0
}

# Class-tagged candidate accumulators, consumed by clean_plan. Reset per run.
CLEAN_CAND_ABS=()
CLEAN_CAND_CLASS=()

# Dry-run / summary accumulators (bytes are raw bytes — same unit scan.sh reports
# as `Total reclaimable`).
CLEAN_PLANNED_COUNT=0
CLEAN_PLANNED_BYTES=0
CLEAN_REMOVED_COUNT=0
CLEAN_FAILED_COUNT=0
CLEAN_REMOVED_BYTES=0

# clean_add_candidates CLASS abs… — tag each candidate path with its manifest
# class (caches|build) for the shared dedup + sizing pass.
clean_add_candidates() {
  local class="$1" p
  shift
  for p in "$@"; do
    [[ -n "$p" ]] || continue
    CLEAN_CAND_ABS+=("$p")
    CLEAN_CAND_CLASS+=("$class")
  done
}

clean_human_size() {
  local b="$1"
  if ((b >= 1073741824)); then
    awk -v b="$b" 'BEGIN { printf "%.1f GB", b / 1073741824 }'
  elif ((b >= 1048576)); then
    awk -v b="$b" 'BEGIN { printf "%.1f MB", b / 1048576 }'
  elif ((b >= 1024)); then
    awk -v b="$b" 'BEGIN { printf "%.1f KB", b / 1024 }'
  else
    printf '%s B' "$b"
  fi
}

# Classify every accumulated candidate, drop any eligible path nested under an
# eligible ancestor (`du` of the ancestor already counts it and `rm -rf` already
# removes it — otherwise the byte total double-counts and apply hits a spent
# path), size the survivors with a SINGLE batched `du` (one subprocess for the
# whole set — process creation is slow on Windows/MSYS), append
# `<class>\t<bytes>\t<relpath>` manifest lines, and — when announce=1 (dry-run)
# — print `Planned remove:` lines. Accumulates CLEAN_PLANNED_COUNT / _BYTES.
#   clean_plan ROOT MANIFEST ANNOUNCE
clean_plan() {
  local root="$1" manifest="$2" announce="$3"
  local -a elig_abs=() elig_class=()
  local i abs class skip
  # Classify first (a dir skipped for a protected descendant must not shadow a
  # clean nested target below it), dedup second.
  for i in "${!CLEAN_CAND_ABS[@]}"; do
    abs="${CLEAN_CAND_ABS[$i]}"
    class="${CLEAN_CAND_CLASS[$i]}"
    [[ -e "$abs" ]] || continue
    if skip="$(clean_target_eligible "$root" "$abs")"; then
      elig_abs+=("$abs")
      elig_class+=("$class")
    else
      [[ -n "$skip" ]] && printf '%s\n' "$skip"
    fi
  done

  local -a surv_abs=() surv_class=()
  local a b nested j
  for i in "${!elig_abs[@]}"; do
    a="${elig_abs[$i]}"
    nested=0
    for j in "${!elig_abs[@]}"; do
      [[ "$i" == "$j" ]] && continue
      b="${elig_abs[$j]}"
      # Anchor on '/' so `build` never swallows a sibling `buildstuff`.
      if [[ "$a" == "$b"/* ]]; then
        nested=1
        break
      fi
    done
    ((nested)) && continue
    surv_abs+=("$a")
    surv_class+=("${elig_class[$i]}")
  done
  ((${#surv_abs[@]})) || return 0

  local -A size_of=()
  local kb path
  while IFS=$'\t' read -r kb path; do
    [[ -n "$path" ]] || continue
    size_of["$path"]=$((kb * 1024))
  done < <(du -sk "${surv_abs[@]}" 2>/dev/null)

  local bytes rel
  for i in "${!surv_abs[@]}"; do
    abs="${surv_abs[$i]}"
    rel="${abs#"$root"/}"
    bytes="${size_of[$abs]:-0}"
    printf '%s\t%s\t%s\n' "${surv_class[$i]}" "$bytes" "$rel" >>"$manifest"
    ((announce)) && printf 'Planned remove: %s (%s)\n' "$rel" "$(clean_human_size "$bytes")"
    CLEAN_PLANNED_COUNT=$((CLEAN_PLANNED_COUNT + 1))
    CLEAN_PLANNED_BYTES=$((CLEAN_PLANNED_BYTES + bytes))
  done
}

# Consume a manifest: re-stat + re-run the protection gate per entry (the
# staleness guard), `rm -rf` survivors, and accumulate outcomes. An entry whose
# path is already gone is idempotent success (resume) — counted neither removed
# nor failed. A path that became protected since the dry-run is skipped (its
# `Skip` line re-emitted), not removed. CLEAN_FAILED_COUNT counts only genuine
# `rm` failures (locked / Unremovable).
#   clean_apply_manifest ROOT MANIFEST
clean_apply_manifest() {
  local root="$1" manifest="$2"
  local class bytes rel abs skip
  while IFS=$'\t' read -r class bytes rel; do
    [[ -n "$rel" ]] || continue
    abs="$root/$rel"
    [[ -e "$abs" ]] || continue
    if ! skip="$(clean_target_eligible "$root" "$abs")"; then
      [[ -n "$skip" ]] && printf '%s\n' "$skip"
      continue
    fi
    if rm -rf "$abs" 2>/dev/null; then
      printf 'Removed: %s\n' "$rel"
      CLEAN_REMOVED_COUNT=$((CLEAN_REMOVED_COUNT + 1))
      CLEAN_REMOVED_BYTES=$((CLEAN_REMOVED_BYTES + bytes))
    else
      printf 'Unremovable: %s\n' "$rel" >&2
      CLEAN_FAILED_COUNT=$((CLEAN_FAILED_COUNT + 1))
    fi
  done <"$manifest"
}

# clean_manifest_path [--manifest VALUE] → resolve/create the session manifest.
# Honors an explicit path (agent passes dry-run's path back at --apply); else
# mktemp a session-scoped file. Truncates so a reused path starts clean.
clean_manifest_path() {
  local explicit="$1" path
  if [[ -n "$explicit" ]]; then
    path="$explicit"
  else
    path="$(mktemp 2>/dev/null)" || path="${TMPDIR:-/tmp}/clean-manifest.$$"
  fi
  : >"$path"
  printf '%s' "$path"
}
