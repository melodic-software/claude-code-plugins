#!/usr/bin/env bash
# Check that every tracked file under docs/ carries a lower-kebab-case basename.
#
#   scripts/check-docs-naming.sh          discover: list every offender
#   scripts/check-docs-naming.sh --check  same, explicit form matching the
#                                         sibling gates (exit 1 on any offender)
#
# The rule: a basename matches `^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$`, so
# `plugin-philosophy.md`, `v1.2.schema.json`, and `0001-first.md` pass while
# `UPPER-KEBAB.md`, `snake_case.md`, `Mixed.md`, `foo..md`, and `foo.md.` do
# not (every dot- or hyphen-separated segment is non-empty, and the name ends
# in a non-empty extension). Exempt:
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
# WHY. With a mix of UPPER-KEBAB, lower-kebab, and mixed-case names, every
# reference to a doc has to remember which spelling that one file uses. One rule, enforced here, means a new file's name needs no
# lookup and a rename never happens twice. The three uppercase names stay
# because they are conventions readers already know, and code files stay
# because their language owns their casing. The ADR that records the decision
# cites this script as the gate: a path-scoped rule, where one exists, loads
# when a covered file is read, never when one is created, so a rule alone
# cannot catch a new file.
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one `path: reason` finding per offender on stderr, the clean-run
# statement on stdout. Exit: 0 clean, 1 any offender, 2 environment or usage
# (git missing, repo root unresolved, bad argument).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

if ! command -v git >/dev/null 2>&1; then
  printf 'check-docs-naming: git is required to list the tracked files under docs/\n' >&2
  exit 2
fi
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  printf 'check-docs-naming: not inside a git repository, nothing inspected\n' >&2
  exit 2
fi

NAME_RE='^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$'
offenders=()

# Tracked paths under docs/, read once. NUL-delimited, so a path git would
# otherwise C-quote (a non-ASCII byte, a tab, or a newline) arrives as the raw
# bytes. The basename pass and the case-collision pass both walk this array.
paths=()
while IFS= read -r -d '' path; do
  paths+=("$path")
done < <(git ls-files -z -- docs/)

# One pass for the basename rule. Exemptions are checked in the order the
# header lists them; the regex only sees what nothing exempted.
for path in ${paths+"${paths[@]}"}; do
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
done

# One pass for case collisions, over EVERY tracked path under docs/ (exempt
# names included: `docs/README.md` beside `docs/readme.md` still collides).
# Lower-casing each path and looking for duplicates finds every pair; each
# member of a colliding group is reported against the group's folded form.
# The fold goes through `tr`, never `${path,,}`: that expansion is Bash 4+,
# and the checkouts this rule protects include stock macOS Bash 3.2.
#
# The duplicate folds come from this same array. A second `git ls-files`
# without `-z` would C-quote the bytes above, and that quoted text would never
# equal the raw path, so the collision would be missed. `sort` and `uniq -d`
# see one `printf %q` record per folded path: a single line, so an embedded
# newline stays inside its record, and the bytes compared are the folded path.
# `sort -z` is not used: BSD sort, which macOS ships, has no `-z`.
folded=()
for path in ${paths+"${paths[@]}"}; do
  # The trailing x keeps a path that ends in a newline intact. A command
  # substitution strips trailing newlines, so x sits after them and is
  # removed once the folded bytes are captured.
  one="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]' && printf x)"
  folded+=("${one%x}")
done

dups=""
if ((${#folded[@]} > 0)); then
  dups="$(
    for one in ${folded+"${folded[@]}"}; do
      printf '%q\n' "$one"
    done | sort | uniq -d
  )"
fi

if [[ -n "$dups" ]]; then
  i=0
  while ((i < ${#paths[@]})); do
    one="${folded[$i]}"
    if [[ -n "$one" ]]; then
      printf -v key '%q' "$one"
      if [[ $'\n'"$dups"$'\n' == *$'\n'"$key"$'\n'* ]]; then
        shown="${paths[$i]}"
        # A raw newline would split this finding into two records at the final
        # `printf | sort -u`, so such a path and its fold are shown as `%q`.
        [[ "$one" == *$'\n'* ]] && printf -v shown '%q' "$shown" && one="$key"
        offenders+=("$shown: differs only by case from another tracked path ($one)")
      fi
    fi
    i=$((i + 1))
  done
fi

if ((${#offenders[@]} == 0)); then
  printf 'check-docs-naming: every tracked file under docs/ is lower-kebab-case.\n'
  exit 0
fi

printf '%s\n' "${offenders[@]}" | sort -u >&2
printf 'check-docs-naming: %d offender(s); rename to lower-kebab-case (see the header of %s).\n' \
  "${#offenders[@]}" "scripts/${0##*/}" >&2
exit 1
