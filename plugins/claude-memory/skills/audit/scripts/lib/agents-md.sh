#!/usr/bin/env bash
# agents-md.sh: does the project root's `AGENTS.md` load as the project instructions?
#
# Sourced by the audit scripts that need the answer: discover-instruction-surfaces.sh
# (whether to emit an `agents-md` project row), instruction-load-stats.sh (whether the
# file joins the always-loaded set and answers `--lines`/`--bytes` by default) and
# audit-spine.sh (the header's root-file line). One reader so the three cannot disagree
# about which file the session actually loaded.
#
#   Claim: Claude Code reads a repository's root `AGENTS.md` as the project
#     instructions only when no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md`
#     sits in the working directory or above it; where one does, it reads the
#     `CLAUDE.md` files instead, and the `AGENTS.md` reaches context only through an
#     import or a symlink. A user-scope `~/.claude/CLAUDE.md` and `.claude/rules/`
#     files do not count for that check.
#   Basis: code.claude.com/docs/en/memory, "AGENTS.md" and "When Claude Code reads
#     AGENTS.md": "An `AGENTS.md`, and no `CLAUDE.md` or `CLAUDE.local.md` in your
#     working directory or above it | Your `AGENTS.md`"; "Count, so Claude reads them
#     instead of `AGENTS.md`: a `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md`
#     in your working directory or any directory above it"; "Don't count, and keep
#     loading alongside `AGENTS.md`: your `~/.claude/CLAUDE.md`, your organization's
#     managed `CLAUDE.md`, and `.claude/rules/` files".
#   As of: 2026-09-20.
#   Recheck trigger: that section changes which file names count for the check, or the
#     default **Project instructions** value stops being `claude-md-or-agents-md`.
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
#   agents_md_loads_natively   0 when the root AGENTS.md is read as the project instructions

agents_md_loads_natively() {
  [[ -f AGENTS.md ]] || return 1
  [[ -f CLAUDE.md || -f .claude/CLAUDE.md || -f CLAUDE.local.md ]] && return 1
  return 0
}
