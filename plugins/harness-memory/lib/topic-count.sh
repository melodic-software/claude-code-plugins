# shellcheck shell=bash
# Topic-file count for one auto-memory directory, library only.
# No top-level execution or exit calls; callers own presentation and exit codes.
#
# Shared so no caller hand-copies the counting rule, whose drift shows only as a wrong number.
# Not interchangeable with memory-dir-stats.sh's glob count, which skips dotfiles.

# mtopics::count <dir>: print <dir>'s topic-file count as a single integer.
# An absent, unreadable, or empty directory prints 0, never an error.
mtopics::count() {
  local n=0
  while IFS= read -r -d '' _; do n=$((n + 1)); done < <(
    find "$1" -maxdepth 1 -name '*.md' ! -name 'MEMORY.md' -print0 2>/dev/null
  )
  printf '%s\n' "$n"
}
