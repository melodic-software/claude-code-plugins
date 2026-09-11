#!/usr/bin/env bash
# Check that every tracked file under docs/ carries a lower-kebab-case basename.
#
#   scripts/check-docs-naming.sh          discover: list every offender
#   scripts/check-docs-naming.sh --check  same, explicit form matching the
#                                         sibling gates (exit 1 on any offender)
#
# The rule: a basename matches `^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9.]+$`, so
# `plugin-philosophy.md`, `v1.2.schema.json`, and `0001-first.md` pass while
# `UPPER-KEBAB.md`, `snake_case.md`, and `Mixed.md` do not. Exempt:
#
#   - `README.md`, `CHANGELOG.md`, `INDEX.md` anywhere under docs/, the
#     conventional uppercase names tooling and forges look for by exact spelling
#     (INDEX.md is the topic-docs convention's reserved index name)
#   - everything under `docs/topics/`, the branch-only contract slice whose
#     file names (`PLAN.md`, `BRIEF.md`, ...) are owned by the topic-docs
#     convention and pruned before merge
#   - code files by extension (`py sh mjs js ps1`), whose casing is the
#     language's convention, not this one
#
# Independently of the regex, no two tracked paths under docs/ may differ only
# by case: a case-insensitive checkout (Windows, macOS) writes the second over
# the first, and two of this repository's CI jobs check out the tree on
# windows-2025.
#
# WHY. docs/ carried a mix of UPPER-KEBAB, lower-kebab, and mixed-case names
# for years, and every reference to a doc had to remember which spelling that
# one file used. One rule, enforced here, means a new file's name needs no
# lookup and a rename never happens twice. The three uppercase names stay
# because they are conventions readers already know, and code files stay
# because their language owns their casing. The ADR that records the decision
# and the .claude/rules/docs-naming.md file that loads it on read cite this
# script as the gate: a path-scoped rule loads when a covered file is read,
# never when one is created, so the rule alone cannot catch a new file.
#
# Output: one `path: reason` line per offender, sorted. Exit: 0 clean, 1 any
# offender, 2 usage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

NAME_RE='^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9.]+$'
offenders=()

# One pass for the basename rule. Exemptions are checked in the order the
# header lists them; the regex only sees what nothing exempted.
while IFS= read -r -d '' path; do
  [[ "$path" == docs/topics/* ]] && continue
  base="${path##*/}"
  [[ "$base" == README.md || "$base" == CHANGELOG.md || "$base" == INDEX.md ]] && continue
  ext="${base##*.}"
  case "$ext" in
  py | sh | mjs | js | ps1) continue ;;
  *) ;;
  esac
  if [[ ! "$base" =~ $NAME_RE ]]; then
    offenders+=("$path: basename is not lower-kebab-case (rule: $NAME_RE)")
  fi
done < <(git ls-files -z -- docs/)

# One pass for case collisions, over EVERY tracked path under docs/ (exempt
# names included: `docs/README.md` beside `docs/readme.md` still collides).
# Lower-casing each path and looking for duplicates finds every pair; each
# member of a colliding group is reported against the group's folded form.
while IFS= read -r folded; do
  [[ -n "$folded" ]] || continue
  while IFS= read -r -d '' path; do
    if [[ "${path,,}" == "$folded" ]]; then
      offenders+=("$path: differs only by case from another tracked path ($folded)")
    fi
  done < <(git ls-files -z -- docs/)
done < <(git ls-files -- docs/ | tr '[:upper:]' '[:lower:]' | sort | uniq -d)

if ((${#offenders[@]} == 0)); then
  printf 'check-docs-naming: every tracked file under docs/ is lower-kebab-case.\n'
  exit 0
fi

printf '%s\n' "${offenders[@]}" | sort -u
printf 'check-docs-naming: %d offender(s); rename to lower-kebab-case (see the header of %s).\n' \
  "${#offenders[@]}" "scripts/${0##*/}" >&2
exit 1
