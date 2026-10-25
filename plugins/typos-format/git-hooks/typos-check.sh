#!/bin/sh
# typos-format pre-commit check: report typos on the lines this commit adds.
#
#   typos-check.sh               the staged changes (git runs it as pre-commit)
#   typos-check.sh --worktree    the uncommitted changes against HEAD, untracked
#                                files included (the opt-in end-of-turn Stop row)
#
# Findings print as "<path>:<line>: <message>" on stderr and exit 1; a line the
# change did not add never blocks. The repository's own typos config governs,
# and its excludes hold for these explicit paths (--force-exclude). A partly
# staged file, or a staged one since deleted from the work tree, is checked as
# staged, from the index. Missing typos follows the
# check-placement contract: checks.skipmissing, else fail for an agent and a
# notice for a person.
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

# The plugin's bundled typos config, passed with -c so SHA-shaped hex is not read
# as a misspelling: beside an installed copy (an entry asset), or under config/
# when run from the plugin itself.
config="$here/default-typos.toml"
[[ -f "$config" ]] || config="$here/../config/default-typos.toml"
config_args=()
[[ -f "$config" ]] && config_args=(-c "$(cd "${config%/*}" && pwd)/${config##*/}")

checks_init pre-commit "$@" || exit 0
checks_require_tool typos "cargo install typos-cli, or another method at https://github.com/crate-ci/typos#install"

# A staged path gone from the work tree is checked from the index, unless the
# index holds it as a symlink (mode 120000) or a submodule.
staged_regular() {
  local entry
  entry="$(git ls-files -s -- ":(literal)$1" 2>/dev/null)"
  [[ "$entry" == 100* ]]
}

# staged_mirror <path>: a scratch tree holding the index copy of <path> at its own
# path, beside every typos config file on the way down from the top level, so
# the repository's excludes and nested configs govern it as they do the file.
staged_mirror() {
  local f="$1" root="$CHECKS_TMP/mirror" rel="." rest="$1" name
  rm -rf "$root"
  mkdir -p "$root"
  while :; do
    for name in typos.toml _typos.toml .typos.toml Cargo.toml pyproject.toml; do
      [[ -f "$rel/$name" ]] && cp "$rel/$name" "$root/$rel/$name"
    done
    [[ "$rest" == */* ]] || break
    rel="$rel/${rest%%/*}"
    rest="${rest#*/}"
    mkdir -p "$root/$rel"
  done
  git show ":$f" >"$root/$f" 2>/dev/null
}

whole=()
partial=()
while IFS= read -r -d '' f; do
  [[ ! -L "$f" ]] || continue
  if [[ ! -e "$f" ]]; then
    [[ "$CHECKS_MODE" == pre-commit ]] && staged_regular "$f" && partial+=("$f")
    continue
  fi
  [[ -f "$f" ]] || continue
  if checks_partly_staged "$f"; then
    partial+=("$f")
  else
    whole+=("$f")
  fi
done < <(checks_files)
((${#whole[@]} + ${#partial[@]})) || exit 0

checks_changed_lines

# typos --format brief prints "<path>:<line>:<col>: error: <message>"; the
# contract line drops the column and the severity.
to_contract() {
  sed -n 's/^\(.*\):\([0-9][0-9]*\):[0-9][0-9]*: [a-z]*: \(.*\)$/\1:\2: \3/p'
}

out="$CHECKS_TMP/findings"
: >"$out"
# run_typos <dir> <path>...: typos on <path>... from <dir>, findings appended to
# $out. typos exits 0 when clean and 2 on findings; any other status (a config
# it cannot read, say) is no verdict, and no verdict blocks.
run_typos() {
  local dir="$1" rc
  shift
  (cd "$dir" && typos ${config_args[@]+"${config_args[@]}"} --force-exclude --format brief --color never -- "$@") \
    >"$CHECKS_TMP/typos.out" 2>"$CHECKS_TMP/typos.err"
  rc=$?
  if ((rc != 0 && rc != 2)); then
    cat "$CHECKS_TMP/typos.err" >&2
    printf 'typos-format: typos exited %s without a verdict; fix what it reports above.\n' "$rc" >&2
    exit 1
  fi
  to_contract <"$CHECKS_TMP/typos.out" >>"$out"
}
((${#whole[@]})) && run_typos . "${whole[@]}"
for f in ${partial[@]+"${partial[@]}"}; do
  staged_regular "$f" || continue
  staged_mirror "$f"
  run_typos "$CHECKS_TMP/mirror" "$f"
done

checks_filter_findings <"$out" >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'typos-format: fix the words above, or allow-list intended ones in the repository typos config (extend-words).\n' >&2
exit 1
