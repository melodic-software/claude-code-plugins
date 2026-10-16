#!/usr/bin/env bash
# actionlint pre-commit check: report what actionlint finds in the GitHub
# Actions workflow files this commit changes, on the lines it adds.
#
#   actionlint-check.sh               the staged changes (git runs it as pre-commit)
#   actionlint-check.sh --worktree    the uncommitted changes against HEAD, untracked
#                                     files included (the opt-in end-of-turn Stop row)
#
# Report only, never rewrites. Findings print as "<path>:<line>: <message>" on
# stderr and exit 1; a line the change did not add never blocks. A finding about
# a whole workflow carries the line actionlint names for it. A partly staged
# file, or a staged one since deleted from the work tree, is checked as staged,
# from the index. The embedded ShellCheck and pyflakes
# integrations stay off (-shellcheck= -pyflakes=), as in the per-edit hook this
# replaced: they spawn a process per run block. Files under .githooks/ are
# installed copies and are skipped. Missing actionlint follows the
# check-placement contract in every mode: checks.skipmissing, else fail for an
# agent and a notice for a person.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1

checks_init pre-commit "$@" || exit 0
checks_require_tool actionlint "brew install actionlint, or another method at https://github.com/rhysd/actionlint/blob/main/docs/install.md"

# staged_gone <path>: 0 at pre-commit when <path> is gone from the work tree and
# the index holds it as a regular file, not a symlink (mode 120000) or a submodule.
staged_gone() {
  [[ "$CHECKS_MODE" == pre-commit && ! -e "$1" && ! -L "$1" ]] || return 1
  [[ "$(git ls-files -s -- ":(literal)$1" 2>/dev/null)" == 100* ]]
}

whole=()
partial=()
while IFS= read -r -d '' f; do
  case "$f" in
  .githooks/*) continue ;;
  .github/workflows/*.yml | .github/workflows/*.yaml | */.github/workflows/*.yml | */.github/workflows/*.yaml) ;;
  *) continue ;;
  esac
  # A staged file gone from the work tree has unstaged changes, so it is partial.
  [[ -f "$f" && ! -L "$f" ]] || staged_gone "$f" || continue
  if checks_partly_staged "$f"; then
    partial+=("$f")
  else
    whole+=("$f")
  fi
done < <(checks_files)
((${#whole[@]} + ${#partial[@]})) || exit 0

checks_changed_lines

# actionlint -oneline prints "<path>:<line>:<col>: <message> [<rule>]"; the
# contract line drops the column and keeps the path in git's forward-slash spelling.
to_contract() {
  sed -n -e ':a' -e 's#^\([^:]*\)\\#\1/#' -e 'ta' -e 's/^\([^:]*\):\([0-9][0-9]*\):[0-9][0-9]*: \(.*\)$/\1:\2: \3/p'
}

flags=(-oneline -shellcheck= -pyflakes=)
out="$CHECKS_TMP/findings"
: >"$out"

if ((${#whole[@]})); then
  actionlint "${flags[@]}" -- "${whole[@]}" >"$CHECKS_TMP/raw" 2>&1
  rc=$?
  if ((rc > 1)); then
    printf 'actionlint: actionlint failed:\n' >&2
    cat "$CHECKS_TMP/raw" >&2
    exit 1
  fi
  to_contract <"$CHECKS_TMP/raw" >>"$out"
fi

if ((${#partial[@]})); then
  for f in "${partial[@]}"; do
    git show ":$f" 2>/dev/null | actionlint "${flags[@]}" - >"$CHECKS_TMP/raw" 2>&1
    rc=${PIPESTATUS[1]}
    if ((rc > 1)); then
      printf 'actionlint: actionlint failed on %s:\n' "$f" >&2
      cat "$CHECKS_TMP/raw" >&2
      exit 1
    fi
    escaped="$(printf '%s' "$f" | sed 's/[#&\\]/\\&/g')"
    to_contract <"$CHECKS_TMP/raw" | sed "s#^<stdin>:#$escaped:#" >>"$out"
  done
fi

checks_filter_findings <"$out" >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'actionlint: fix the findings above, or adjust .github/actionlint.yaml.\n' >&2
exit 1
