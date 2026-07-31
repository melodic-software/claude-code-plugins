#!/usr/bin/env bash
# list-workspaces.sh — pre-compute probe listing the calling project's teach workspaces.
#
# Exists because the harness composes a skill's `## Pre-computed Context` commands into a
# shell invocation, and the worktree-isolation Bash guard refuses any genuine `$`-expansion
# (`$local`, command substitution, `${VAR:-default}`) — so a pre-compute line carrying the
# derivation inline makes the whole skill fail to load from a worktree-isolated agent. The
# invoking line in SKILL.md now passes plugin variables only, which the harness substitutes
# into literal paths before any shell sees them; the `$`-bearing logic lives here, where a
# shell reads it as an ordinary script.
#
# The project-slug derivation below is an IMPLEMENTATION, not the specification: SKILL.md's
# "Workspace layout" section is normative for it (canonicalize the project path first, then
# basename-slug plus `-` and the first 8 hex chars of that canonical path's sha256). Change
# the spec there first, then mirror it here.
#
# Usage:
#   list-workspaces.sh <project-dir> <plugin-data-dir>
#   list-workspaces.sh --help

set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
list-workspaces.sh — list the teach workspaces belonging to one project.

Usage: list-workspaces.sh <project-dir> <plugin-data-dir>

  <project-dir>       the project root to derive the workspace slug from
  <plugin-data-dir>   the plugin's persistent data directory holding the workspaces

Prints up to 20 `<plugin-data-dir>/<project-slug>/<mode>/<topic>/` paths, one per line,
or `none` when the project has no workspaces. Exits 2 on a usage error.

The `<project-slug>` derivation is specified by SKILL.md's "Workspace layout" section.
EOF
  exit 0
fi

if [[ $# -ne 2 ]]; then
  echo "list-workspaces.sh: expected <project-dir> <plugin-data-dir>; got $# argument(s)" >&2
  exit 2
fi

project_dir="$1"
data_dir="$2"

# Canonicalize BEFORE deriving either half of the slug, so a project reached through a
# symlink and through its real path resolve to one workspace rather than two. The
# `printf` tail keeps the derivation total when neither canonicalizer exists.
canonical_path="$(realpath "$project_dir" 2>/dev/null || readlink -f "$project_dir" 2>/dev/null || printf '%s' "$project_dir")"

basename_slug="$(basename "$canonical_path" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
# The hash discriminates clones and worktrees that share a directory name. `shasum -a 256`
# is the fallback for a stock macOS with no `sha256sum`.
path_hash="$(printf '%s' "$canonical_path" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"

# The `<mode>/<topic>/` pair is one glob rather than an `ls` parse: the trailing slash
# already restricts matches to directories, and an array survives a path containing
# whitespace that a line-oriented pipeline would split. `nullglob` makes a non-match an
# empty array instead of the literal pattern.
shopt -s nullglob
workspaces=("${data_dir}/${basename_slug}-${path_hash}"/*/*/)
shopt -u nullglob

if [[ "${#workspaces[@]}" -eq 0 ]]; then
  echo "none"
else
  printf '%s\n' "${workspaces[@]:0:20}"
fi
exit 0
