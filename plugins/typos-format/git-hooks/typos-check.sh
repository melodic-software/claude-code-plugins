#!/usr/bin/env bash
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
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1

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

# typos_excluded <path>: 0 when the repository's typos config excludes <path>.
# typos only answers for a path that exists, so a path gone from the work tree
# is asked about in a scratch mirror holding a placeholder and every typos
# config file on the way down from the top level.
typos_excluded() {
  local f="$1" root="." rel="." rest="$1" name
  if [[ ! -e "$f" ]]; then
    root="$CHECKS_TMP/mirror"
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
    : >"$root/$f"
  fi
  [[ -z "$(cd "$root" && typos ${config_args[@]+"${config_args[@]}"} --force-exclude --files -- "$f" 2>/dev/null)" ]]
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
if ((${#whole[@]})); then
  typos ${config_args[@]+"${config_args[@]}"} --force-exclude --format brief --color never -- "${whole[@]}" | to_contract >>"$out"
fi
if ((${#partial[@]})); then
  for f in "${partial[@]}"; do
    # The index blob has no path, so ask typos first whether its excludes cover it.
    staged_regular "$f" || continue
    typos_excluded "$f" && continue
    git show ":$f" 2>/dev/null | typos ${config_args[@]+"${config_args[@]}"} --format brief --color never - 2>/dev/null | to_contract |
      sed "s#^-:#$(printf '%s' "$f" | sed 's/[#&\\]/\\&/g'):#" >>"$out"
  done
fi

checks_filter_findings <"$out" >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'typos-format: fix the words above, or allow-list intended ones in the repository typos config (extend-words).\n' >&2
exit 1
