#!/usr/bin/env bash
# memory-dir-stats.sh — single-integer auto-memory statistics for the audit skill's
# `## Pre-computed context` block.
#
# Why this exists as a script rather than inline in SKILL.md: the harness composes
# every `` !`command` `` line of a skill into one shell invocation, and the
# worktree-isolation Bash guard refuses any command string carrying a shell
# expansion — `$var`, `$(…)`, `${VAR:-default}`. The stats these lines report need
# the resolved memory dir, so inline they read
# `d=$(resolve-memory-dir.sh); ls "$d"/*.md | wc -l`, which the guard rejects and
# the whole skill then fails to load from an isolated agent (#1687). Hoisting the
# logic here leaves the pre-compute line free of every `$` except the plugin
# variables the harness substitutes into literal paths before any shell sees them.
#
# The memory dir is resolved by the sibling resolve-memory-dir.sh — this plugin's
# single source of truth for that resolution — never by re-deriving the slug here.
#
# OUTPUT CONTRACT (both stat modes): exactly one integer on stdout, always exit 0.
# Every failure path — resolver failure, absent memory dir, absent MEMORY.md —
# reports `0` rather than an error, because the caller is a pre-compute line whose
# output is injected verbatim into the skill body. A non-zero exit is reserved for
# a bad or missing mode argument, which prints usage to stderr and nothing to stdout.
#
# Usage:
#   memory-dir-stats.sh --md-count      # count of *.md files in the memory dir
#   memory-dir-stats.sh --memory-lines  # loaded-content line count of MEMORY.md (0 when absent)
#   memory-dir-stats.sh --memory-bytes  # loaded-content byte count of MEMORY.md (0 when absent)
#   memory-dir-stats.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
memory-dir-stats.sh — emit one auto-memory statistic as a single integer.

Usage: memory-dir-stats.sh (--md-count|--memory-lines|--memory-bytes|--help)

  --md-count       print the number of *.md files in the current project's memory dir
  --memory-lines   print the loaded-content line count of that dir's MEMORY.md (0 when absent)
  --memory-bytes   print the loaded-content byte count of that dir's MEMORY.md (0 when absent)
  --help           this message

The MEMORY.md stats measure the content that loads: YAML frontmatter and block-level
HTML comments are stripped before the index is loaded, so they don't count toward the
200-line/25KB limits. A block that never closes is counted as content, comments inside
fenced code blocks are kept, and byte counts are of LF-normalized content — criteria.md
M1 records these readings. Resolves the memory dir via the sibling resolve-memory-dir.sh.
Every stat mode prints exactly one integer and always exits 0; a bad or missing mode
exits 2.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

mode="${1:-}"
if [[ "$mode" != "--md-count" && "$mode" != "--memory-lines" && "$mode" != "--memory-bytes" ]]; then
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# No repo guard here: the sibling resolver handles the non-repo case itself (outside a
# git repo the cwd is the project key, per the memory doc).
memory_dir=$(bash "$SCRIPT_DIR/resolve-memory-dir.sh" 2>/dev/null)

# An empty resolution would make the glob below expand against the filesystem root.
if [[ -z "$memory_dir" ]]; then
  echo "0"
  exit 0
fi

if [[ "$mode" == "--md-count" ]]; then
  # nullglob (the idiom the sibling memory-index-refs-check.sh already uses) so an
  # empty or absent dir yields an empty array rather than the literal pattern —
  # and, unlike `ls | wc -l`, cannot fail the pipeline under `pipefail`.
  shopt -s nullglob
  files=("$memory_dir"/*.md)
  shopt -u nullglob
  printf '%s\n' "${#files[@]}"
  exit 0
fi

index="$memory_dir/MEMORY.md"
if [[ ! -f "$index" ]]; then
  echo "0"
  exit 0
fi

# The 200-line/25KB limits measure only the content that loads: YAML frontmatter and
# block-level HTML comments are stripped before the index is loaded (memory doc), so
# both MEMORY.md stats measure that stripped content — matching criteria.md M1.
#
# A block only counts as one once it closes. An opening `---` or `<!--` that never
# closes is ordinary content, so those lines are held and flushed at EOF instead of
# swallowed: a leading thematic break or a clipped frontmatter block would otherwise
# report 0, and M1 is a [FAIL]-severity size gate that 0 always passes — it could
# never fire. MEMORY.md carries frontmatter by design (Claude Code stamps a `modified`
# field into any memory file that has it), so this is a live shape, not a corner case.
#
# Closing is necessary but not sufficient: a leading `---` only opens frontmatter if
# what follows is shaped like frontmatter. Markdown carries thematic breaks freely, so
# a file opening with `---` and carrying any later `---` would otherwise have the whole
# span between them stripped — a 253-line index reporting one loaded line, disarming
# the very gate the flush-at-EOF rule above exists to arm. Frontmatter mode is
# therefore bounded twice, and abandoning it re-emits the held lines as content:
#   * grammar — the block ends at the first line that is not blank, a comment, or a
#     `key:` mapping entry, which is all YAML a memory index's frontmatter holds;
#   * length — `fmcap` lines, because grammar alone still swallows a runaway whose
#     every line happens to be a `#` heading or a `Label: value` pair, a plausible
#     shape for a hand-written index.
# Both bounds fail toward counting: an over-count can only make this gate fire early,
# while the under-count they replace stopped it firing at all.
#
# A block-level comment occupies whole lines; text sharing a line with the comment's
# open or close is loaded content and survives. Comments inside fenced code blocks are
# preserved — a comment inside a fence is code, not block-level markdown. The memory
# doc states that explicitly for CLAUDE.md and says nothing either way for MEMORY.md;
# criteria.md M1 records the reading rather than claiming it as documented.
#
# tr guards Git Bash CRLF, so both counts measure LF-normalized content (see the
# assumption recorded in criteria.md M1); the arithmetic expansion strips the leading
# padding BSD `wc` emits on macOS.
strip_unloaded() {
  tr -d '\r' <"$index" | awk '
    BEGIN { fmcap = 20 }
    NR == 1 && $0 == "---" { pending = $0 "\n"; fm = 1; next }
    fm == 1 {
      if ($0 == "---") { fm = 2; pending = ""; next }
      if (++fmlines <= fmcap && ($0 ~ /^[[:space:]]*$/ ||
                                 $0 ~ /^[[:space:]]*#/ ||
                                 $0 ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_-]*:/)) {
        pending = pending $0 "\n"
        next
      }
      # Not frontmatter after all: re-emit the held lines as content and let this one
      # fall through to the rules below, which still owe it fence and comment handling.
      fm = 0
      printf "%s", pending
      pending = ""
    }
    incomment {
      pending = pending $0 "\n"
      if (!sub(/^.*-->/, "")) next
      incomment = 0; pending = ""
      if ($0 ~ /[^[:space:]]/) print
      next
    }
    /^[[:space:]]*```/ { fence = !fence; print; next }
    fence { print; next }
    /^[[:space:]]*<!--/ {
      pending = $0 "\n"
      if (!sub(/^[[:space:]]*<!--.*-->/, "")) { incomment = 1; next }
      pending = ""
      if ($0 ~ /[^[:space:]]/) print
      next
    }
    { print }
    END { printf "%s", pending }
  '
}

if [[ "$mode" == "--memory-lines" ]]; then
  n=$(strip_unloaded | wc -l)
else
  n=$(strip_unloaded | wc -c)
fi
printf '%s\n' "$((n))"
