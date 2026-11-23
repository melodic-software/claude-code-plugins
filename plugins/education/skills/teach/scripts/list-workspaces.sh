#!/usr/bin/env bash

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
(a workspace whose MISSION.md has a `Status: closed` line is marked `(closed)`;
pre-ladder per-worktree slugs are listed too, marked `(legacy worktree slug)`),
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
  (cd "$1" 2>/dev/null && pwd -P) ||
    realpath "$1" 2>/dev/null || readlink -f "$1" 2>/dev/null ||
    printf '%s' "$1"
}

if [[ "${1:-}" == "--default-root" ]]; then
  case "$(uname -s)" in
  Darwin)
    docs="$HOME/Documents"
    ;;
  MINGW* | MSYS* | CYGWIN*)
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
  docs_canonical="$(canonicalize "$docs")"
  [[ "$docs_canonical" != "$(canonicalize "$HOME")" ]] || exit 1
  printf '%s/Claude Learning\n' "$docs_canonical"
  exit 0
fi

if [[ $# -lt 2 ]]; then
  echo "list-workspaces.sh: expected <project-dir> <root>...; got $# argument(s)" >&2
  exit 2
fi

project_dir="$1"
shift

roots=()
for r in "$@"; do
  [[ -n "$r" && "$r" != *\$\{* ]] && roots+=("$r")
done
if [[ "${#roots[@]}" -eq 0 ]]; then
  echo "list-workspaces.sh: every supplied root was empty or an unset placeholder" >&2
  exit 2
fi

canonical_path="$(canonicalize "$project_dir")"

legacy_canonical=""
if command -v git >/dev/null 2>&1; then
  common="$(git -C "$canonical_path" rev-parse --git-common-dir 2>/dev/null)" || common=""
  if [[ -n "$common" ]]; then
    [[ "$common" == /* || "$common" == [A-Za-z]:[/\\]* ]] ||
      common="$canonical_path/$common"
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
  path_hash="$(printf '%s' "$1" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
  printf '%s-%s' "$basename_slug" "$path_hash"
}

slug="$(derive_slug "$canonical_path")"
legacy_slug=""
[[ -n "$legacy_canonical" ]] && legacy_slug="$(derive_slug "$legacy_canonical")"

closed_mark() {
  if [[ -f "$1MISSION.md" ]] &&
    grep -qE '^Status:[[:space:]]*closed[[:space:]]*$' "$1MISSION.md" 2>/dev/null; then
    printf ' (closed)'
  fi
}

lines=()
shopt -s nullglob
for root in "${roots[@]}"; do
  for w in "${root}/${slug}"/*/*/; do
    lines+=("$w$(closed_mark "$w")")
  done
  if [[ -n "$legacy_slug" ]]; then
    for w in "${root}/${legacy_slug}"/*/*/; do
      lines+=("$w$(closed_mark "$w") (legacy worktree slug)")
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
