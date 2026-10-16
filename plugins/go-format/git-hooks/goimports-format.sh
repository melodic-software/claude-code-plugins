#!/usr/bin/env bash
# go-format pre-commit entry: rewrite the staged Go files with goimports.
#
#   goimports-format.sh               the staged changes (git runs it as pre-commit)
#   goimports-format.sh --worktree    the uncommitted changes against HEAD, untracked
#                                     files included, parsed without rewriting
#                                     (the opt-in end-of-turn Stop row)
#
# goimports reports no lint findings, so this entry rewrites and fails only when
# goimports itself errors, which it does for a file it cannot parse. Pre-commit:
# a partly staged file is refused before anything is rewritten (re-staging a
# rewrite would stage its unstaged hunks too). Then `goimports -w` runs over the
# staged .go files, the rewritten paths print on stdout and are re-staged, and
# each parse error prints as "<path>:<line>: <message>" on stderr, exit 1.
# A file that does not parse is a failure wherever the error sits, so the errors
# are not narrowed to the lines the commit adds.
#
# A file whose leading comment block carries Go's `// Code generated ... DO NOT
# EDIT.` marker is left alone, as is anything under .githooks/ (installed
# copies). goimports comes from PATH. Missing goimports follows the
# check-placement contract: checks.skipmissing, else fail for an agent and a
# notice for a person; the --worktree mode stays silent, since the session-start
# probe already reports it.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1

checks_init pre-commit "$@" || exit 0

if [[ "$CHECKS_MODE" == worktree ]]; then
  command -v goimports >/dev/null 2>&1 || exit 0
fi
checks_require_tool goimports "go install golang.org/x/tools/cmd/goimports@latest (needs a Go toolchain: https://go.dev/dl/)"

# generated <path>: 0 when the file's leading comment and blank-line run holds
# the generated-code marker. The scan is a stand-in for go/ast.IsGenerated: it
# tracks /* */ blocks, tolerates a BOM and CRLF, and stops at the first line
# that is neither blank nor a comment.
generated() {
  local line trimmed in_block=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#$'\xEF\xBB\xBF'}"
    if ((in_block)); then
      [[ "$line" == *'*/'* ]] && in_block=0
      continue
    fi
    [[ -n "${line//[[:space:]]/}" ]] || continue
    trimmed="${line#"${line%%[![:space:]]*}"}"
    if [[ "$trimmed" == //* ]]; then
      [[ "$line" =~ ^//\ Code\ generated\ .*\ DO\ NOT\ EDIT\.$ ]] && return 0
      continue
    fi
    if [[ "$trimmed" == /\** ]]; then
      [[ "$trimmed" == *'*/'* ]] || in_block=1
      continue
    fi
    break
  done <"$1"
  return 1
}

files=()
while IFS= read -r -d '' f; do
  case "$f" in
    .githooks/*) continue ;;
    *.go) ;;
    *) continue ;;
  esac
  [[ -f "$f" && ! -L "$f" ]] || continue
  generated "$f" && continue
  files+=("$f")
done < <(checks_files)
((${#files[@]})) || exit 0

if [[ "$CHECKS_MODE" == pre-commit ]]; then
  # Only the Go files are refused, not every staged path, which is what
  # checks_refuse_partly_staged would walk.
  refused=0
  for f in "${files[@]}"; do
    if checks_partly_staged "$f"; then
      printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
      refused=1
    fi
  done
  ((refused)) && exit 1
fi

# local_prefix <dir>: the module path of the module holding <dir>, for goimports'
# -local grouping; empty when go is absent or the directory is outside a module.
local_prefix() {
  local mod=""
  if command -v go >/dev/null 2>&1; then
    mod="$(cd "$1" 2>/dev/null && go list -m 2>/dev/null)" || mod=""
    [[ "$mod" == "command-line-arguments" ]] && mod=""
  fi
  printf '%s' "$mod"
}

errs="$CHECKS_TMP/goimports"
: >"$errs"
if [[ "$CHECKS_MODE" == pre-commit ]]; then
  flags=(-w)
else
  flags=(-l)
fi

# run_group <prefix> <files...>: one goimports run over files sharing a -local prefix.
run_group() {
  local prefix="$1" args=("${flags[@]}")
  shift
  [[ -n "$prefix" ]] && args+=(-local "$prefix")
  goimports "${args[@]}" -- "$@" >/dev/null 2>>"$errs" || :
}

# Files arrive sorted, so the files of one module sit together and one run
# covers them.
group=()
group_prefix=""
for f in "${files[@]}"; do
  dir="${f%/*}"
  [[ "$dir" == "$f" ]] && dir=.
  prefix="$(local_prefix "$dir")"
  if ((${#group[@]})) && [[ "$prefix" != "$group_prefix" ]]; then
    run_group "$group_prefix" "${group[@]}"
    group=()
  fi
  group_prefix="$prefix"
  group+=("$f")
done
((${#group[@]})) && run_group "$group_prefix" "${group[@]}"

if [[ "$CHECKS_MODE" == pre-commit ]]; then
  rewritten=()
  while IFS= read -r -d '' f; do
    rewritten+=("$f")
  done < <(git diff --name-only -z -- "${files[@]}")
  if ((${#rewritten[@]})); then
    printf '%s\n' "${rewritten[@]}"
    git add -- "${rewritten[@]}"
  fi
fi

[[ -s "$errs" ]] || exit 0

# goimports prints "<path>:<line>:<col>: <message>"; the contract line drops the
# column. Anything else it prints passes through.
sed -e 's/^\(.*\.go\):\([0-9][0-9]*\):[0-9][0-9]*: /\1:\2: /' "$errs" >&2
printf 'go-format: goimports could not process the files above.\n' >&2
exit 1
