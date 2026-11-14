#!/usr/bin/env bash
# GENERATED from lib/default-branch-file.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Print one file as origin's default branch holds it, read by commit SHA, never through a short ref
# (origin/HEAD) that a same-named local branch or tag could shadow, and never from the working tree.
# For settings a branch must not change, such as a command a skill runs.
#
# SINGLE SOURCE OF TRUTH: lib/default-branch-file.sh at the marketplace repo root. Each copy sits beside
# its plugin's copies of config-root.sh and resolve-convention-home.sh; never edit a copy. Edit the source
# and run scripts/sync-shared-copies.sh.
#
# Usage:
#   default-branch-file.sh --plugin <plugin>   the team file <home>/<plugin>.yaml, <home> being the
#                                              convention home at that commit (docs/conventions by default)
#   default-branch-file.sh --path <path>       any repository-relative file (letters, digits, . _ / -,
#                                              no leading / or -, no ..)
#
# Exit 0: the file's content on stdout, then `default-branch-file: <path> at origin/<branch>, commit <sha>`
#         on stderr.
# Exit 1: the default branch has no such file.
# Exit 2: the default branch could not be read; the reason is on stderr. The caller uses its defaults,
#         never the working tree's copy.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config-root.sh
source "$SCRIPT_DIR/config-root.sh"

stop() {
  printf 'default-branch-file: %s\n' "${2//[[:cntrl:]]/ }" >&2
  exit "$1"
}

plugin="" file=""
case "${1:-}:${2:-}:${3:-}" in
--plugin:?*:) plugin="$2" ;;
--path:?*:) file="$2" ;;
*) stop 2 "usage: default-branch-file.sh --plugin <plugin> | --path <path>" ;;
esac
if [[ -n "$plugin" && ! "$plugin" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  stop 2 "--plugin takes a name of lowercase letters, digits and -"
fi
if [[ -n "$file" ]] && [[ ! "$file" =~ ^[A-Za-z0-9._/-]+$ || "$file" == [/-]* || "$file" == *..* ]]; then
  stop 2 "--path '$file' is not a repository-relative path"
fi

root="$(config_root_resolve)"
case "$(config_root_classify "$root")" in
home) stop 2 "the root is \$HOME or an ancestor of it" ;;
non-repo) stop 2 "the root is not inside a git working tree" ;;
*) ;;
esac
root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || stop 2 "the repository top level could not be read"

symref="$(git -C "$root" ls-remote --symref origin HEAD 2>/dev/null)" ||
  stop 2 "no origin remote answered git ls-remote --symref origin HEAD"
branch="$(awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }' <<<"$symref")"
branch="${branch#refs/heads/}"
[[ -n "$branch" ]] || stop 2 "origin names no default branch"
if [[ ! "$branch" =~ ^[A-Za-z0-9._/-]+$ || "$branch" == -* || "$branch" == *..* ]]; then
  stop 2 "origin's default branch name '$branch' is not a safe name"
fi
# An explicit destination, so a single-branch clone's narrowed refspec still updates the ref.
git -C "$root" fetch --quiet origin "+refs/heads/$branch:refs/remotes/origin/$branch" >/dev/null 2>&1 ||
  stop 2 "the fetch of origin/$branch failed"
sha="$(git -C "$root" rev-parse --verify --quiet --end-of-options "refs/remotes/origin/$branch^{commit}")" ||
  stop 2 "origin/$branch has not been fetched"

if [[ -n "$plugin" ]]; then
  rc=0
  home="$(bash "$SCRIPT_DIR/resolve-convention-home.sh" --root "$root" --ref "$sha" 2>/dev/null)" || rc=$?
  case "$rc" in
  0) ;;
  1 | 4) home=docs/conventions ;;
  *) stop 2 "the convention-home pointer at origin/$branch is broken (resolve-convention-home.sh exit $rc)" ;;
  esac
  file="$home/$plugin.yaml"
fi
git -C "$root" cat-file -e "$sha:$file" 2>/dev/null || stop 1 "$file is not on origin/$branch, commit $sha"
git -C "$root" show --end-of-options "$sha:$file" || stop 2 "$file could not be read at commit $sha"
printf 'default-branch-file: %s at origin/%s, commit %s\n' "$file" "$branch" "$sha" >&2
