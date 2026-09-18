# shellcheck shell=bash
# Topic-file count for one auto-memory directory, library only.
#
# No top-level execution, no env-driven side effects, no exit calls. Callers own
# presentation, absence wording, and exit-code mapping: one caller prints the
# count in a tab-separated line, another in a prose sentence. Only the COUNTING
# RULE is shared, and both callers' printed counts are a tested contract.
#
# WHY THIS EXISTS: the rule is not "the *.md files in the directory".
#   * MEMORY.md is the index, not a topic, so it is excluded.
#   * The walk stays at depth 1, so a nested directory's files never fold in.
#   * The walk is null-delimited, so a topic filename carrying an embedded
#     newline counts once rather than twice.
# A hand-written second copy of those three rules drifts on the first change to
# any of them, and the drift surfaces only as a wrong number.
#
# NOT interchangeable with the glob form `files=("$dir"/*.md); ${#files[@]}`
# that the audit skill's memory-dir-stats.sh uses for its own statistic:
# pathname expansion skips dotfiles, so a `.hidden.md` file counts here and does
# not count there. The two counts answer different questions; neither is the
# other's substitute.

# mtopics::count <dir>: print <dir>'s topic-file count as a single integer.
# An absent, unreadable, or empty directory counts 0: absence is data the caller
# reports, never an error this library raises.
mtopics::count() {
  local n=0
  while IFS= read -r -d '' _; do n=$((n + 1)); done < <(
    find "$1" -maxdepth 1 -name '*.md' ! -name 'MEMORY.md' -print0 2>/dev/null
  )
  printf '%s\n' "$n"
}
