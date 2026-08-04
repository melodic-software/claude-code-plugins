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
200-line/25KB limits. Resolves the memory dir via the sibling resolve-memory-dir.sh.
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
# both MEMORY.md stats measure that stripped content — matching criteria.md M1. HTML
# comments inside fenced code blocks are preserved, per the documented comment
# behavior. tr guards Git Bash CRLF; the arithmetic expansion strips the leading
# padding BSD `wc` emits on macOS.
strip_unloaded() {
  tr -d '\r' <"$index" | awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm == 1 { if ($0 == "---") fm = 2; next }
    /^[[:space:]]*```/ { fence = !fence; print; next }
    fence { print; next }
    incomment { if (/-->/) incomment = 0; next }
    /^[[:space:]]*<!--/ { if (!/-->/) incomment = 1; next }
    { print }
  '
}

if [[ "$mode" == "--memory-lines" ]]; then
  n=$(strip_unloaded | wc -l)
else
  n=$(strip_unloaded | wc -c)
fi
printf '%s\n' "$((n))"
