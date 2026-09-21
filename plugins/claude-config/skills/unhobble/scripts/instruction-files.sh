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
#   instruction-files.sh list <root>                  print the files present under <root>
#   instruction-files.sh strip <root>                 git rm each present file, printing what went
#   instruction-files.sh restore <root> <ref> <name>...  git checkout <ref> -- each NAMED file
#                                                     the worktree lacks
#   instruction-files.sh restore <root> <ref> --all   the abort path: every name at once
#
# <root> is always an explicit argument. This script never falls back to the
# working directory: a strip that resolved its own target would run against
# whatever repository the operator happened to be standing in rather than the
# checkout they named.
#
# RESTORE NAMES WHAT IT RESTORES. Phase 4 re-adds only the instructions the
# stumble ledger defended, one at a time, so a restore that returned every
# stripped file would hand back the ones the ledger did not defend and quietly
# undo the experiment's whole result. `--all` exists for the other case, closing
# or abandoning an experiment, where returning the pre-strip state entire IS the
# intent; it is a separate word because those two are opposite decisions.
#
# `strip` checks every present file is tracked AND clean BEFORE it removes any of
# them, and exits 2 naming the offenders with the tree untouched. `git rm` refuses
# both an untracked file (the ordinary case for CLAUDE.local.md) and a tracked one
# whose content differs from the tip of the branch, and either refusal mid-loop
# leaves the files ahead of it gone while the ones behind it stay loaded, which is
# the half-stripped baseline this whole change exists to prevent. Back an untracked
# file up through the manifest, and commit or stash a dirty one, then strip.
#
# Exit: 0 done, 2 usage, a bad root, or an instruction file git rm would refuse.
set -euo pipefail

NAMES=(CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md AGENTS.md .claude/AGENTS.md)

usage() {
  echo "usage: instruction-files.sh list|strip <root>" >&2
  echo "       instruction-files.sh restore <root> <ref> <name>... | --all" >&2
  echo "names: ${NAMES[*]}" >&2
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
  refused=()
  present=()
  for n in "${NAMES[@]}"; do
    [[ -f "$root/$n" ]] || continue
    present+=("$n")
    if ! git -C "$root" ls-files --error-unmatch -- "$n" >/dev/null 2>&1; then
      refused+=("$n (untracked: back it up through the manifest, git cannot restore it)")
    elif ! git -C "$root" diff --quiet -- "$n" ||
      ! git -C "$root" diff --cached --quiet HEAD -- "$n"; then
      # `git rm` without -f refuses a file whose content differs from the tip of
      # the branch, in the worktree or staged, exactly as it refuses an untracked
      # one. Catching it here keeps the refusal from landing mid-loop.
      refused+=("$n (modified: commit or stash it before stripping)")
    fi
  done
  if [[ ${#refused[@]} -gt 0 ]]; then
    echo "instruction-files.sh: git rm would refuse these, so nothing was stripped:" >&2
    printf '  %s\n' "${refused[@]}" >&2
    exit 2
  fi
  for n in ${present[@]+"${present[@]}"}; do
    git -C "$root" rm -q -- "$n"
    printf '%s\n' "$n"
  done
  ;;
restore)
  ref="${3:-}"
  [[ -n "$ref" && $# -ge 4 ]] || usage
  shift 3
  if [[ "$1" == "--all" ]]; then
    [[ $# -eq 1 ]] || usage
    wanted=("${NAMES[@]}")
  else
    wanted=("$@")
    for n in "${wanted[@]}"; do
      known=""
      for k in "${NAMES[@]}"; do [[ "$n" == "$k" ]] && known=1 && break; done
      [[ -n "$known" ]] || {
        echo "instruction-files.sh: not an instruction file name: $n" >&2
        echo "names: ${NAMES[*]}" >&2
        exit 2
      }
    done
  fi
  for n in "${wanted[@]}"; do
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
