#!/usr/bin/env bash
# instruction-load-stats.sh — how much instruction content actually loads at launch.
#
# The C1 line budget is stated per CLAUDE.md file, but what Claude Code loads is
# the file WITH its `@path` imports expanded: "imported files still load and enter
# the context window at launch" (memory doc). A one-line CLAUDE.md that imports a
# 500-line AGENTS.md is a 500-line file for the budget's purpose, so a raw `wc -l`
# on the root file measures the wrong thing. This script measures the expanded
# content, using the same import parser the nested-AGENTS.md check uses
# (lib/imports.sh), so the two never disagree about what an import is.
#
# What is counted is the content that loads: block-level HTML comments are
# stripped (the doc says they are removed before injection; comments inside a
# fenced code block are kept, since a fence is code). Lines are non-blank lines
# after that strip; bytes are of the LF-normalized stripped content; tokens are
# bytes / 4, which is an ESTIMATE and is labelled as one wherever it is printed.
# A measured figure is the `context-budget` plugin's job when it is installed.
#
# The always-loaded set for --tokens and --breakdown is every root memory file
# that exists (CLAUDE.md, .claude/CLAUDE.md, CLAUDE.local.md) plus every
# `.claude/rules/**/*.md` without `paths:` frontmatter, and the same two shapes
# in the user scope (${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md and its
# rules/), which load in every session of every project. Each root has its
# imports expanded. A file reached from two roots is counted once. A project
# import that resolves outside the repository is listed as `external` and never
# expanded: the loader gates those behind an approval dialog whose answer this
# script cannot see. A user-scope import is expanded within the config dir.
#
# OUTPUT CONTRACT: --lines, --bytes, and --tokens print exactly one integer and
# always exit 0 (a missing file reports 0), because the pre-compute lines that
# call them inject stdout verbatim into the skill body. --breakdown prints TSV.
# A bad mode exits 2.
#
# Usage:
#   instruction-load-stats.sh --lines [--file <path>]   expanded loaded lines of one root file
#   instruction-load-stats.sh --bytes [--file <path>]   expanded loaded bytes of one root file
#   instruction-load-stats.sh --tokens                  estimated tokens of the always-loaded set
#   instruction-load-stats.sh --breakdown               TSV: status, lines, bytes, path; then TOTAL
#   instruction-load-stats.sh --help
#
# --file defaults to CLAUDE.md, then .claude/CLAUDE.md, whichever exists first.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/imports.sh
source "$SCRIPT_DIR/lib/imports.sh"

usage() {
  cat <<'EOF'
instruction-load-stats.sh — size of the instruction layer as Claude Code loads it.

Usage: instruction-load-stats.sh (--lines|--bytes) [--file <path>]
       instruction-load-stats.sh (--tokens|--breakdown|--help)

  --lines       non-blank loaded lines of one root file with its @imports expanded
  --bytes       loaded bytes of that file with its @imports expanded
  --file <p>    the root file (default: CLAUDE.md, else .claude/CLAUDE.md)
  --tokens      estimated tokens (bytes / 4) of the whole always-loaded set
  --breakdown   one TSV row per loaded file: status, lines, bytes, path; then TOTAL
  --help        this message

Block-level HTML comments are stripped before counting; comments inside fenced
code are kept. Imports follow the memory doc: relative to the importing file,
four hops deep, code spans and fences skipped. An import outside the repository
is listed as external and not expanded. Stat modes print one integer, exit 0.
EOF
}

mode=""
file_arg=""
while (($# > 0)); do
  case "$1" in
  --lines | --bytes | --tokens | --breakdown) mode="$1" ;;
  --file)
    shift
    file_arg="${1:-}"
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
  shift
done
[[ -n "$mode" ]] || {
  usage >&2
  exit 2
}

repo_root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
[[ -n "$repo_root" ]] || repo_root="$PWD"
cd "$repo_root" || exit 2
PROJECT_ROOT="$(il_realpath "$repo_root")"
# The external-import boundary for the walk in progress: the repository for
# project-scope roots, the config dir for user-scope ones (a user file's imports
# load without the approval dialog, so they are expanded).
IL_ROOT="$PROJECT_ROOT"
export IL_ROOT

# Loaded content of one file: LF-normalized, block-level HTML comments removed
# outside fenced code. A comment ends at the first `-->` after its own opener; an
# opener that never closes is content, so it is flushed at EOF rather than eaten.
loaded_content() {
  tr -d '\r' <"$1" | LC_ALL=C awk '
    function emit(s) { print s }
    function uncomment(s,   p, q, out) {
      while ((p = index(s, "<!--")) > 0) {
        out = out substr(s, 1, p - 1)
        q = index(substr(s, p + 4), "-->")
        if (q == 0) { incomment = 1; pending = substr(s, p) "\n"; return out }
        s = substr(s, p + q + 6)
      }
      return out s
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
    /<!--/ { emit(uncomment($0)); next }
    { print }
    END { printf "%s", pending }
  '
}

count_lines() { loaded_content "$1" | grep -c '[^[:space:]]'; }
count_bytes() { loaded_content "$1" | wc -c; }

# The always-loaded roots of one scope: the scope's CLAUDE.md files that exist,
# then its unscoped rules. One `<scope>\t<path>` per line. The project scope is
# the repository; the user scope is ${CLAUDE_CONFIG_DIR:-$HOME/.claude}, whose
# CLAUDE.md and rules load in every session of every project (memory doc, "User
# instructions" and "User-level rules"), so an estimate of the always-loaded set
# that omitted them would be systematically low wherever that layer is non-empty.
# A file both scopes reach (a repository rooted at `~`) is counted once, by
# physical path, in the walk below.
scope_roots() {
  local scope="$1" base="$2" f
  if [[ "$scope" == "project" ]]; then
    for f in CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md; do
      [[ -f "$f" ]] && printf '%s\t%s\n' "$scope" "$f"
    done
  else
    [[ -f "$base/CLAUDE.md" ]] && printf '%s\t%s\n' "$scope" "$base/CLAUDE.md"
  fi
  [[ -d "$base/rules" ]] || return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    is_unscoped_rule "$f" && printf '%s\t%s\n' "$scope" "$f"
  done < <(find "$base/rules" -name '*.md' -type f 2>/dev/null | LC_ALL=C sort)
}

always_loaded_roots() {
  scope_roots project .claude
  local user_dir="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
  [[ -n "${CLAUDE_CONFIG_DIR:-}${HOME:-}" && -d "$user_dir" ]] || return 0
  scope_roots user "$user_dir"
}

# A rule loads unconditionally unless its frontmatter declares `paths:`.
is_unscoped_rule() {
  local head1
  head1=$(head -1 "$1" | tr -d '\r')
  [[ "$head1" == "---" ]] || return 0
  tr -d '\r' <"$1" | awk 'NR==1{next} /^---$/{exit} {print}' | grep -q '^paths:' && return 1
  return 0
}

relpath() {
  local p="$1"
  [[ "$p" == "$PROJECT_ROOT"/* ]] && p="${p#"$PROJECT_ROOT"/}"
  printf '%s' "$p"
}

# --- single-file modes -------------------------------------------------------
if [[ "$mode" == "--lines" || "$mode" == "--bytes" ]]; then
  target="$file_arg"
  if [[ -z "$target" ]]; then
    for f in CLAUDE.md .claude/CLAUDE.md; do
      [[ -f "$f" ]] && {
        target="$f"
        break
      }
    done
  fi
  if [[ -z "$target" || ! -f "$target" ]]; then
    echo 0
    exit 0
  fi
  total=0
  while IFS=$'\t' read -r status path; do
    case "$status" in
    root | import)
      if [[ "$mode" == "--lines" ]]; then n=$(count_lines "$path"); else n=$(count_bytes "$path"); fi
      total=$((total + n))
      ;;
    *) ;;
    esac
  done < <(il_walk "$target")
  printf '%s\n' "$total"
  exit 0
fi

# --- whole-set modes ---------------------------------------------------------
declare -A counted=()
rows=()
lines_total=0
bytes_total=0
while IFS=$'\t' read -r scope root; do
  [[ -n "$root" ]] || continue
  if [[ "$scope" == "user" ]]; then
    IL_ROOT="$(il_realpath "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}")"
  else
    IL_ROOT="$PROJECT_ROOT"
  fi
  while IFS=$'\t' read -r status path; do
    [[ -n "$path" ]] || continue
    case "$status" in
    root | import)
      [[ -n "${counted[$path]:-}" ]] && continue
      counted[$path]=1
      l=$(count_lines "$path")
      b=$(count_bytes "$path")
      lines_total=$((lines_total + l))
      bytes_total=$((bytes_total + b))
      rows+=("$(printf '%s\t%s\t%s\t%s\t%s' "$scope" "$status" "$l" "$b" "$(relpath "$path")")")
      ;;
    *)
      key="$status $path"
      [[ -n "${counted[$key]:-}" ]] && continue
      counted[$key]=1
      rows+=("$(printf '%s\t%s\t0\t0\t%s' "$scope" "$status" "$(relpath "$path")")")
      ;;
    esac
  done < <(il_walk "$root")
done < <(always_loaded_roots)
IL_ROOT="$PROJECT_ROOT"

tokens=$((bytes_total / 4))
if [[ "$mode" == "--tokens" ]]; then
  printf '%s\n' "$tokens"
  exit 0
fi

printf 'scope\tstatus\tlines\tbytes\tpath\n'
for row in ${rows[@]+"${rows[@]}"}; do printf '%s\n' "$row"; done
printf 'TOTAL\t%s\t%s\t~%s tokens (bytes/4, estimate)\n' "$lines_total" "$bytes_total" "$tokens"
exit 0
