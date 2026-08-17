#!/usr/bin/env bash
# list-workspaces.sh — probe listing the calling project's teach workspaces across roots.
#
# Exists because the harness composes a skill's `## Pre-computed Context` commands into a
# shell invocation, and the worktree-isolation Bash guard refuses any genuine `$`-expansion
# (`$local`, command substitution, `${VAR:-default}`) — so a pre-compute line carrying the
# derivation inline makes the whole skill fail to load from a worktree-isolated agent. The
# invoking line in SKILL.md passes plugin variables only, which the harness substitutes
# into literal paths before any shell sees them; the `$`-bearing logic lives here, where a
# shell reads it as an ordinary script. `${user_config.*}` tokens must NEVER reach the
# pre-compute line either — a surviving literal is a bash `bad substitution` that kills the
# whole call — so the skill body resolves the workspace-root ladder and re-invokes this
# script with the resolved roots as ordinary arguments.
#
# The project-slug derivation below is an IMPLEMENTATION, not the specification: SKILL.md's
# "Workspace layout" section is normative for it (canonicalize the project path first —
# hoisting a linked git worktree to its main repository via `git rev-parse
# --git-common-dir` — then basename-slug plus `-` and the first 8 hex chars of that
# canonical path's sha256). Change the spec there first, then mirror it here.
#
# Usage:
#   list-workspaces.sh <project-dir> <root>...
#   list-workspaces.sh --default-root
#   list-workspaces.sh --help

set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
list-workspaces.sh — list the teach workspaces belonging to one project.

Usage: list-workspaces.sh <project-dir> <root>...
       list-workspaces.sh --default-root

  <project-dir>   the project root to derive the workspace slug from
  <root>...       one or more workspace roots to scan (plugin data dir,
                  configured root, OS Documents home, ...). A root that is
                  empty or still carries a literal `${user_config...}`
                  placeholder is skipped as unset.

Prints up to 20 `<root>/<project-slug>/<mode>/<topic>/` paths, one per line
(pre-ladder per-worktree slugs are listed too, marked `(legacy worktree slug)`),
or `none` when the project has no workspaces. Exits 2 on a usage error —
including when every supplied root was filtered out as unset.

--default-root prints the OS-default topic root — the platform Documents
directory plus `Claude Learning/` — ONLY when that Documents directory already
exists and is not `$HOME` itself (unconfigured `xdg-user-dir` echoes `$HOME`).
Exits 1, printing nothing, when no eligible default exists. Never creates
anything.

The `<project-slug>` derivation is specified by SKILL.md's "Workspace layout".
EOF
  exit 0
fi

canonicalize() {
  realpath "$1" 2>/dev/null || readlink -f "$1" 2>/dev/null || printf '%s' "$1"
}

if [[ "${1:-}" == "--default-root" ]]; then
  docs=""
  case "$(uname -s)" in
  Darwin)
    docs="$HOME/Documents"
    ;;
  MINGW* | MSYS* | CYGWIN*)
    # Resolve the Documents KNOWN FOLDER native-side (it may be OneDrive-redirected), then
    # convert to POSIX form for Git Bash — fail-loud, per docs/conventions/windows-path-emit/.
    win="$(powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('MyDocuments')" 2>/dev/null | tr -d '\r')"
    [[ -n "$win" ]] || exit 1
    docs="$(cygpath -u "$win" 2>/dev/null)" || exit 1
    ;;
  *)
    command -v xdg-user-dir >/dev/null 2>&1 || exit 1
    docs="$(xdg-user-dir DOCUMENTS 2>/dev/null)" || exit 1
    ;;
  esac
  [[ -n "$docs" && -d "$docs" ]] || exit 1
  # The ≠ $HOME guard: an unconfigured/headless box answers the Documents query with $HOME
  # itself; treating that as Documents would scatter workspaces across the home directory.
  [[ "$(canonicalize "$docs")" != "$(canonicalize "$HOME")" ]] || exit 1
  printf '%s/Claude Learning\n' "$(canonicalize "$docs")"
  exit 0
fi

if [[ $# -lt 2 ]]; then
  echo "list-workspaces.sh: expected <project-dir> <root>...; got $# argument(s)" >&2
  exit 2
fi

project_dir="$1"
shift

# Filter the roots: a surviving `${user_config...}` literal means that key is unset, and an
# empty string is an unset harness variable — both are skipped, not treated as paths.
roots=()
for r in "$@"; do
  [[ -n "$r" && "$r" != *\$\{* ]] && roots+=("$r")
done
if [[ "${#roots[@]}" -eq 0 ]]; then
  echo "list-workspaces.sh: every supplied root was empty or an unset placeholder" >&2
  exit 2
fi

# Canonicalize BEFORE deriving either half of the slug, so a project reached through a
# symlink and through its real path resolve to one workspace rather than two. The
# `printf` tail keeps the derivation total when neither canonicalizer exists.
canonical_path="$(canonicalize "$project_dir")"

# A linked git worktree hoists to its MAIN repository, so every worktree of one repo shares
# one workspace. `--git-common-dir` names the main repo's `.git`; when that differs from the
# worktree's own `.git`, the directory holding it is the canonical project. Anything odd
# (no git, bare repo, common dir not named `.git`) falls back to the plain canonical path.
legacy_canonical=""
if command -v git >/dev/null 2>&1; then
  common="$(git -C "$canonical_path" rev-parse --git-common-dir 2>/dev/null)" || common=""
  if [[ -n "$common" ]]; then
    [[ "$common" == /* ]] || common="$canonical_path/$common"
    common="$(canonicalize "$common")"
    if [[ "$(basename "$common")" == ".git" ]]; then
      main_dir="$(dirname "$common")"
      if [[ "$main_dir" != "$canonical_path" ]]; then
        legacy_canonical="$canonical_path"
        canonical_path="$main_dir"
      fi
    fi
  fi
fi

derive_slug() {
  local basename_slug path_hash
  basename_slug="$(basename "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
  # The hash discriminates clones that share a directory name. `shasum -a 256` is the
  # fallback for a stock macOS with no `sha256sum`.
  path_hash="$(printf '%s' "$1" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
  printf '%s-%s' "$basename_slug" "$path_hash"
}

slug="$(derive_slug "$canonical_path")"
legacy_slug=""
[[ -n "$legacy_canonical" ]] && legacy_slug="$(derive_slug "$legacy_canonical")"

# The `<mode>/<topic>/` pair is one glob rather than an `ls` parse: the trailing slash
# already restricts matches to directories, and an array survives a path containing
# whitespace that a line-oriented pipeline would split. `nullglob` makes a non-match an
# empty array instead of the literal pattern. Roots are scanned in the order given —
# callers pass them ladder-highest first, so the cap keeps the highest-precedence hits.
lines=()
shopt -s nullglob
for root in "${roots[@]}"; do
  for w in "${root}/${slug}"/*/*/; do
    lines+=("$w")
  done
  if [[ -n "$legacy_slug" ]]; then
    for w in "${root}/${legacy_slug}"/*/*/; do
      lines+=("$w (legacy worktree slug)")
    done
  fi
done
shopt -u nullglob

if [[ "${#lines[@]}" -eq 0 ]]; then
  echo "none"
else
  printf '%s\n' "${lines[@]:0:20}"
fi
exit 0
