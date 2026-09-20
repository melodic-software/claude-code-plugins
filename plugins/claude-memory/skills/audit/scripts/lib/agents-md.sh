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
# Like the rest of project-scope discovery this is depth-1 at the current directory: a
# `CLAUDE.md` above the repository root is outside what any of these scripts can see.
#
# Functions (pure, none writes anything):
#   agents_md_native_files   one path per line: the AGENTS.md files read as the project
#                            instructions, in the doc's own order. Empty when a CLAUDE.md
#                            displaces them or neither file exists.

agents_md_native_files() {
  [[ -f CLAUDE.md || -f .claude/CLAUDE.md || -f CLAUDE.local.md ]] && return 0
  local f
  for f in AGENTS.md .claude/AGENTS.md; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
  return 0
}
