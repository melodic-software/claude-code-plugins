#!/usr/bin/env bash
# worktree-create.sh — shared worktree-creation helper (issue #399, Phase A).
#
# Single owner of worktree creation for this plugin: external-root path
# computation `<root>/<owner>-<repo>-<slug>`, slug sanitization, base-ref
# resolution (`worktree.baseRef` fresh|head), `git worktree add`, and the
# `.worktreeinclude` local-file copy. The copy Claude Code performs for its
# native worktrees (EnterWorktree / --worktree) is bypassed when a worktree is
# created with `git worktree add` directly, so this helper reimplements it.
#
# Consumers:
#   - Phase A (now): the `/worktree create` skill routes through this helper,
#     then calls EnterWorktree(path:) on the printed path to enter the worktree.
#   - Phase B (gated on upstream #77566 + #78212): the `WorktreeCreate` hook
#     becomes a thin stdin adapter (parse `.name`) that calls this same helper.
# The flag CLI is the stable seam both consumers share.
#
# Refuse-with-guidance contract: when the external root is unconfigured the
# helper refuses (exit 3) and never falls back to Claude Code's in-repo
# `.claude/worktrees/`, whose nested placement triggers the CLAUDE.md/rules
# double-load bug (#400, upstream anthropics/claude-code #29599 / #23565).
#
# Output contract: on success the created worktree path is the SOLE stdout line
# (machine-parseable); all diagnostics go to stderr.
#
# Exit codes:
#   0  success — worktree created; path on stdout
#   2  usage error — unknown/missing flag
#   3  refuse — external root unconfigured (guidance on stderr); nothing created
#   4  environment error — not a git repo, or `git worktree add` failed

set -uo pipefail

PROG=${0##*/}

usage() {
  cat >&2 <<EOF
$PROG — shared worktree-creation helper (issue #399).

Usage:
  $PROG --name <name> --root <dir> [--base-ref fresh|head] [--repo-dir <dir>]

Options:
  --name <name>       Branch/worktree name (e.g. feat/my-feature). Required.
  --root <dir>        External worktree root. Required and must be configured;
                      an empty value or an unexpanded \${user_config.*} token
                      makes the helper refuse (exit 3) rather than fall back to
                      the in-repo .claude/worktrees/ default (#400).
  --base-ref <ref>    fresh (default) branches from the remote default branch;
                      head branches from the repo's current HEAD. When omitted,
                      the repo's worktree.baseRef git config is used, else fresh.
  --repo-dir <dir>    Source repository directory. Default: current directory.
  -h, --help          Show this help.

On success the created worktree path is printed as the sole stdout line, for the
caller to feed to EnterWorktree(path:).

Exit codes: 0 success · 2 usage · 3 refuse (root unconfigured) · 4 environment.
EOF
}

name=""
root=""
base_ref=""
repo_dir="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) name="${2:-}"; shift 2 ;;
    --root) root="${2:-}"; shift 2 ;;
    --base-ref) base_ref="${2:-}"; shift 2 ;;
    --repo-dir) repo_dir="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%s: unknown argument: %s\n' "$PROG" "$1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$name" ]]; then
  printf '%s: --name is required\n' "$PROG" >&2
  exit 2
fi

# Refuse-with-guidance: unconfigured root. Treat an empty value or an unexpanded
# ${user_config.*} token (what Claude Code leaves when the key is unset) as unset.
# SC2016: the single-quoted ${user_config token is matched literally on purpose —
# we are detecting the UNexpanded placeholder, so expansion here would be a bug.
# shellcheck disable=SC2016
if [[ -z "$root" || "$root" == *'${user_config'* ]]; then
  cat >&2 <<EOF
$PROG: worktree root is not configured — refusing to create a worktree.

Set the source-control plugin's \`worktree_root\` directory key to an external
root (a path OUTSIDE every repository, on the same drive as the repo on Windows),
then retry. Run the worktree setup skill, or configure it via \`/plugin\`.

Not falling back to the in-repo .claude/worktrees/ default: that nested
placement triggers Claude Code's CLAUDE.md/rules double-load bug (#400).
EOF
  exit 3
fi

# Resolve the source repository top level.
if ! toplevel=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null); then
  printf '%s: --repo-dir is not inside a git repository: %s\n' "$PROG" "$repo_dir" >&2
  exit 4
fi

# owner/repo from the origin remote when present; otherwise fall back to the
# repository directory name (owner omitted).
owner=""
repo=""
if origin_url=$(git -C "$toplevel" remote get-url origin 2>/dev/null); then
  # Strip a trailing .git and any trailing slash, then take the last two
  # path/colon-separated segments as owner/repo. Handles:
  #   git@host:owner/repo.git · https://host/owner/repo.git · ssh://git@host/owner/repo
  stripped="${origin_url%.git}"
  stripped="${stripped%/}"
  repo="${stripped##*/}"
  rest="${stripped%/*}"
  owner="${rest##*[:/]}"
fi
if [[ -z "$repo" ]]; then
  repo="${toplevel##*/}"
  owner=""
fi

# Sanitize the name into a filesystem-safe slug: '/' and any character outside
# [A-Za-z0-9._-] become '-', runs of '-' collapse, leading/trailing '-' trim.
slug="$name"
slug="${slug//[^A-Za-z0-9._-]/-}"
while [[ "$slug" == *--* ]]; do slug="${slug//--/-}"; done
slug="${slug#-}"
slug="${slug%-}"
if [[ -z "$slug" ]]; then
  printf '%s: --name %q sanitizes to an empty slug\n' "$PROG" "$name" >&2
  exit 2
fi

if [[ -n "$owner" ]]; then
  dirname="${owner}-${repo}-${slug}"
else
  dirname="${repo}-${slug}"
fi
worktree_path="${root%/}/${dirname}"

if [[ -e "$worktree_path" ]]; then
  printf '%s: target path already exists: %s\n' "$PROG" "$worktree_path" >&2
  exit 4
fi

# Base-ref resolution. Precedence: explicit --base-ref, then the repo's
# worktree.baseRef config, then the "fresh" default.
if [[ -z "$base_ref" ]]; then
  base_ref=$(git -C "$toplevel" config worktree.baseRef 2>/dev/null || true)
fi
[[ -z "$base_ref" ]] && base_ref="fresh"

case "$base_ref" in
  head)
    base_commit="HEAD"
    ;;
  fresh)
    # Resolve the remote's default branch symbolically (never hardcode
    # origin/main — portability-lint #531). Fall back to local HEAD when the
    # remote default is not cached, matching Claude Code's documented behavior.
    if head_ref=$(git -C "$toplevel" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null); then
      base_commit="$head_ref"
    else
      base_commit="HEAD"
    fi
    ;;
  *)
    printf '%s: --base-ref must be fresh or head, got: %q\n' "$PROG" "$base_ref" >&2
    exit 2
    ;;
esac

if ! git -C "$toplevel" worktree add -b "$name" "$worktree_path" "$base_commit" >&2; then
  printf '%s: git worktree add failed (branch %q may already exist)\n' "$PROG" "$name" >&2
  exit 4
fi

# Reimplement Claude Code's .worktreeinclude copy: files that match a
# .worktreeinclude pattern AND are also gitignored are copied one-way into the
# new worktree. `ls-files -o -i --exclude-from` yields untracked files matching
# the include patterns; `check-ignore -q` filters that down to the ones the
# real .gitignore also ignores (the documented intersection).
include_file="$toplevel/.worktreeinclude"
copied=0
if [[ -f "$include_file" ]]; then
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    git -C "$toplevel" check-ignore -q -- "$rel" || continue
    src="$toplevel/$rel"
    [[ -f "$src" ]] || continue
    dest="$worktree_path/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -p "$src" "$dest"
    copied=$((copied + 1))
  done < <(git -C "$toplevel" ls-files -o -i --exclude-from="$include_file")
  printf '%s: copied %d .worktreeinclude file(s) into the worktree\n' "$PROG" "$copied" >&2
fi

printf '%s: created worktree on branch %q (base %s)\n' "$PROG" "$name" "$base_ref" >&2
printf '%s\n' "$worktree_path"
