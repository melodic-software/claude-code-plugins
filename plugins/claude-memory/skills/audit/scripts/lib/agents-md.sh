#!/usr/bin/env bash
# agents-md.sh: which of the project root's AGENTS.md files load as the project instructions?
#
# Sourced by the audit scripts that need the answer: discover-instruction-surfaces.sh
# (whether to emit an `agents-md` project row), instruction-load-stats.sh (whether the
# file joins the always-loaded set and answers `--lines`/`--bytes` by default) and
# audit-spine.sh (the header's root-file line). One reader so the three cannot disagree
# about which file the session actually loaded.
#
#   Claim: Claude Code reads a repository's `AGENTS.md` and `.claude/AGENTS.md` as the
#     project instructions only when no `CLAUDE.md`, `.claude/CLAUDE.md` or
#     `CLAUDE.local.md` sits in the working directory or above it; where one does, it
#     reads the `CLAUDE.md` files instead, and an `AGENTS.md` reaches context only
#     through an import or a symlink. A user-scope `~/.claude/CLAUDE.md` and
#     `.claude/rules/` files do not count for that check. Both AGENTS.md names load,
#     and the doc states no precedence between them.
#   Basis: code.claude.com/docs/en/memory, "AGENTS.md" and "When Claude Code reads
#     AGENTS.md": "An `AGENTS.md`, and no `CLAUDE.md` or `CLAUDE.local.md` in your
#     working directory or above it | Your `AGENTS.md`"; "Count, so Claude reads them
#     instead of `AGENTS.md`: a `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md`
#     in your working directory or any directory above it"; "Don't count, and keep
#     loading alongside `AGENTS.md`: your `~/.claude/CLAUDE.md`, your organization's
#     managed `CLAUDE.md`, and `.claude/rules/` files"; and, for the pair of names,
#     "At session start: every `AGENTS.md` and `.claude/AGENTS.md` in your working
#     directory and the directories above it".
#   As of: 2026-09-20.
#   Recheck trigger: that section changes which file names count for the check, names a
#     precedence between `AGENTS.md` and `.claude/AGENTS.md`, or the default **Project
#     instructions** value stops being `claude-md-or-agents-md`.
#
# Two conditions the caller cannot see are assumed rather than modelled: the default
# `claude-md-or-agents-md` setting (`claude-md-and-agents-md` would load both files,
# `claude-md` neither) and a session able to read AGENTS.md directly at all. Both are
# session state, not repository state.
#
# The AGENTS.md files themselves are depth-1, like the rest of project-scope discovery:
# deeper ones are subtree memory that loads on demand, which this checklist does not cover.
# The displacement test is NOT depth-1, because the doc's condition is not: a `CLAUDE.md`
# anywhere above the repository root suppresses the file just as one beside it does, and a
# check that stopped at the root would report a surface the session never reads.
#
# Functions (pure, none writes anything):
#   agents_md_is_user_root   true when a `.claude` directory is the user root, whose
#                            CLAUDE.md loads alongside an AGENTS.md rather than displacing it.
#   agents_md_displaced      true when a CLAUDE.md name in the current directory or any
#                            directory above it makes Claude Code read it instead.
#   agents_md_native_files   one path per line: the AGENTS.md files read as the project
#                            instructions, in the doc's own order. Empty when a CLAUDE.md
#                            displaces them or neither file exists.

# True when the `.claude` directory given is the user root, whose CLAUDE.md keeps loading
# ALONGSIDE an AGENTS.md instead of displacing it. Both `~/.claude` and a relocated
# `CLAUDE_CONFIG_DIR` answer to it. Compared with `-ef`, by device and inode, because the
# same directory reaches the walk under names that are not equal as strings: a Windows 8.3
# short name, a symlinked home, a case difference.
agents_md_is_user_root() {
  local d="$1"
  [[ -n "${HOME:-}" && -d "$HOME/.claude" && "$d" -ef "$HOME/.claude" ]] && return 0
  [[ -n "${CLAUDE_CONFIG_DIR:-}" && -d "$CLAUDE_CONFIG_DIR" && "$d" -ef "$CLAUDE_CONFIG_DIR" ]]
}

agents_md_displaced() {
  local dir="$PWD" parent
  while :; do
    [[ -f "$dir/CLAUDE.md" || -f "$dir/CLAUDE.local.md" ]] && return 0
    # A bare `CLAUDE.md` in the user's home is a different file from the user root's own and
    # counts like any other, which is why only the `.claude/CLAUDE.md` location is exempted.
    if [[ -f "$dir/.claude/CLAUDE.md" ]]; then
      agents_md_is_user_root "$dir/.claude" || return 0
    fi
    parent="$(dirname "$dir")"
    [[ "$parent" == "$dir" ]] && return 1
    dir="$parent"
  done
}

agents_md_native_files() {
  agents_md_displaced && return 0
  local f
  for f in AGENTS.md .claude/AGENTS.md; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
  return 0
}
