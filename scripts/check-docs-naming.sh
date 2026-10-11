#!/usr/bin/env bash
# Check that every tracked file under docs/, and every tracked markdown file
# anywhere in the repository, carries a lower-kebab-case basename.
#
#   scripts/check-docs-naming.sh          discover: list every offender
#   scripts/check-docs-naming.sh --check  same, explicit form matching the
#                                         sibling gates (exit 1 on any offender)
#
# The rule: a basename matches `^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$`, so
# `plugin-philosophy.md`, `v1.2.schema.json`, and `0001-first.md` pass while
# `UPPER-KEBAB.md`, `snake_case.md`, `Mixed.md`, `foo..md`, and `foo.md.` do
# not (every dot- or hyphen-separated segment is non-empty, and the name ends
# in a non-empty extension). Scope:
#
#   - every tracked file under docs/, whatever its extension
#   - every tracked `.md` file outside docs/, except under a `fixtures/`,
#     `evals/`, or `vendor/` directory, whose names belong to the test case,
#     eval workspace, or upstream copy they reproduce
#
# Exempt:
#
#   - the uppercase role names in EXEMPT_NAMES below, anywhere in scope: names
#     that tools, forges, or skills look up by exact spelling. ADR 0059 records
#     the evidence for each; a name joins the list only with such evidence
#   - under docs/, code files by extension (`py sh mjs js ps1`), whose casing
#     is the language's convention, not this one
#
# Independently of the regex, no two tracked paths in scope may differ only by
# case (fixture, eval, and vendor trees included): a case-insensitive checkout
# (Windows, macOS) writes the second over the first, and two of this
# repository's CI jobs check out the tree on windows-2025.
#
# WHY. With a mix of UPPER-KEBAB, lower-kebab, and mixed-case names, every
# reference to a file has to remember which spelling that one file uses. One
# rule, enforced here, means a new file's name needs no lookup and a rename
# never happens twice. The role names stay because something looks them up by
# exact spelling, and code files stay because their language owns their
# casing. ADR 0034 records the docs/ rule and ADR 0059 its extension to every
# markdown file; both cite this script as the gate: a path-scoped rule loads
# when a covered file is read, never when one is created, so a rule alone
# cannot catch a new file.
#
# It matches the gate /docs-naming:generate-file-name-gate emits from
# .claude/docs-naming.json, whose roots carry the same scope and whose
# exempt_basenames carries the same list; the co-located test compares the two.
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one `path: reason` finding per offender on stderr, the clean-run
# statement on stdout. Exit: 0 clean, 1 any offender, 2 environment or usage
# (git or python 3 missing, repo root unresolved, bad argument).
set -euo pipefail

# Parameter expansion, not dirname: with coreutils off PATH, bash 5.3 fails
# `cd ""` before the git check below can name what is missing.
SCRIPT_SRC="${BASH_SOURCE[0]}"
[[ "$SCRIPT_SRC" == */* ]] || SCRIPT_SRC="./$SCRIPT_SRC"
SCRIPT_DIR="$(cd "${SCRIPT_SRC%/*}" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

if ! command -v git >/dev/null 2>&1; then
  printf 'check-docs-naming: git is required to list the tracked files in scope\n' >&2
  exit 2
fi
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  printf 'check-docs-naming: not inside a git repository, nothing inspected\n' >&2
  exit 2
fi

# The case-collision pass folds with Python (see that pass). python3 first;
# `python` only when it is Python 3, since on Windows either name can be a
# zero-length store alias.
PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; sys.exit(sys.version_info[0] != 3)' >/dev/null 2>&1; then
    PYTHON="$candidate"
    break
  fi
done
if [[ -z "$PYTHON" ]]; then
  printf 'check-docs-naming: python 3 is required to fold paths for the case-collision check\n' >&2
  exit 2
fi
FOLD_PY='import sys
data = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
sys.stdout.buffer.write(data.lower().encode("utf-8", "surrogateescape"))'

NAME_RE='^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$'
# Space-delimited so one pattern match tests membership on stock macOS Bash 3.2,
# which has no associative arrays. Keep in step with exempt_basenames in
# .claude/docs-naming.json.
EXEMPT_NAMES=' README.md CHANGELOG.md INDEX.md LICENSE.md AGENTS.md CLAUDE.md SKILL.md CONTRIBUTING.md SECURITY.md REVIEW.md CODE_OF_CONDUCT.md CONTRACT.md STYLE.md TODO.md PLAN.md '
offenders=()

# Tracked paths in scope, read once. The `icase` pathspec magic matches the
# extension in any case, so `NOTES.MD` is in scope too. NUL-delimited, so a path git would
# otherwise C-quote (a non-ASCII byte, a tab, or a newline) arrives as the raw
# bytes. The basename pass and the case-collision pass both walk this array.
paths=()
while IFS= read -r -d '' path; do
  paths+=("$path")
done < <(git ls-files -z -- docs/ ':(icase)*.md')

# One pass for the basename rule. Exemptions are checked in the order the
# header lists them; the regex only sees what nothing exempted.
for path in ${paths+"${paths[@]}"}; do
  base="${path##*/}"
  if [[ "$path" != docs/* ]]; then
    case "/$path" in
    */fixtures/* | */evals/* | */vendor/*) continue ;;
    *) ;;
    esac
  fi
  [[ "$EXEMPT_NAMES" == *" $base "* ]] && continue
  if [[ "$path" == docs/* ]]; then
    case "${base##*.}" in
    py | sh | mjs | js | ps1) continue ;;
    *) ;;
    esac
  fi
  if [[ ! "$base" =~ $NAME_RE ]]; then
    offenders+=("$path: basename is not lower-kebab-case (rule: $NAME_RE)")
  fi
done

# One pass for case collisions, over EVERY path in scope (exempt names and
# excluded trees included: `docs/README.md` beside `docs/readme.md` still
# collides). Lower-casing each path and looking for duplicates finds every
# pair; each member of a colliding group is reported against the group's
# folded form. The fold is Python's Unicode `str.lower()` over the
# NUL-delimited list, so `Ä.md` beside `ä.md` collides as it does on NTFS and
# APFS; `tr` folds ASCII only, and `${path,,}` is Bash 4+ where stock macOS
# ships 3.2. Bytes that are not UTF-8 pass through unchanged
# (surrogateescape). The folded list stays index-aligned with `paths` because
# it is read back in the order it was written.
#
# `sort` and `uniq -d` see one `printf %q` record per folded path: a single
# line, so an embedded newline stays inside its record, and the bytes compared
# are the folded path. `sort -z` is not used: BSD sort, which macOS ships, has
# no `-z`.
folded=()
if ((${#paths[@]} > 0)); then
  while IFS= read -r -d '' one; do
    folded+=("$one")
  done < <(printf '%s\0' "${paths[@]}" | "$PYTHON" -c "$FOLD_PY")
fi

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
  printf 'check-docs-naming: every tracked file under docs/ is lower-kebab-case, and so is every tracked .md file outside it.\n'
  exit 0
fi

printf '%s\n' "${offenders[@]}" | sort -u >&2
printf 'check-docs-naming: %d offender(s); rename to lower-kebab-case (see the header of %s).\n' \
  "${#offenders[@]}" "scripts/${0##*/}" >&2
exit 1
