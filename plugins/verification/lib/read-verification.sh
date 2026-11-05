#!/usr/bin/env bash
# GENERATED from lib/read-verification.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Resolve the `verification` level (off | light | standard | strict) one skill
# runs at, from its plugin's team file docs/conventions/<plugin>.yaml as origin's
# default branch holds it. Meaning of each level:
# docs/conventions/verification-level/README.md.
#
#   verification_skills.<skill>   wins when set
#   verification                  the plugin's value otherwise
#   standard                      no value, an invalid value, or no readable layer
#
# The team layer is the only layer, read at origin/<default>: the working-tree
# copy never applies, so a branch cannot lower its own level. When the working
# tree's copy gives another level, a second line names both copies.
#
# SINGLE SOURCE OF TRUTH: lib/read-verification.sh at the marketplace repo root.
# Each copy sits beside its plugin's copies of config-root.sh,
# parse-concern-value.sh and yaml-subset.awk; never edit a copy. Edit the
# source and run scripts/sync-shared-copies.sh.
#
# Usage:
#   read-verification.sh --plugin <plugin> --skill <skill>
#
# Output: one line, `verification: <level> (<source>)`, for example
#   verification: light (docs/conventions/docs-hygiene.yaml verification_skills.compress at origin/main, commit <sha>)
#   verification: standard (default; team layer skipped: <reason>)
# then, when the working tree's copy differs, a second `verification:` line.
# Always exit 0: every case ends in a level, so an unattended run never stops.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config-root.sh
source "$SCRIPT_DIR/config-root.sh"

say() { printf 'verification: %s\n' "${1//[[:cntrl:]]/ }"; }
standard() {
  say "standard ($1)"
  exit 0
}

plugin="" skill=""
while (($#)); do
  case "$1" in
  --plugin | --skill)
    (($# >= 2)) || standard "default; usage: read-verification.sh --plugin <plugin> --skill <skill>"
    if [[ "$1" == --plugin ]]; then plugin="$2"; else skill="$2"; fi
    shift 2
    ;;
  *) standard "default; usage: read-verification.sh --plugin <plugin> --skill <skill>" ;;
  esac
done
name='^[a-z0-9][a-z0-9-]*$'
[[ "$plugin" =~ $name && "$skill" =~ $name ]] ||
  standard "default; --plugin and --skill take a name of lowercase letters, digits and -"

root="$(config_root_resolve)"
case "$(config_root_classify "$root")" in
home) standard "default; team layer skipped: the root is \$HOME or an ancestor of it" ;;
non-repo) standard "default; team layer skipped: the root is not inside a git working tree" ;;
*) ;;
esac
root="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" ||
  standard "default; team layer skipped: the repository top level could not be read"

symref="$(git -C "$root" ls-remote --symref origin HEAD 2>/dev/null)" ||
  standard "default; team layer skipped: no origin remote answered git ls-remote --symref origin HEAD"
branch="$(awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }' <<<"$symref")"
branch="${branch#refs/heads/}"
[[ -n "$branch" ]] || standard "default; team layer skipped: origin names no default branch"
if [[ ! "$branch" =~ ^[A-Za-z0-9._/-]+$ || "$branch" == -* || "$branch" == *..* ]]; then
  standard "default; team layer skipped: origin's default branch name '$branch' is not a safe name"
fi

stale=""
git -C "$root" fetch --quiet origin "$branch" >/dev/null 2>&1 ||
  stale="; the fetch failed, so the last fetched copy may be stale"
sha="$(git -C "$root" rev-parse --verify --quiet --end-of-options "refs/remotes/origin/$branch^{commit}")" ||
  standard "default; team layer skipped: origin/$branch has not been fetched"

file="docs/conventions/$plugin.yaml"
at="at origin/$branch, commit $sha$stale"

# resolve [ref]: sets LEVEL, KEY (empty when no key set) and ERR (empty when valid).
resolve() {
  local ref=() v rc k
  [[ -z "${1:-}" ]] || ref=(--ref "$1")
  LEVEL=standard KEY="" ERR=""
  for k in "verification_skills.$skill" verification; do
    rc=0
    v="$(cd "$root" && bash "$SCRIPT_DIR/parse-concern-value.sh" --strict ${ref[@]+"${ref[@]}"} "$file" "$k" 2>/dev/null)" || rc=$?
    case "$rc" in
    0) ;;
    3) ERR="$file does not parse or repeats a key" && return ;;
    *) ERR="$file could not be read" && return ;;
    esac
    [[ -z "$v" ]] || break
  done
  [[ -n "$v" ]] || return
  if [[ "$v" =~ ^(off|light|standard|strict)$ ]]; then
    LEVEL="$v" KEY="$k"
  else
    ERR="$file $k=$v is not off, light, standard or strict"
  fi
}

describe() {
  if [[ -n "$ERR" ]]; then
    printf 'standard (default; %s' "$ERR"
  elif [[ -n "$KEY" ]]; then
    printf '%s (%s %s' "$LEVEL" "$file" "$KEY"
  else
    printf 'standard (default; %s sets no level' "$file"
  fi
}

resolve "origin/$branch"
team_level="$LEVEL"
say "$(describe) $at)"

resolve ""
if [[ "$LEVEL" != "$team_level" ]]; then
  say "the working tree's copy gives $(describe)); the origin/$branch copy ($team_level) applied"
fi
exit 0
