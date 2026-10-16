#!/usr/bin/env bash
# markdown-format pre-commit check: rewrite the staged Markdown files, then
# report what markdownlint-cli2 still finds on the lines this commit adds.
#
#   markdown-check.sh               the staged changes (git runs it as pre-commit)
#   markdown-check.sh --worktree    the uncommitted changes against HEAD, untracked
#                                   files included, reported without rewriting
#                                   (the opt-in end-of-turn Stop row)
#
# Pre-commit: a partly staged file is refused before anything is rewritten
# (re-staging a rewrite would stage its unstaged hunks too). Then
# `markdownlint-cli2 --fix` runs over the staged .md and .mdc files, the rewritten
# paths print on stdout and are re-staged, and the findings that remain print as
# "<path>:<line>: <message>" on stderr, exit 1, only for lines the commit adds.
# A staged file since deleted from the work tree is checked from the index and
# never rewritten.
#
# Only a file a markdownlint config governs is touched (see markdown-gates.sh),
# and one a config that can run repository code governs only once the user has
# approved that config state; until then it is skipped with a notice. Files under
# .githooks/ are installed copies and are skipped. markdownlint-cli2 comes from
# PATH, else the repo's own node_modules/.bin. Missing markdownlint-cli2 follows
# the check-placement contract in every mode: checks.skipmissing, else fail for
# an agent and a notice for a person.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
# shellcheck source=markdown-gates.sh
. "$here/markdown-gates.sh" || exit 1

checks_init pre-commit "$@" || exit 0

# trust_notice: say why the files under the last judged config set were skipped,
# once per config set. Approval is the user's: an agent commit gets the verdict,
# never the command that grants it.
notices=$'\n'
trust_notice() {
  local configs="" c msg
  for c in "${MD_CODE_CONFIGS[@]}"; do
    c="${c#./}"
    configs+="${configs:+, }$c"
  done
  case "$notices" in *$'\n'"$configs"$'\n'*) return 0 ;; *) ;; esac
  notices+="$configs"$'\n'
  msg="markdown-format trust gate: markdownlint-cli2 skipped for files under $configs;"
  case "$MD_TRUST" in
    gate)
      msg="$msg it can run repository code and is not approved. Approval is the user's."
      if ! checks_is_agent; then
        msg="$msg Review that config and every module it references, then run: mkdir -p '$MD_TRUST_DIR' (any change to them revokes the approval)."
      fi
      ;;
    unverifiable) msg="$msg it cannot be verified free of repository code, so lint stays off." ;;
    unpinnable) msg="$msg it names code through an expression no approval can pin, so lint stays off." ;;
    *) msg="$msg it can run repository code and there is no approval store, so lint stays off." ;;
  esac
  printf '%s\n' "$msg" >&2
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
    *.md | *.mdc) ;;
    *) continue ;;
  esac
  kind=tree
  if [[ ! -f "$f" || -L "$f" ]]; then
    staged_gone "$f" || continue
    kind=gone
  fi
  md_config_state "$f" .
  case "$MD_STATE" in
    none) continue ;;
    code)
      md_trust .
      if [[ "$MD_TRUST" != approved ]]; then
        [[ "$CHECKS_MODE" == worktree ]] || trust_notice
        continue
      fi
      ;;
    *) ;;
  esac
  if [[ "$kind" == gone ]]; then gone+=("$f"); else files+=("$f"); fi
done < <(checks_files)
((${#files[@]} + ${#gone[@]})) || exit 0

if ! command -v markdownlint-cli2 >/dev/null 2>&1; then
  first="${files[0]:-${gone[0]}}"
  first="${first%/*}"
  [[ "$first" == "${files[0]:-${gone[0]}}" ]] && first=.
  if bin="$(md_local_bin "$first" .)"; then
    PATH="$PWD/${bin%/*}:$PATH"
  fi
fi
checks_require_tool markdownlint-cli2 "npm i -D markdownlint-cli2, or another method at https://github.com/DavidAnson/markdownlint-cli2"

fix=()
if [[ "$CHECKS_MODE" == pre-commit ]]; then
  # Only the Markdown files are refused, not every staged path, which is what
  # checks_refuse_partly_staged would walk.
  refused=0
  for f in ${files[@]+"${files[@]}"}; do
    if checks_partly_staged "$f"; then
      printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
      refused=1
    fi
  done
  ((refused)) && exit 1
  fix=(--fix)
fi

# lint <dir> <path...>: one markdownlint-cli2 run from <dir> over the literal
# paths, appended to $out; keeps the highest exit code in rc.
out="$CHECKS_TMP/markdownlint"
: >"$out"
rc=0
lint() {
  local dir="$1" f one
  shift
  local literal=()
  for f in "$@"; do
    literal+=(":$f")
  done
  (cd "$dir" && markdownlint-cli2 ${fix[@]+"${fix[@]}"} "${literal[@]}") >>"$out" 2>&1
  one=$?
  ((one > rc)) && rc=$one
  return 0
}

# One run: with --fix, markdownlint-cli2 lists only what it could not fix.
((${#files[@]})) && lint . "${files[@]}"

# mirror <path>: the staged content of <path> under $CHECKS_TMP/staged at the
# same relative path, beside a link to every markdownlint config and ignore file
# on the way down from the top level, so markdownlint-cli2 run there reads the
# repository's config. A link keeps a code config's own imports resolving from
# where it really lives.
mirror() {
  local root="$CHECKS_TMP/staged" rel=. rest="$1" name
  mkdir -p "$root"
  while :; do
    for name in .markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.cjs .markdownlint-cli2.mjs \
      .markdownlint.jsonc .markdownlint.json .markdownlint.yaml .markdownlint.yml .markdownlint.cjs .markdownlint.mjs \
      .gitignore; do
      [[ -f "$rel/$name" && ! -e "$root/$rel/$name" ]] && ln -s "$PWD/$rel/$name" "$root/$rel/$name"
    done
    [[ "$rest" == */* ]] || break
    rel="$rel/${rest%%/*}"
    rest="${rest#*/}"
    mkdir -p "$root/$rel"
  done
  git show ":$1" >"$root/$1" 2>/dev/null
}
if ((${#gone[@]})); then
  for f in "${gone[@]}"; do
    mirror "$f"
  done
  fix=()
  lint "$CHECKS_TMP/staged" "${gone[@]}"
fi

if [[ "$CHECKS_MODE" == pre-commit ]] && ((${#files[@]})); then
  rewritten=()
  while IFS= read -r -d '' f; do
    rewritten+=("$f")
  done < <(git --literal-pathspecs diff --name-only -z -- "${files[@]}")
  if ((${#rewritten[@]})); then
    printf '%s\n' "${rewritten[@]}"
    git --literal-pathspecs add -- "${rewritten[@]}"
  fi
fi

if ((rc > 1)); then
  printf 'markdown-format: markdownlint-cli2 failed:\n' >&2
  cat "$out" >&2
  exit 1
fi

checks_changed_lines

# markdownlint-cli2's line is "<path>:<line>[:<col>] [<severity> ]MD<n>/<name> ...";
# the contract line drops the column and the severity and keeps the path in git's
# forward-slash spelling. A path holding a colon cannot be told from the line
# number, so its findings are not listed here.
to_contract() {
  sed -n -E -e ':a' -e 's#^([^:]*)\\#\1/#' -e 'ta' \
    -e 's/^([^:]+):([0-9]+)(:[0-9]+)? ((error|warning) )?(MD[0-9]+\/.*)$/\1:\2: \6/p'
}

to_contract <"$out" | checks_filter_findings >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'markdown-format: fix the findings above, or adjust the repository markdownlint config.\n' >&2
exit 1
