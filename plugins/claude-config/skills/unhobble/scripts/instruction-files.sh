#!/usr/bin/env bash
# instruction-files.sh: the project-root instruction files the unhobble strip
# moves aside, and the git commands that move them and put them back.
#
# AGENTS.md and .claude/AGENTS.md are on the list unconditionally. Claude Code
# reads them as the project instructions only when no CLAUDE.md name displaces
# them, and the strip removes exactly those CLAUDE.md names, so a file that is
# merely imported by a one-line shim today is read natively the moment the shim
# goes. A baseline that left it in place would declare itself bare while the
# repository's whole instruction surface was still loading. The displacement
# rule and its dated record live in
# plugins/instruction-placement/skills/migrate/reference/sources.md.
#
#   instruction-files.sh list <root>           print the files present under <root>
#   instruction-files.sh strip <root>          git rm each present file, printing what went
#   instruction-files.sh restore <root> <ref>  git checkout <ref> -- each listed file that
#                                              <ref> has and the worktree lacks
#
# <root> is always an explicit argument. This script never falls back to the
# working directory: a strip that resolved its own target would run against
# whatever repository the operator happened to be standing in rather than the
# checkout they named.
#
# `strip` checks every present file is tracked BEFORE it removes any of them, and
# exits 2 naming the untracked ones with the tree untouched. An untracked
# instruction file is the ordinary case for CLAUDE.local.md, and `git rm` on one
# fails mid-loop: the files ahead of it are already gone while the ones behind it
# stay loaded, which is the half-stripped baseline this whole change exists to
# prevent. Back those files up through the manifest first, then strip.
#
# Exit: 0 done, 2 usage, a bad root, or an untracked instruction file.
set -euo pipefail

NAMES=(CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md AGENTS.md .claude/AGENTS.md)

usage() {
  echo "usage: instruction-files.sh list|strip <root>" >&2
  echo "       instruction-files.sh restore <root> <ref>" >&2
  exit 2
}

cmd="${1:-}"
root="${2:-}"
[[ -n "$cmd" && -n "$root" ]] || usage
[[ -d "$root" ]] || {
  echo "instruction-files.sh: not a directory: $root" >&2
  exit 2
}

case "$cmd" in
list)
  for n in "${NAMES[@]}"; do
    if [[ -f "$root/$n" ]]; then printf '%s\n' "$n"; fi
  done
  ;;
strip)
  untracked=()
  present=()
  for n in "${NAMES[@]}"; do
    if [[ -f "$root/$n" ]]; then
      present+=("$n")
      git -C "$root" ls-files --error-unmatch -- "$n" >/dev/null 2>&1 || untracked+=("$n")
    fi
  done
  if [[ ${#untracked[@]} -gt 0 ]]; then
    echo "instruction-files.sh: untracked instruction file(s), nothing stripped:" >&2
    printf '  %s\n' "${untracked[@]}" >&2
    echo "Back them up through the manifest before stripping; git cannot restore them." >&2
    exit 2
  fi
  for n in ${present[@]+"${present[@]}"}; do
    git -C "$root" rm -q -- "$n"
    printf '%s\n' "$n"
  done
  ;;
restore)
  ref="${3:-}"
  [[ -n "$ref" ]] || usage
  for n in "${NAMES[@]}"; do
    if [[ -f "$root/$n" ]]; then continue; fi
    if git -C "$root" cat-file -e "$ref:$n" 2>/dev/null; then
      git -C "$root" checkout "$ref" -- "$n"
      printf '%s\n' "$n"
    fi
  done
  ;;
*)
  usage
  ;;
esac
