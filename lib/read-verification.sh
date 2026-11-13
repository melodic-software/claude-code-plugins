#!/usr/bin/env bash
# Resolve the `verification` level (off | light | standard | strict) one skill
# runs at, from its plugin's team file <home>/<plugin>.yaml as origin's default
# branch holds it. <home> is the convention home that resolve-convention-home.sh
# reads at the same commit; with no pointer line, or a declined one, it is
# docs/conventions. A plugin whose team file sits at a fixed path whatever the
# convention home (bugs keeps docs/conventions/bugs.yaml, say) passes that path
# with --file, and the convention home is not read. Meaning of each level:
# docs/contracts/verification-level/README.md.
#
#   verification_skills.<skill>   wins when set
#   verification                  the plugin's value otherwise
#   standard                      an invalid value, or a file that does not parse
#   light                         no value, or no readable layer
#
# An invalid value falls to standard, not light, so a team that set a level
# keeps a floor through a typo.
#
# The team layer is the only layer, read at origin/<default>: the working-tree
# copy never applies, so a branch cannot lower its own level. When the working
# tree's copy gives another level, a second line names both copies.
#
# SINGLE SOURCE OF TRUTH: lib/read-verification.sh at the marketplace repo root.
# Each copy sits beside its plugin's copies of config-root.sh,
# resolve-convention-home.sh and yaml-subset.awk; never edit a copy. Edit the
# source and run scripts/sync-shared-copies.sh.
#
# Usage:
#   read-verification.sh --plugin <plugin> --skill <skill> [--file <path>]
#
#   --file  the team file, relative to the repository root (letters, digits,
#           . _ / -, ending .yaml, no leading / or -, no ..), in place of
#           <home>/<plugin>.yaml
#
# Output: one line, `verification: <level> (<source>)`, for example
#   verification: light (docs/conventions/docs-hygiene.yaml verification_skills.compress at origin/main, commit <sha>)
#   verification: light (default; team layer skipped: <reason>)
#   verification: standard (default; docs/conventions/verification.yaml verification=Strict is not off, light, standard or strict at origin/main, commit <sha>)
# then, when the working tree's copy differs, a second `verification:` line.
# Always exit 0: every case ends in a level, so an unattended run never stops.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config-root.sh
source "$SCRIPT_DIR/config-root.sh"

say() { printf 'verification: %s\n' "${1//[[:cntrl:]]/ }"; }
fallback() {
  say "light ($1)"
  exit 0
}

usage="default; usage: read-verification.sh --plugin <plugin> --skill <skill> [--file <path>]"
plugin="" skill="" fixed=""
while (($#)); do
  case "$1" in
  --plugin | --skill | --file)
    (($# >= 2)) || fallback "$usage"
    case "$1" in
    --plugin) plugin="$2" ;;
    --skill) skill="$2" ;;
    *) fixed="$2" ;;
    esac
    shift 2
    ;;
  *) fallback "$usage" ;;
  esac
done
name='^[a-z0-9][a-z0-9-]*$'
[[ "$plugin" =~ $name && "$skill" =~ $name ]] ||
  fallback "default; --plugin and --skill take a name of lowercase letters, digits and -"
if [[ -n "$fixed" ]] && [[ ! "$fixed" =~ ^[A-Za-z0-9._/-]+\.yaml$ || "$fixed" == [/-]* || "$fixed" == *..* ]]; then
  fallback "default; --file '$fixed' is not a repository-relative .yaml path"
fi

root="$(config_root_resolve)"
case "$(config_root_classify "$root")" in
home) fallback "default; team layer skipped: the root is \$HOME or an ancestor of it" ;;
non-repo) fallback "default; team layer skipped: the root is not inside a git working tree" ;;
*) ;;
esac
root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" ||
  fallback "default; team layer skipped: the repository top level could not be read"

symref="$(git -C "$root" ls-remote --symref origin HEAD 2>/dev/null)" ||
  fallback "default; team layer skipped: no origin remote answered git ls-remote --symref origin HEAD"
branch="$(awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }' <<<"$symref")"
branch="${branch#refs/heads/}"
[[ -n "$branch" ]] || fallback "default; team layer skipped: origin names no default branch"
if [[ ! "$branch" =~ ^[A-Za-z0-9._/-]+$ || "$branch" == -* || "$branch" == *..* ]]; then
  fallback "default; team layer skipped: origin's default branch name '$branch' is not a safe name"
fi

stale=""
# An explicit destination, so a single-branch clone's narrowed refspec still
# updates refs/remotes/origin/<branch>.
git -C "$root" fetch --quiet origin "+refs/heads/$branch:refs/remotes/origin/$branch" >/dev/null 2>&1 ||
  stale="; the fetch failed, so the last fetched copy may be stale"
sha="$(git -C "$root" rev-parse --verify --quiet --end-of-options "refs/remotes/origin/$branch^{commit}")" ||
  fallback "default; team layer skipped: origin/$branch has not been fetched"

# Every read below names the commit, never a short ref a same-named tag or
# local branch could shadow.
if [[ -n "$fixed" ]]; then
  file="$fixed"
else
  rc=0
  home="$(bash "$SCRIPT_DIR/resolve-convention-home.sh" --root "$root" --ref "$sha" 2>/dev/null)" || rc=$?
  case "$rc" in
  0) ;;
  1 | 4) home=docs/conventions ;;
  *) fallback "default; team layer skipped: the convention-home pointer at origin/$branch is broken (resolve-convention-home.sh exit $rc)" ;;
  esac
  file="$home/$plugin.yaml"
fi
at="at origin/$branch, commit $sha$stale"

# resolve [sha]: sets LEVEL, KEY (empty when no key set) and ERR (empty when
# valid), from the file at <sha>, or the working tree's copy with no argument.
# The value is checked as the parser records it, before any normalization, so
# `off/` or a list is named as invalid rather than read as a level.
resolve() {
  local text records v k
  LEVEL=light KEY="" ERR=""
  if [[ -n "${1:-}" ]]; then
    text="$(git -C "$root" show --end-of-options "$1:$file" 2>/dev/null)" || return
  else
    [[ -f "$root/$file" ]] || return
    text="$(<"$root/$file")"
  fi
  records="$(LC_ALL=C awk -f "$SCRIPT_DIR/yaml-subset.awk" <<<"$text" 2>/dev/null)" || {
    LEVEL=standard ERR="$file does not parse or repeats a key"
    return
  }
  for k in "verification_skills.$skill" verification; do
    if awk -F '\t' -v k="$k." 'index($1, k) == 1 { found = 1 } END { exit !found }' <<<"$records"; then
      LEVEL=standard ERR="$file $k is a list or map, not off, light, standard or strict"
      return
    fi
    v="$(awk -F '\t' -v k="$k" '$1 == k { print substr($0, length($1) + 2); exit }' <<<"$records")"
    [[ -z "$v" ]] || break
  done
  [[ -n "$v" ]] || return
  if [[ "$v" =~ ^(off|light|standard|strict)$ ]]; then
    LEVEL="$v" KEY="$k"
  else
    LEVEL=standard ERR="$file $k=$v is not off, light, standard or strict"
  fi
}

describe() {
  if [[ -n "$ERR" ]]; then
    printf 'standard (default; %s' "$ERR"
  elif [[ -n "$KEY" ]]; then
    printf '%s (%s %s' "$LEVEL" "$file" "$KEY"
  else
    printf 'light (default; %s sets no level' "$file"
  fi
}

resolve "$sha"
team_level="$LEVEL"
say "$(describe) $at)"

resolve ""
if [[ "$LEVEL" != "$team_level" ]]; then
  say "the working tree's copy gives $(describe)); the origin/$branch copy ($team_level) applied"
fi
exit 0
