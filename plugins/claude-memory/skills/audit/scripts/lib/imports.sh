#!/usr/bin/env bash
# imports.sh — the `@path` import graph of a memory file, as Claude Code reads it.
#
# Sourced by the audit scripts that need to know what a CLAUDE.md actually pulls
# into context: instruction-load-stats.sh (how much loads) and
# nested-agents-check.sh (whether a nested AGENTS.md loads at all). One parser so
# the two answers cannot disagree about what an import is.
#
# The reading follows the memory doc ("Import additional files"): an import is an
# `@path` token; relative paths resolve against the importing file's directory,
# not the working directory; imports recurse to a maximum depth of four hops;
# parsing skips fenced code blocks and inline code spans, so a backticked
# `@README` is a mention, not an import. Trailing sentence punctuation is dropped
# from a token so `see @docs/x.md.` imports `docs/x.md`.
#
# Functions (all pure, none writes anything):
#   il_imports_of <file>            print each import target as an absolute path, one per line
#   il_realpath <path>              resolve symlinks (bounded), print the physical path
#   il_reaches <from> <want> [depth] 0 when <from> is, or transitively imports, the file
#                                    whose physical path is <want>
#   il_walk <file> [depth] [seen]   print `<status>\t<path>` for the file and every import
#                                    it reaches: root, import, external, missing, depth, seen

# Print the import targets of one file as absolute paths. A `~/` target expands
# against HOME the way the doc's own example (`@~/.claude/my-project-instructions.md`)
# expects.
il_imports_of() {
  local file="$1" dir
  [[ -f "$file" ]] || return 0
  dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || return 0
  tr -d '\r' <"$file" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)
      n = split(line, tok, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        if (substr(tok[i], 1, 1) == "@" && length(tok[i]) > 1) {
          t = substr(tok[i], 2)
          sub(/[.,;:)]+$/, "", t)
          if (t != "") print t
        }
      }
    }
  ' | while IFS= read -r target; do
    case "$target" in
    /*) printf '%s\n' "$target" ;;
    "~"/*) printf '%s\n' "${HOME}/${target#\~/}" ;;
    *) printf '%s\n' "$dir/$target" ;;
    esac
  done
}

# Physical path of <path>: directories through `pwd -P`, files by following a
# symlink chain by hand with a hop bound so a cycle cannot spin. A path that does
# not exist is printed unchanged so a caller can still report it as missing.
il_realpath() {
  local p="${1:-}" dir base target hops=0
  [[ -n "$p" ]] || return 0
  if [[ ! -e "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  if [[ -d "$p" ]]; then
    (cd -P "$p" 2>/dev/null && pwd -P) || printf '%s' "$p"
    return 0
  fi
  dir="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P)" || {
    printf '%s' "$p"
    return 0
  }
  base="$(basename "$p")"
  while [[ -L "$dir/$base" ]] && ((hops < 32)); do
    target="$(readlink "$dir/$base" 2>/dev/null)" || break
    [[ -n "$target" ]] || break
    case "$target" in
    /*) dir="$(cd -P "$(dirname "$target")" 2>/dev/null && pwd -P)" || break ;;
    *) dir="$(cd -P "$dir/$(dirname "$target")" 2>/dev/null && pwd -P)" || break ;;
    esac
    base="$(basename "$target")"
    hops=$((hops + 1))
  done
  printf '%s/%s' "$dir" "$base"
}

# 0 when <from> is <want> (a symlinked CLAUDE.md counts) or reaches it through at
# most four import hops. <from> sits at hop <depth>, so its imports are hop
# depth + 1, and the loader follows hops one through four: a file at hop four may
# still BE the target, but its imports are hop five and are never loaded, so they
# are not examined. This is the same bound il_walk reports as `depth`.
il_reaches() {
  local from="$1" want="$2" depth="${3:-0}" imported real
  [[ -f "$from" ]] || return 1
  [[ "$(il_realpath "$from")" == "$want" ]] && return 0
  ((depth >= 4)) && return 1
  while IFS= read -r imported; do
    [[ -z "$imported" ]] && continue
    real="$(il_realpath "$imported")"
    [[ "$real" == "$want" ]] && return 0
    if [[ -f "$real" ]] && il_reaches "$real" "$want" $((depth + 1)); then
      return 0
    fi
  done < <(il_imports_of "$from")
  return 1
}

# Walk the import graph from <file>. One `<status>\t<physical path>` row per
# node, the root first. Statuses:
#   root      the starting file
#   import    an imported file that loads (inside IL_ROOT when it is set)
#   external  an import resolving outside IL_ROOT: listed, never expanded, since
#             the doc gates those behind an approval dialog the audit cannot see
#   missing   an import whose target does not exist
#   depth     an import past the fourth hop, which the loader does not follow
#   seen      a file already reached on this walk, by a back-edge (a cycle) or a
#             second path (a diamond); it is counted once, on its first row
# IL_ROOT, when exported, is the physical repository root the external test uses.
# The visited set is walk-global (IL_SEEN), not per branch: a per-branch set would
# report the shared node of a diamond twice and overstate the loaded size.
il_walk() {
  local file="$1" depth="${2:-0}" real imported ireal
  real="$(il_realpath "$file")"
  if ((depth == 0)); then
    printf 'root\t%s\n' "$real"
    IL_SEEN="|$real|"
  fi
  while IFS= read -r imported; do
    [[ -z "$imported" ]] && continue
    ireal="$(il_realpath "$imported")"
    if [[ "$IL_SEEN" == *"|$ireal|"* ]]; then
      printf 'seen\t%s\n' "$ireal"
      continue
    fi
    IL_SEEN="$IL_SEEN$ireal|"
    if [[ ! -f "$ireal" ]]; then
      printf 'missing\t%s\n' "$ireal"
      continue
    fi
    if [[ -n "${IL_ROOT:-}" && "$ireal" != "$IL_ROOT" && "$ireal" != "$IL_ROOT"/* ]]; then
      printf 'external\t%s\n' "$ireal"
      continue
    fi
    if ((depth + 1 > 4)); then
      printf 'depth\t%s\n' "$ireal"
      continue
    fi
    printf 'import\t%s\n' "$ireal"
    il_walk "$ireal" $((depth + 1))
  done < <(il_imports_of "$real")
}
