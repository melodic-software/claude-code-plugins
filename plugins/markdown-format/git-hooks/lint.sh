#!/bin/sh
# markdown-format lint entry: report what the markdownlint-cli2 adapter finds on
# the lines this change adds. It never rewrites a file.
#
#   lint.sh             the staged changes (git runs it as pre-commit)
#   lint.sh --worktree  the uncommitted changes against HEAD, untracked files
#                       included (the end-of-turn Stop row)
#   lint.sh --resolve [<path>...]  print the lint row, or one per path
#                       (resolve-tool.sh rt_print); runs nothing
#
# The command resolves per file through lib/git-hooks/resolve-tool.sh to the
# adapter in adapters.sh where a markdownlint config governs the file, else to
# nothing; a .claude/ecosystems/ record is never run here. The linter runs over
# a copy under the check's temporary directory: the staged content at
# pre-commit, the work tree's in --worktree mode, beside links to the rest of
# the repository on the way down, so a config that turns fixing on rewrites
# only the copy and a partly staged file is checked as the commit holds it. Its findings become "<path>:<line>: <message>" lines,
# repo-relative, and only those on added lines block (stderr, exit 1). A run
# that exits non-zero with no parseable finding fails closed, and exit 2 is a
# tool failure. A config that can run repository code and is not approved is
# skipped with a notice at commit (never the approval command to an agent).
# Files under .githooks/ are installed copies and are skipped. A missing tool
# follows the check-placement contract: checks.skipmissing, else fail for an
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
rt="$here/resolve-tool.sh"
[[ -f "$rt" ]] || rt="$here/../lib/git-hooks/resolve-tool.sh"
# shellcheck source=../../../lib/git-hooks/resolve-tool.sh
. "$rt" || exit 1
# shellcheck source=markdown-gates.sh
. "$here/markdown-gates.sh" || exit 1
# shellcheck source=adapters.sh
. "$here/adapters.sh" || exit 1

resolve=()
if [[ "${1:-}" == --resolve ]]; then
  shift
  for f in "$@"; do
    [[ "$f" == /* ]] || f="$PWD/$f"
    resolve+=("$f")
  done
  set -- --resolve
fi
checks_init pre-commit "$@" || exit 0
if [[ " $CHECKS_ARGS " == *" --resolve "* ]]; then
  rt_print lint "$PWD" ${resolve[@]+"${resolve[@]}"}
  exit 0
fi

# trust_notice <configs> <verdict> <approval dir>: say why the files under a
# held config set were skipped. Approval is the user's: an agent commit gets the
# verdict, never the command that grants it.
trust_notice() {
  local msg="markdown-format trust gate: markdownlint-cli2 skipped for files under $1;"
  case "$2" in
  gate)
    msg="$msg it can run repository code and is not approved. Approval is the user's."
    if ! checks_is_agent; then
      msg="$msg Review that config and every module it references, then run: mkdir -p '$3' (any change to them revokes the approval)."
    fi
    ;;
  unverifiable) msg="$msg it cannot be verified free of repository code, so lint stays off." ;;
  unpinnable) msg="$msg it names code through an expression no approval can pin, so lint stays off." ;;
  *) msg="$msg it can run repository code and there is no approval store, so lint stays off." ;;
  esac
  printf '%s\n' "$msg" >&2
}

candidates=()
while IFS= read -r -d '' f; do
  rt_wants "$f" && candidates+=("$f")
done < <(checks_files)
((${#candidates[@]})) || exit 0

# shellcheck disable=SC2086 # the config names split on spaces
checks_refuse_config_drift $RT_DRIFT_CONFIGS -- "${candidates[@]}" || exit 1
rt_group lint "$PWD" "${candidates[@]}"
if [[ "$CHECKS_MODE" == pre-commit ]]; then
  for held in ${MF_HELD[@]+"${MF_HELD[@]}"}; do
    IFS=$'\t' read -r h_configs h_verdict h_dir <<<"$held"
    trust_notice "$h_configs" "$h_verdict" "$h_dir"
  done
fi
((RT_GN)) || exit 0

# Every group's tool first: a missing one skips its own group only, and an
# agent's missing tool fails the entry after the other groups have reported.
failed=0
runs=()
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  rt_require
  case $? in
  0) runs[i]=1 ;;
  2) runs[i]=0 failed=1 ;;
  *) runs[i]=0 ;;
  esac
done

# The mirror: every directory on the way down to a file under check is a real
# directory under $mirror, every other entry in it a link to the real one, and
# each file under check a copy of the content under check. markdownlint-cli2 run
# there reads the repository's configs and everything they reference (an
# extended config, a custom rule, node_modules) where it really lives, while a
# config that turns fixing on can rewrite only the copies. Entries are kept in
# \x1f-separated lists, so bash 3.2 needs no associative array.
mirror="$CHECKS_TMP/mirror"
US=$'\x1f'
spine="$US.$US"
checked="$US"
gcopies=()
for ((i = 0; i < RT_GN; i++)); do
  gcopies[i]=""
  ((runs[i])) || continue
  rt_use "$i"
  for f in "${RT_FILES[@]}"; do
    [[ -L "$f" ]] && continue
    [[ -f "$f" ]] || checks_staged_gone "$f" || continue
    checked+="$f$US"
    gcopies[i]+="$f$US"
    d="$f"
    while [[ "$d" == */* ]]; do
      d="${d%/*}"
      [[ "$spine" == *"$US$d$US"* ]] || spine+="$d$US"
    done
  done
done
if [[ "$checked" != "$US" ]]; then
  rest="${spine#"$US"}"
  while [[ -n "$rest" ]]; do
    d="${rest%%"$US"*}"
    rest="${rest#*"$US"}"
    mkdir -p "$mirror/$d"
    links=()
    for e in "$d"/* "$d"/.[!.]* "$d"/..?*; do
      [[ -e "$e" || -L "$e" ]] || continue
      r="${e#./}"
      [[ "${r##*/}" == .git ]] && continue
      [[ "$spine" == *"$US$r$US"* || "$checked" == *"$US$r$US"* ]] && continue
      links+=("$PWD/$r")
    done
    ((${#links[@]})) && ln -s "${links[@]}" "$mirror/$d/"
  done
  rest="${checked#"$US"}"
  while [[ -n "$rest" ]]; do
    f="${rest%%"$US"*}"
    rest="${rest#*"$US"}"
    if [[ "$CHECKS_MODE" == pre-commit ]]; then
      git show ":$f" >"$mirror/$f" 2>/dev/null
    else
      cat -- "$f" >"$mirror/$f"
    fi
  done
fi

out="$CHECKS_TMP/markdownlint"
: >"$out"
rc=0
for ((i = 0; i < RT_GN; i++)); do
  [[ -n "${gcopies[i]:-}" ]] || continue
  rt_use "$i"
  copies=()
  rest="${gcopies[i]}"
  while [[ -n "$rest" ]]; do
    copies+=("$mirror/${rest%%"$US"*}")
    rest="${rest#*"$US"}"
  done
  RT_DIR="$mirror"
  rt_run "${copies[@]}" >>"$out" 2>&1
  one=$?
  ((one > rc)) && rc=$one
done

if ((rc > 1)); then
  printf 'markdown-format: markdownlint-cli2 failed:\n' >&2
  cat "$out" >&2
  exit 1
fi

# markdownlint-cli2's line is "<path>:<line>[:<col>] [<severity> ]MD<n>/<name> ...";
# the contract line drops the column and the severity and keeps the path in git's
# forward-slash spelling, without a leading "./". A path holding a colon cannot be
# told from the line number, so it parses as no finding and fails closed below.
contract="$CHECKS_TMP/contract"
sed -n -E -e ':a' -e 's#^([^:]*)\\#\1/#' -e 'ta' -e 's#^\./##' \
  -e 's/^([^:]+):([0-9]+)(:[0-9]+)? ((error|warning) )?(MD[0-9]+\/.*)$/\1:\2: \6/p' <"$out" >"$contract"
status=$?
if ((status != 0)); then
  checks_tool_failed sed "$status" 'reading the markdownlint findings'
  exit 1
fi
if ((rc != 0)) && [[ ! -s "$contract" ]]; then
  printf 'markdown-format: markdownlint-cli2 exited %s and reported no <path>:<line> finding, so the change was not checked:\n' "$rc" >&2
  cat "$out" >&2
  exit 1
fi
if [[ -s "$contract" ]]; then
  checks_changed_lines
  checks_filter_findings <"$contract" >"$CHECKS_TMP/blocking"
  if [[ -s "$CHECKS_TMP/blocking" ]]; then
    cat "$CHECKS_TMP/blocking" >&2
    printf 'markdown-format: fix the findings markdownlint-cli2 reported above, or adjust the repository markdownlint config.\n' >&2
    failed=1
  fi
fi
exit "$failed"
