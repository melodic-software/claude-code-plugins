# shellcheck shell=bash

list_tracked_markdown() {
  git -c core.fsmonitor= -c core.hooksPath=/dev/null -C "$1" -c core.quotePath=false ls-files '*.md'
}

normalize_dir_target() {
  local dir="${1%/}"
  if [[ -z "$dir" || "$dir" == [A-Za-z]: ]]; then
    printf '%s\n' "$1"
    return 0
  fi
  printf '%s\n' "$dir"
}

list_tracked_or_fallback() {
  local dir="$1" mode="$2" inside listing status rel

  if ! command -v git >/dev/null 2>&1; then
    if [[ "$mode" == walk ]]; then
      echo "detect.sh: git is not on PATH; directory $dir expanded via filesystem walk (tracked-files-only is not achievable)" >&2
      find "$dir" -name '*.md' -type f 2>/dev/null
    else
      echo "detect.sh: git is not on PATH; a bare invocation has no tracked markdown to list (pass paths explicitly)" >&2
    fi
    return 0
  fi

  inside="$(git -c core.fsmonitor= -c core.hooksPath=/dev/null -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)"
  status=$?
  if [[ "$mode" == walk ]]; then
    if [[ "$status" -ne 0 ]]; then
      echo "detect.sh: git could not confirm a work tree under $dir (exit $status); expanding via filesystem walk" >&2
    fi
    if [[ "$status" -ne 0 || "$inside" != "true" ]]; then
      find "$dir" -name '*.md' -type f 2>/dev/null
      return 0
    fi
  elif [[ "$status" -ne 0 || "$inside" != "true" ]]; then
    echo "detect.sh: git could not confirm a work tree at $dir; a bare invocation has no tracked markdown to list (pass paths explicitly)" >&2
    return 0
  fi

  listing="$(list_tracked_markdown "$dir")"
  status=$?
  if [[ "$status" -ne 0 ]]; then
    if [[ "$mode" == walk ]]; then
      echo "detect.sh: git ls-files failed under $dir (exit $status); that directory expanded to nothing" >&2
    else
      echo "detect.sh: git ls-files failed in $dir (exit $status); nothing was scanned" >&2
    fi
    return 0
  fi

  if [[ "$mode" != walk ]]; then
    [[ -n "$listing" ]] && printf '%s\n' "$listing"
    return 0
  fi
  local sep=/
  [[ "$dir" == */ || "$dir" == *\\ ]] && sep=""
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    printf '%s%s%s\n' "$dir" "$sep" "$rel"
  done <<<"$listing"
}

expand_dir_target() {
  list_tracked_or_fallback "$(normalize_dir_target "$1")" walk
}

list_repo_markdown() {
  list_tracked_or_fallback "$1" none
}

resolve_targets() {
  local -n dest_ref="$1"
  local repo_root="$2" paths_file="$3" offset="$4" limit="$5" skip_window="$6"
  shift 6
  local -a raw=("$@")
  local line rest t end p
  local -a expanded=() windowed=() files=()

  if [[ -n "$paths_file" ]]; then
    if [[ ! -r "$paths_file" ]]; then
      echo "detect.sh: cannot read --paths-file: $paths_file" >&2
      return 2
    fi
    while IFS= read -r line || [[ -n $line ]]; do
      [[ -n "${line//[[:space:]]/}" ]] || continue
      rest="${line#*$'\t'}"
      [[ "$rest" != "$line" && "$rest" != *$'\t'* ]] && line="$rest"
      raw+=("$line")
    done <"$paths_file"
    if [[ "${#raw[@]}" -eq 0 ]]; then
      echo "detect.sh: --paths-file lists no paths; nothing was scanned: $paths_file" >&2
    fi
  elif [[ "${#raw[@]}" -eq 0 ]]; then
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

  # shellcheck disable=SC2034  # nameref: writes the caller's array
  dest_ref=(${files[@]+"${files[@]}"})
}
