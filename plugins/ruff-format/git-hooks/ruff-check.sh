#!/usr/bin/env bash
# ruff-format pre-commit check: rewrite the staged Python files, then report
# what Ruff still finds on the lines this commit adds.
#
#   ruff-check.sh               the staged changes (git runs it as pre-commit)
#   ruff-check.sh --worktree    the uncommitted changes against HEAD, untracked
#                               files included, reported without rewriting
#                               (the opt-in end-of-turn Stop row)
#
# Pre-commit: a partly staged file is refused before anything is rewritten
# (re-staging a rewrite would stage its unstaged hunks too). Then `ruff check
# --fix` (safe fixes) and `ruff format` run over the staged .py and .pyi files,
# the rewritten paths print on stdout and are re-staged, and the findings that
# remain print as "<path>:<line>: <message>" on stderr, exit 1, only for lines
# the commit adds. A staged file since deleted from the work tree is checked
# from the index and never rewritten.
#
# Only a file a Ruff configuration governs is touched (a .ruff.toml, ruff.toml,
# or pyproject.toml with a [tool.ruff] section above it), and the config's own
# excludes hold for these explicit paths (--force-exclude). Files under
# .githooks/ are installed copies and are skipped. Ruff comes from the repo's
# .venv, else PATH. Missing ruff follows the check-placement contract in every
# mode: checks.skipmissing, else fail for an agent and a notice for a person.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1

checks_init pre-commit "$@" || exit 0

# A .venv the repository commits is its code, not the user's install, and a
# commit hook never runs it.
venv_dirs=()
[[ -z "$(git ls-files -- ':(literal).venv' 2>/dev/null)" ]] && venv_dirs=(.venv/bin .venv/Scripts)
for venv_bin in ${venv_dirs[@]+"${venv_dirs[@]}"}; do
  if [[ -x "$venv_bin/ruff" || -x "$venv_bin/ruff.exe" ]]; then
    PATH="$PWD/$venv_bin:$PATH"
    break
  fi
done
checks_require_tool ruff "pip install ruff, or another method at https://docs.astral.sh/ruff/installation/"

# governed <path>: 0 when a Ruff configuration sits in the path's directory or
# above it, up to the repository root.
governed() {
  local dir="${1%/*}" name
  [[ "$dir" == "$1" ]] && dir=.
  while :; do
    for name in .ruff.toml ruff.toml; do
      [[ -f "$dir/$name" ]] && return 0
    done
    if [[ -f "$dir/pyproject.toml" ]] && grep -qE '^[[:space:]]*\[tool\.ruff(\]|[.])' "$dir/pyproject.toml" 2>/dev/null; then
      return 0
    fi
    [[ "$dir" == . ]] && return 1
    case "$dir" in
    */*) dir="${dir%/*}" ;;
    *) dir=. ;;
    esac
  done
}

# staged_gone <path>: 0 at pre-commit when <path> is gone from the work tree and
# the index holds it as a regular file, not a symlink (mode 120000) or a submodule.
staged_gone() {
  [[ "$CHECKS_MODE" == pre-commit && ! -e "$1" && ! -L "$1" ]] || return 1
  [[ "$(git ls-files -s -- ":(literal)$1" 2>/dev/null)" == 100* ]]
}

files=()
gone=()
while IFS= read -r -d '' f; do
  case "$f" in
  .githooks/*) continue ;;
  *.py | *.pyi) ;;
  *) continue ;;
  esac
  governed "$f" || continue
  if [[ -f "$f" && ! -L "$f" ]]; then
    files+=("$f")
  elif staged_gone "$f"; then
    gone+=("$f")
  fi
done < <(checks_files)
((${#files[@]} + ${#gone[@]})) || exit 0

common=(--force-exclude --no-cache --quiet)

if [[ "$CHECKS_MODE" == pre-commit ]] && ((${#files[@]})); then
  # Only the Python files are refused, not every staged path, which is what
  # checks_refuse_partly_staged would walk.
  refused=0
  for f in "${files[@]}"; do
    if checks_partly_staged "$f"; then
      printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
      refused=1
    fi
  done
  ((refused)) && exit 1

  ruff check --fix --no-unsafe-fixes "${common[@]}" -- "${files[@]}" >/dev/null 2>&1 || :
  ruff format "${common[@]}" -- "${files[@]}" >/dev/null 2>&1 || :

  rewritten=()
  while IFS= read -r -d '' f; do
    rewritten+=("$f")
  done < <(git --literal-pathspecs diff --name-only -z -- "${files[@]}")
  if ((${#rewritten[@]})); then
    printf '%s\n' "${rewritten[@]}"
    git --literal-pathspecs add -- "${rewritten[@]}"
  fi
fi

checks_changed_lines

# Ruff's concise format is "<path>:<line>:<col>: <code> <message>"; the contract
# line drops the column and keeps the path in git's forward-slash spelling.
to_contract() {
  sed -n -e ':a' -e 's#^\([^:]*\)\\#\1/#' -e 'ta' -e 's/^\(.*\):\([0-9][0-9]*\):[0-9][0-9]*: \(.*\)$/\1:\2: \3/p'
}

out="$CHECKS_TMP/ruff"
: >"$CHECKS_TMP/contract"
if ((${#files[@]})); then
  ruff check --no-fix --output-format concise "${common[@]}" -- "${files[@]}" >"$out" 2>&1
  rc=$?
  if ((rc > 1)); then
    printf 'ruff-format: ruff failed:\n' >&2
    cat "$out" >&2
    exit 1
  fi
  to_contract <"$out" >>"$CHECKS_TMP/contract"
fi
# --stdin-filename names the path, so the config and its excludes hold for it.
for f in ${gone[@]+"${gone[@]}"}; do
  git show ":$f" 2>/dev/null |
    ruff check --no-fix --output-format concise "${common[@]}" --stdin-filename "$f" - >"$out" 2>&1
  rc=${PIPESTATUS[1]}
  if ((rc > 1)); then
    printf 'ruff-format: ruff failed on %s:\n' "$f" >&2
    cat "$out" >&2
    exit 1
  fi
  to_contract <"$out" >>"$CHECKS_TMP/contract"
done
checks_filter_findings <"$CHECKS_TMP/contract" >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'ruff-format: fix the findings above, or adjust the repository Ruff config.\n' >&2
exit 1
