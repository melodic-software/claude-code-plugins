#!/bin/sh
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
# from the index. actionlint reads .github/actionlint.yaml from the work tree,
# so a commit is refused while that file differs between the index and the work
# tree. The embedded ShellCheck and pyflakes
# integrations stay off (-shellcheck= -pyflakes=), as in the per-edit hook this
# replaced: they spawn a process per run block. Files under .githooks/ are
# installed copies and are skipped. Missing actionlint follows the
# check-placement contract in every mode: checks.skipmissing, else fail for an
# agent and a notice for a person.
#
# POSIX sh until check-lib.sh, sourced first, has it running under bash.
# shellcheck shell=bash
case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
lib="$here/check-lib.sh"
# shellcheck disable=SC2292 # still POSIX sh: no [[ ]]
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail

checks_init pre-commit "$@" || exit 0
checks_require_tool actionlint "the kjanat/actionlint v1.17.0 release asset, checked against its checksums file: https://github.com/kjanat/actionlint/releases/tag/v1.17.0"

whole=()
partial=()
while IFS= read -r -d '' f; do
  case "$f" in
  .githooks/*) continue ;;
  .github/workflows/*.yml | .github/workflows/*.yaml | */.github/workflows/*.yml | */.github/workflows/*.yaml) ;;
  *) continue ;;
  esac
  # A staged file gone from the work tree has unstaged changes, so it is partial.
  [[ -f "$f" && ! -L "$f" ]] || checks_staged_gone "$f" || continue
  if checks_partly_staged "$f"; then
    partial+=("$f")
  else
    whole+=("$f")
  fi
done < <(checks_files)
((${#whole[@]} + ${#partial[@]})) || exit 0
checks_refuse_config_drift actionlint.yaml actionlint.yml -- ${whole[@]+"${whole[@]}"} ${partial[@]+"${partial[@]}"} || exit 1

checks_changed_lines

# actionlint -oneline prints "<path>:<line>:<col>: <message> [<rule>]"; the
# contract line drops the column and keeps the path in git's forward-slash spelling.
to_contract() {
  sed -n -e ':a' -e 's#^\([^:]*\)\\#\1/#' -e 'ta' -e 's/^\([^:]*\):\([0-9][0-9]*\):[0-9][0-9]*: \(.*\)$/\1:\2: \3/p'
}

flags=(-oneline -shellcheck= -pyflakes=)
out="$CHECKS_TMP/findings"
: >"$out"

# exit_if_lint_failed <status> [<what>]: actionlint exits 1 on findings and
# above 1 when it could not lint; then its output goes to stderr and the
# script exits 1.
exit_if_lint_failed() {
  (($1 > 1)) || return 0
  printf 'actionlint: actionlint failed%s:\n' "${2:-}" >&2
  cat "$CHECKS_TMP/raw" >&2
  exit 1
}

if ((${#whole[@]})); then
  actionlint "${flags[@]}" -- "${whole[@]}" >"$CHECKS_TMP/raw" 2>&1
  exit_if_lint_failed $?
  to_contract <"$CHECKS_TMP/raw" >>"$out"
fi

for f in ${partial[@]+"${partial[@]}"}; do
  git show ":$f" 2>/dev/null | actionlint "${flags[@]}" - >"$CHECKS_TMP/raw" 2>&1
  exit_if_lint_failed "${PIPESTATUS[1]}" " on $f"
  escaped="$(printf '%s' "$f" | sed 's/[#&\\]/\\&/g')"
  to_contract <"$CHECKS_TMP/raw" | sed "s#^<stdin>:#$escaped:#" >>"$out"
done

checks_filter_findings <"$out" >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'actionlint: fix the findings above, or adjust .github/actionlint.yaml.\n' >&2
exit 1
