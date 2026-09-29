# shellcheck shell=bash
# One resolver for detect.sh's target list. Sourceable; not invoked directly.
# Every entry form (no paths, explicit paths, a directory, --paths-file,
# offset/limit) comes through resolve_targets, and the git listing is one
# function: core.quotePath=false, with the listing's own stderr left intact.

# list_tracked_markdown <dir>: tracked *.md paths relative to dir, one per line.
# The exit status is git's. quotePath is forced off so a non-ASCII name is the
# raw filename, not a C-quoted escape.
list_tracked_markdown() {
  git -C "$1" -c core.quotePath=false ls-files '*.md'
}

# Strip one trailing slash, except a Windows drive root (`C:/`) or `/`.
# `C:\` is unchanged: this strip only removes `/`.
normalize_dir_target() {
  local dir="${1%/}"
  if [[ -z "$dir" || "$dir" == [A-Za-z]: ]]; then
    printf '%s\n' "$1"
    return 0
  fi
  printf '%s\n' "$dir"
}

# expand_dir_target <dir>: markdown under dir, one absolute-to-the-spelling path
# per line. Tracked files when git confirms a work tree; a filesystem walk
# otherwise, with the stderr line that names why the walk ran.
expand_dir_target() {
  local dir inside listing status
  dir="$(normalize_dir_target "$1")"

  if ! command -v git >/dev/null 2>&1; then
    echo "detect.sh: git is not on PATH; directory $dir expanded via filesystem walk (tracked-files-only is not achievable)" >&2
    find "$dir" -name '*.md' -type f 2>/dev/null
    return 0
  fi

  inside="$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)"
  status=$?
  if [[ "$status" -ne 0 ]]; then
    echo "detect.sh: git could not confirm a work tree under $dir (exit $status); expanding via filesystem walk" >&2
    find "$dir" -name '*.md' -type f 2>/dev/null
    return 0
  fi
  if [[ "$inside" != "true" ]]; then
    find "$dir" -name '*.md' -type f 2>/dev/null
    return 0
  fi

  listing="$(list_tracked_markdown "$dir")"
  status=$?
  if [[ "$status" -ne 0 ]]; then
    echo "detect.sh: git ls-files failed under $dir (exit $status); that directory expanded to nothing" >&2
    return 0
  fi

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    if [[ "$dir" == */ || "$dir" == *\\ ]]; then
      printf '%s%s\n' "$dir" "$rel"
    else
      printf '%s/%s\n' "$dir" "$rel"
    fi
  done <<<"$listing"
}

# list_repo_markdown <repo-root>: tracked markdown for a bare invocation.
# Prints repo-relative paths. A missing git, a non-work-tree, or a failed
# listing prints its stderr line and prints no paths.
list_repo_markdown() {
  local repo_root="$1" inside listing status

  if ! command -v git >/dev/null 2>&1; then
    echo "detect.sh: git is not on PATH; a bare invocation has no tracked markdown to list (pass paths explicitly)" >&2
    return 0
  fi

  inside="$(git -C "$repo_root" rev-parse --is-inside-work-tree 2>/dev/null)"
  status=$?
  if [[ "$status" -ne 0 || "$inside" != "true" ]]; then
    echo "detect.sh: git could not confirm a work tree at $repo_root; a bare invocation has no tracked markdown to list (pass paths explicitly)" >&2
    return 0
  fi

  listing="$(list_tracked_markdown "$repo_root")"
  status=$?
  if [[ "$status" -ne 0 ]]; then
    echo "detect.sh: git ls-files failed in $repo_root (exit $status); nothing was scanned" >&2
    return 0
  fi

  [[ -n "$listing" ]] || return 0
  printf '%s\n' "$listing"
}

# resolve_targets <dest> <repo-root> <paths-file> <offset> <limit> <skip-window> [path...]
# Fills dest with the sorted file list. skip-window is 1 for --list-targets,
# which ignores offset and limit. Returns 2 when paths-file is unreadable.
resolve_targets() {
  local -n dest_ref="$1"
  local repo_root="$2" paths_file="$3" offset="$4" limit="$5" skip_window="$6"
  shift 6
  local -a raw=("$@")
  local line rest t end p
  local -a expanded=() windowed=() files=()
  local paths_file_empty=0

  if [[ -n "$paths_file" ]]; then
    if [[ ! -r "$paths_file" ]]; then
      echo "detect.sh: cannot read --paths-file: $paths_file" >&2
      return 2
    fi
    while IFS= read -r line; do
      [[ -n "${line//[[:space:]]/}" ]] || continue
      rest="${line#*$'\t'}"
      [[ "$rest" != "$line" && "$rest" != *$'\t'* ]] && line="$rest"
      raw+=("$line")
    done <"$paths_file"
    if [[ "${#raw[@]}" -eq 0 ]]; then
      echo "detect.sh: --paths-file lists no paths; nothing was scanned: $paths_file" >&2
      paths_file_empty=1
    fi
  fi

  if [[ "${#raw[@]}" -eq 0 && "$paths_file_empty" -eq 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      raw+=("$repo_root/$line")
    done < <(list_repo_markdown "$repo_root")
  fi

  for t in ${raw[@]+"${raw[@]}"}; do
    if [[ -d "$t" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && expanded+=("$line")
      done < <(expand_dir_target "$t")
    else
      expanded+=("$t")
    fi
  done

  mapfile -t windowed < <(printf '%s\n' ${expanded[@]+"${expanded[@]}"} | sort -u)
  if [[ "$skip_window" -eq 0 ]] && [[ "$offset" -gt 0 || "$limit" -gt 0 ]]; then
    end="${#windowed[@]}"
    [[ "$limit" -gt 0 ]] && end=$((offset + limit))
    mapfile -t windowed < <(printf '%s\n' ${windowed[@]+"${windowed[@]}"} | awk -v s="$offset" -v e="$end" 'NR > s && NR <= e')
  fi

  for p in ${windowed[@]+"${windowed[@]}"}; do
    [[ -f "$p" ]] || continue
    files+=("$p")
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    dest_ref=()
  else
    # shellcheck disable=SC2034  # nameref: writes the caller's array
    dest_ref=("${files[@]}")
  fi
}
