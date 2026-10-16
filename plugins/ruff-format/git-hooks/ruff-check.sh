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
# the commit adds.
#
# Only a file a Ruff configuration governs is touched (a .ruff.toml, ruff.toml,
# or pyproject.toml with a [tool.ruff] section above it), and the config's own
# excludes hold for these explicit paths (--force-exclude). Files under
# .githooks/ are installed copies and are skipped. Ruff comes from the repo's
# .venv, else PATH. Missing ruff follows the check-placement contract:
# checks.skipmissing, else fail for an agent and a notice for a person; the
# --worktree mode stays silent, since the session-start probe already reports it.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1

checks_init pre-commit "$@" || exit 0

for venv_bin in .venv/bin .venv/Scripts; do
  if [[ -x "$venv_bin/ruff" || -x "$venv_bin/ruff.exe" ]]; then
    PATH="$PWD/$venv_bin:$PATH"
    break
  fi
done
if [[ "$CHECKS_MODE" == worktree ]]; then
  command -v ruff >/dev/null 2>&1 || exit 0
fi
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

files=()
while IFS= read -r -d '' f; do
  case "$f" in
  .githooks/*) continue ;;
  *.py | *.pyi) ;;
  *) continue ;;
  esac
  [[ -f "$f" && ! -L "$f" ]] || continue
  governed "$f" || continue
  files+=("$f")
done < <(checks_files)
((${#files[@]})) || exit 0

common=(--force-exclude --no-cache --quiet)

if [[ "$CHECKS_MODE" == pre-commit ]]; then
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
  done < <(git diff --name-only -z -- "${files[@]}")
  if ((${#rewritten[@]})); then
    printf '%s\n' "${rewritten[@]}"
    git add -- "${rewritten[@]}"
  fi
fi

checks_changed_lines

# Ruff's concise format is "<path>:<line>:<col>: <code> <message>"; the contract
# line drops the column and keeps the path in git's forward-slash spelling.
to_contract() {
  sed -n -e ':a' -e 's#^\([^:]*\)\\#\1/#' -e 'ta' -e 's/^\(.*\):\([0-9][0-9]*\):[0-9][0-9]*: \(.*\)$/\1:\2: \3/p'
}

out="$CHECKS_TMP/ruff"
ruff check --no-fix --output-format concise "${common[@]}" -- "${files[@]}" >"$out" 2>&1
rc=$?
if ((rc > 1)); then
  printf 'ruff-format: ruff failed:\n' >&2
  cat "$out" >&2
  exit 1
fi
to_contract <"$out" | checks_filter_findings >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'ruff-format: fix the findings above, or adjust the repository Ruff config.\n' >&2
exit 1
