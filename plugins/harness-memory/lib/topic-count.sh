# shellcheck shell=bash

mtopics::count() {
  local n=0
  while IFS= read -r -d '' _; do n=$((n + 1)); done < <(
    find "$1" -maxdepth 1 -name '*.md' ! -name 'MEMORY.md' -print0 2>/dev/null
  )
  printf '%s\n' "$n"
}
