#!/usr/bin/env bash
# agents-md.sh: which of the project root's AGENTS.md files load as the project instructions?
# One reader so the audit scripts cannot disagree about which file the session loaded.
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
# Assumed, not modeled (session state): the default `claude-md-or-agents-md` setting,
# and a session able to read AGENTS.md at all.
#
# The AGENTS.md files are depth-1, but the displacement test walks above the repository
# root, because a `CLAUDE.md` up there suppresses the file just as one beside it does.

# The user root's CLAUDE.md loads alongside an AGENTS.md instead of displacing it. `-ef`
# compares by inode: 8.3 short names, symlinked homes, and case differences reach the walk.
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
