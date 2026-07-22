#!/usr/bin/env bash
# worktree-create.sh — shared worktree-creation helper (Phase A).
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
#   - Phase B (gated on two upstream Claude Code behaviors still being verified):
#     the `WorktreeCreate` hook becomes a thin stdin adapter (parse `.name`) that
#     calls this same helper.
# The flag CLI is the stable seam both consumers share.
#
# Refuse-with-guidance contract: when the external root is unconfigured the
# helper refuses (exit 3) and never falls back to Claude Code's in-repo
# `.claude/worktrees/`, whose nested placement triggers the confirmed, unfixed
# CLAUDE.md/rules double-load bug.
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
$PROG — shared worktree-creation helper.

Usage:
  $PROG --name <name> --root <dir> [--base-ref fresh|head] [--repo-dir <dir>]

Options:
  --name <name>       Branch/worktree name (e.g. feat/my-feature). Required.
  --root <dir>        External worktree root. Required and must be configured;
                      an empty value or an unexpanded \${user_config.*} token
                      makes the helper refuse (exit 3) rather than fall back to
                      the in-repo .claude/worktrees/ default (a known Claude
                      Code double-load bug).
  --base-ref <ref>    fresh (default) branches from the remote default branch;
                      head branches from the repo's current HEAD. Omitted
                      defaults to fresh; the caller passes the effective Claude
                      worktree.baseRef setting (a settings.json key, not git config).
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

# need_value <flag> — guard against a value-taking flag given as the last token
# with no argument. Without this, `shift 2` on a single remaining positional
# fails and leaves $# unchanged, spinning the loop forever.
need_value() {
  if [[ $# -lt 2 ]]; then
    printf '%s: %s requires a value\n' "$PROG" "$1" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) need_value "$@"; name="$2"; shift 2 ;;
    --root) need_value "$@"; root="$2"; shift 2 ;;
    --base-ref) need_value "$@"; base_ref="$2"; shift 2 ;;
    --repo-dir) need_value "$@"; repo_dir="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%s: unknown argument: %s\n' "$PROG" "$1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$name" ]]; then
  printf '%s: --name is required\n' "$PROG" >&2
  exit 2
fi

# Validate the name up front against the EnterWorktree schema: max 64 chars, and
# each '/'-separated segment contains only letters, digits, dots, underscores,
# and dashes. This is a strict subset of what git refs allow, so a validated name
# is always a creatable branch — reject invalid names loudly (exit 2) here rather
# than let `git worktree add` fail opaquely downstream. The branch is used
# verbatim; only the directory slug transforms it.
if (( ${#name} > 64 )); then
  printf '%s: --name %q exceeds 64 characters\n' "$PROG" "$name" >&2
  exit 2
fi
if [[ ! "$name" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]]; then
  printf '%s: --name %q is not a valid worktree/branch name (each /-separated segment: letters, digits, dots, underscores, dashes only)\n' "$PROG" "$name" >&2
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
placement triggers Claude Code's CLAUDE.md/rules double-load bug.
EOF
  exit 3
fi

# Resolve the source repository top level.
if ! toplevel=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null); then
  printf '%s: --repo-dir is not inside a git repository: %s\n' "$PROG" "$repo_dir" >&2
  exit 4
fi

# parse_owner_repo <url> — derive an `owner<TAB>repo` pair from a remote URL for
# the directory name. Sets globals `owner` and `repo`. Handles the shapes we see:
#   git@host:owner/repo.git · https://host/owner/repo.git · ssh://git@host/owner/repo
#   GitLab subgroups (group/subgroup/repo → owner=subgroup)
#   Azure DevOps (…/org/project/_git/repo and v3/org/project/repo → owner=project)
# It never fails: with fewer than two usable path segments, owner is left empty
# and the caller falls back to the repo-dir name.
parse_owner_repo() {
  local url="$1" path
  owner=""; repo=""
  # Reduce to the path portion. Scheme URLs (scheme://host/path) and scp syntax
  # (git@host:path) delimit the host differently, so branch on which is present.
  path="$url"
  if [[ "$path" == *"://"* ]]; then
    path="${path#*://}"        # strip scheme://
    path="${path#*/}"          # strip host[:port] up to the first '/'
  elif [[ "$path" == *:* ]]; then
    path="${path#*:}"          # scp-like git@host:owner/repo -> owner/repo
  fi
  path="${path%.git}"
  path="${path%/}"

  # Split into non-empty segments, dropping Azure's `_git` marker and a leading
  # `v3` (Azure SSH) so the meaningful org/project/repo tail remains.
  local -a seg=() parts
  IFS='/' read -r -a parts <<<"$path"
  local p
  for p in "${parts[@]}"; do
    [[ -z "$p" || "$p" == "_git" || "$p" == "v3" ]] && continue
    seg+=("$p")
  done

  local n=${#seg[@]}
  if (( n >= 2 )); then
    repo="${seg[n-1]}"
    owner="${seg[n-2]}"
  elif (( n == 1 )); then
    repo="${seg[0]}"
  fi
}

# owner/repo from the origin remote when present; otherwise fall back to the
# repository directory name (owner omitted).
owner=""
repo=""
if origin_url=$(git -C "$toplevel" remote get-url origin 2>/dev/null); then
  parse_owner_repo "$origin_url"
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

# `git -C "$toplevel" worktree add` resolves a relative target against the repo
# top level, so a relative root (e.g. `worktrees`) always lands inside the repo.
# Anchor it to $toplevel up front so the containment check below sees the real
# target rather than an unrooted string whose ancestor walk never reaches the repo.
[[ "$worktree_path" != /* && "$worktree_path" != ?:* ]] && worktree_path="$toplevel/$worktree_path"

# Reject placement inside any git repository — a working tree, a normal repo's
# .git directory, or a bare clone. Keeping worktrees OUT of every repository is
# the helper's core purpose: a worktree nested inside a working tree reintroduces
# the CLAUDE.md/rules double-load bug for whichever checkout owns the ancestor,
# and one dropped inside a .git or bare directory mixes the checkout into git
# metadata. The unconfigured-root refuse above does not catch a root explicitly
# pointed inside a repository (e.g. the old .claude/worktrees/ path, a root under
# a sibling clone, or a path beneath a .git directory), so ask git about the
# target's location: walk up from the target's parent to the nearest existing
# ancestor. Probing the parent, never the target itself, keeps an already-created
# worktree at $worktree_path from matching its own top level — that case is the
# "already exists" error below. `--show-toplevel` catches work-tree ancestors (and
# by top-level equality tells the source repo from a foreign clone);
# `--is-inside-git-dir` catches .git and bare-repo ancestors, which have no work
# tree and so report no top level. Both come from `rev-parse`, so the check is
# immune to path-format differences (drive-letter spelling, symlinks) that defeat
# a raw string prefix test.
probe="${worktree_path%/*}"
while [[ ! -e "$probe" ]]; do
  parent="${probe%/*}"
  [[ "$parent" == "$probe" ]] && break
  probe="$parent"
done
if [[ -e "$probe" ]]; then
  location=""
  detail=""
  if target_top=$(git -C "$probe" rev-parse --show-toplevel 2>/dev/null) && [[ -n "$target_top" ]]; then
    if [[ "$target_top" == "$toplevel" ]]; then
      location="inside the repository"
    else
      location="inside another git working tree"
    fi
    detail="  checkout: $target_top"
  elif [[ "$(git -C "$probe" rev-parse --is-inside-git-dir 2>/dev/null)" == "true" ]]; then
    location="inside a git directory"
    detail="  git dir:  $(git -C "$probe" rev-parse --absolute-git-dir 2>/dev/null)"
  fi
  if [[ -n "$location" ]]; then
    cat >&2 <<EOF
$PROG: worktree target is $location — refusing to create a worktree.

  target:   $worktree_path
$detail

Set the source-control plugin's \`worktree_root\` directory key to an external
root (a path OUTSIDE every repository, on the same drive as the repo on Windows),
then retry.

Not creating inside a checkout or a git directory: that placement triggers Claude
Code's CLAUDE.md/rules double-load bug and mixes the worktree into git metadata.
EOF
    exit 3
  fi
fi

if [[ -e "$worktree_path" ]]; then
  printf '%s: target path already exists: %s\n' "$PROG" "$worktree_path" >&2
  exit 4
fi

# Base-ref resolution. The caller owns policy: pass --base-ref (fresh|head),
# defaulting to fresh when omitted. Claude Code's `worktree.baseRef` lives in
# settings.json (not git config), so the helper does not probe it — the skill
# reads the effective setting and passes it through this flag.
[[ -z "$base_ref" ]] && base_ref="fresh"

case "$base_ref" in
  head)
    base_commit="HEAD"
    ;;
  fresh)
    # Resolve the remote's default branch symbolically (never hardcode
    # origin/main — the portability lint forbids it). When origin/HEAD is not cached
    # locally, fall back to local HEAD (matching Claude Code's documented
    # behavior) but warn loudly: "fresh" promises the remote default branch, so a
    # silent fall-through to HEAD could carry unpushed local commits the caller
    # did not want.
    if head_ref=$(git -C "$toplevel" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null); then
      base_commit="$head_ref"
    else
      base_commit="HEAD"
      printf '%s: warning: --base-ref fresh could not resolve the remote default branch (origin/HEAD not set); branching from local HEAD instead. Run: git remote set-head origin --auto  to cache it.\n' "$PROG" >&2
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
# real .gitignore also ignores (the documented intersection). NUL-delimited
# (`-z` / `read -d ''`) so paths with spaces, newlines, or quote-triggering
# characters are not dropped or mangled.
include_file="$toplevel/.worktreeinclude"
copied=0
copy_failed=0
if [[ -f "$include_file" ]]; then
  while IFS= read -r -d '' rel; do
    [[ -z "$rel" ]] && continue
    git -C "$toplevel" check-ignore -q -- "$rel" || continue
    src="$toplevel/$rel"
    [[ -f "$src" ]] || continue
    dest="$worktree_path/$rel"
    if mkdir -p "$(dirname "$dest")" && cp -p "$src" "$dest"; then
      copied=$((copied + 1))
    else
      copy_failed=$((copy_failed + 1))
      printf '%s: warning: failed to copy .worktreeinclude file: %s\n' "$PROG" "$rel" >&2
    fi
  done < <(git -C "$toplevel" ls-files -o -i -z --exclude-from="$include_file")
  printf '%s: copied %d .worktreeinclude file(s) into the worktree\n' "$PROG" "$copied" >&2
  if (( copy_failed > 0 )); then
    printf '%s: %d .worktreeinclude file(s) failed to copy — the worktree at %s exists but is missing expected local files\n' \
      "$PROG" "$copy_failed" "$worktree_path" >&2
    exit 4
  fi
fi

printf '%s: created worktree on branch %q (base %s)\n' "$PROG" "$name" "$base_ref" >&2
printf '%s\n' "$worktree_path"
