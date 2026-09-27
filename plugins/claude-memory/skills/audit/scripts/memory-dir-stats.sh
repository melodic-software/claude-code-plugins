#!/usr/bin/env bash
# memory-dir-stats.sh — single-integer auto-memory statistics for the audit skill's
# `## Pre-computed context` block.
# Every stat mode prints exactly one integer and exits 0, failures included: the
# output is injected verbatim into the skill body. Only a bad mode exits non-zero.
# Keep this a script, not an inline pre-compute line: the worktree-isolation Bash
# guard refuses a pre-compute command carrying a `$` expansion, so inlining it breaks
# skill loading from an isolated agent.

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

# No repo guard here: the sibling resolver handles the non-repo case itself.
memory_dir=$(bash "$SCRIPT_DIR/resolve-memory-dir.sh" 2>/dev/null)

# An empty resolution would make the glob below expand against the filesystem root.
if [[ -z "$memory_dir" ]]; then
  echo "0"
  exit 0
fi

if [[ "$mode" == "--md-count" ]]; then
  # nullglob, not `ls | wc -l`, which fails the pipeline under pipefail on an empty dir.
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

# Emits only the MEMORY.md content that loads (criteria.md M1 records the reading):
# YAML frontmatter and block-level HTML comments are stripped, fenced comments kept.
# A `---` or `<!--` that never closes is content, flushed at EOF: counting 0 would
# disarm M1's size gate. Frontmatter mode ends at the first line that is not blank or
# `key:` (a `#` line is a markdown heading), after `fmcap` lines, or after `fmbytecap`
# bytes, re-emitting what it held; every bound fails toward over-counting.
# A comment ends at the FIRST `-->` after its opener and the line is re-scanned, so
# text beside a comment survives; awk's ERE has no lazy match, hence index/substr.
# tr strips Git Bash CRLF; the caller's $((n)) strips BSD wc padding.
strip_unloaded() {
  tr -d '\r' <"$index" | LC_ALL=C awk '
    BEGIN { fmcap = 20; fmbytecap = 1024 }
    function emit(s) { if (s ~ /[^[:space:]]/) print s }
    # Remove every complete comment from s, each ending at the first `-->` after its
    # own opener. An opener with no close takes the rest of s and arms `incomment`,
    # holding the raw remainder so an unterminated block still counts at EOF.
    function uncomment(s,   p, q, out) {
      while ((p = index(s, "<!--")) > 0) {
        out = out substr(s, 1, p - 1)
        q = index(substr(s, p + 4), "-->")
        if (q == 0) { incomment = 1; pending = substr(s, p) "\n"; return out }
        s = substr(s, p + q + 6)
      }
      return out s
    }
    NR == 1 && $0 == "---" { pending = $0 "\n"; fm = 1; next }
    fm == 1 {
      if ($0 == "---") { fm = 2; pending = ""; next }
      if (++fmlines <= fmcap && length(pending) + length($0) + 1 <= fmbytecap &&
          ($0 ~ /^[[:space:]]*$/ ||
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
      close_at = index($0, "-->")
      if (close_at == 0) next
      incomment = 0; pending = ""
      emit(uncomment(substr($0, close_at + 3)))
      next
    }
    /^[[:space:]]*```/ { fence = !fence; print; next }
    fence { print; next }
    /^[[:space:]]*<!--/ {
      residue = uncomment($0)
      # An unterminated opener holds its own raw text. Whitespace that loaded ahead of
      # it belongs to that held block too, so an indented opener keeps its indent.
      # Real text is emitted instead of held: folding it into pending would lose it
      # outright once the comment closes and the held block is dropped.
      if (incomment && residue !~ /[^[:space:]]/) pending = residue pending
      emit(residue)
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
