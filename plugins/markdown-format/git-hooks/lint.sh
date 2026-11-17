#!/bin/sh
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

mirror="$CHECKS_TMP/mirror"
if [[ -d node_modules && ! -L node_modules && -z "$(git ls-files -- ':(literal)node_modules' 2>/dev/null)" ]] &&
  git check-ignore -q node_modules/.cache 2>/dev/null &&
  mkdir -p node_modules/.cache/markdown-format 2>/dev/null &&
  in_repo="$(mktemp -d "$PWD/node_modules/.cache/markdown-format/lint.XXXXXX" 2>/dev/null)"; then
  mirror="$in_repo" mf_status=0
  trap 'mf_status=$?; rm -rf "${in_repo:?}"; checks_finish "$mf_status" || exit 1' EXIT
fi
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
mf_link() {
  local r="${1#./}"
  [[ -e "$mirror/$r" || -L "$mirror/$r" || "$checked" == *"$US$r$US"* ]] && return 0
  case "$r" in *.md | *.mdc | *.markdown) return 0 ;; *) ;; esac
  [[ "$r" == */* ]] && mkdir -p "$mirror/${r%/*}"
  ln -s "$PWD/$r" "$mirror/$r"
}
if [[ "$checked" != "$US" ]]; then
  configs=()
  rest="${spine#"$US"}"
  while [[ -n "$rest" ]]; do
    d="${rest%%"$US"*}"
    rest="${rest#*"$US"}"
    mkdir -p "$mirror/$d"
    for name in $RT_DRIFT_CONFIGS .gitignore; do
      [[ -f "$d/$name" ]] || continue
      mf_link "$d/$name"
      [[ "$name" == .gitignore ]] || configs+=("$d/$name")
    done
  done
  if ((${#configs[@]})); then
    proot="$(pwd -P)"
    MD_MODULES=() MD_TRUST_BLOCK=""
    md_collect_modules "$proot" "${configs[@]}" || :
    for m in ${MD_MODULES[@]+"${MD_MODULES[@]}"}; do
      mf_link "${m#"$proot"/}"
    done
  fi
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
