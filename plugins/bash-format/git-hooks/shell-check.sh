#!/usr/bin/env bash
# bash-format pre-commit check: format the staged shell scripts the repository
# opted in to format, then report what ShellCheck finds on the lines this commit
# adds.
#
#   shell-check.sh               the staged changes (git runs it as pre-commit)
#   shell-check.sh --worktree    the uncommitted changes against HEAD, untracked
#                                files included, reported without rewriting
#                                (the opt-in end-of-turn Stop row)
#
# Pre-commit: a partly staged shell script that shfmt would rewrite is refused
# before anything is rewritten (re-staging a rewrite would stage its unstaged
# hunks too). Then shfmt formats the staged .sh and .bash files an .editorconfig
# section governs (see git-hooks/shfmt-rewrite.sh), the rewritten paths print on
# stdout and are re-staged, and the ShellCheck findings (warning and above) print
# as "<path>:<line>: <message>" on stderr, exit 1, only for lines the commit adds.
#
# The repository's own .shellcheckrc and .editorconfig govern; the plugin ships
# none. Files under .githooks/ are installed copies and are skipped. A missing
# tool follows the check-placement contract: checks.skipmissing, else fail for an
# agent and a notice for a person; a tool that is skipped only drops its own half
# (no shfmt: no rewrite; no shellcheck: no findings). The rule holds in every
# mode.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
# shellcheck source=shfmt-rewrite.sh
. "$here/shfmt-rewrite.sh" || exit 1

checks_init pre-commit "$@" || exit 0

# need <tool> <install>: 0 when the tool is usable. When it is missing, the
# contract decides: an agent's run fails here; a skip key or a person's notice
# returns 1 so the other half of the check still runs.
need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  (checks_require_tool "$1" "$2") || exit 1
  return 1
}

files=()
while IFS= read -r -d '' f; do
  case "$f" in
  .githooks/*) continue ;;
  *.sh | *.bash) ;;
  *) continue ;;
  esac
  [[ -f "$f" && ! -L "$f" ]] || continue
  files+=("$f")
done < <(checks_files)
((${#files[@]})) || exit 0

if [[ "$CHECKS_MODE" == pre-commit ]]; then
  governed=()
  for f in "${files[@]}"; do
    shfmt_governed "$f" && governed+=("$f")
  done
  if ((${#governed[@]})); then
    # Only the governed shell files are refused, not every staged path, which is
    # what checks_refuse_partly_staged would walk.
    refused=0
    for f in "${governed[@]}"; do
      if checks_partly_staged "$f"; then
        printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
        refused=1
      fi
    done
    ((refused)) && exit 1

    can_rewrite=1
    need shfmt "see https://github.com/mvdan/sh#shfmt" || can_rewrite=0
    need jq "see https://jqlang.org/download/" || can_rewrite=0
    if ((can_rewrite)); then
      for f in "${governed[@]}"; do
        shfmt_rewrite "$f"
      done
      [[ -z "$SHFMT_NOTE" ]] || printf '%s\n' "$SHFMT_NOTE" >&2
      rewritten=()
      while IFS= read -r -d '' f; do
        rewritten+=("$f")
      done < <(git diff --name-only -z -- "${governed[@]}")
      if ((${#rewritten[@]})); then
        printf '%s\n' "${rewritten[@]}"
        git add -- "${rewritten[@]}"
      fi
    fi
  fi
fi

need shellcheck "see https://github.com/koalaman/shellcheck#installing" || exit 0

checks_changed_lines

# ShellCheck's gcc format is "<path>:<line>:<col>: <level>: <message>"; the
# contract line drops the column.
to_contract() {
  sed -n -e 's/^\(.*\):\([0-9][0-9]*\):[0-9][0-9]*: \(.*\)$/\1:\2: \3/p'
}

out="$CHECKS_TMP/shellcheck"
shellcheck -x -f gcc -S warning -- "${files[@]}" >"$out" 2>&1
rc=$?
to_contract <"$out" | checks_filter_findings >"$CHECKS_TMP/blocking"
if [[ -s "$CHECKS_TMP/blocking" ]]; then
  cat "$CHECKS_TMP/blocking" >&2
  printf 'bash-format: fix the findings above, or adjust the repository .shellcheckrc.\n' >&2
  exit 1
fi
if ((rc > 1)); then
  printf 'bash-format: shellcheck failed:\n' >&2
  cat "$out" >&2
  exit 1
fi
exit 0
