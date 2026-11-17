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

US=$'\x1f'
RS=$'\x1e'
mf_yes="$US" mf_no="$US"
mf_nm_ok() {
  local nm=node_modules
  [[ "$1" == . ]] || nm="$1/node_modules"
  [[ "$mf_yes" == *"$US$1$US"* ]] && return 0
  [[ "$mf_no" == *"$US$1$US"* ]] && return 1
  if [[ -d "$nm" && ! -L "$nm" && -z "$(git ls-files -- ":(literal)$nm" 2>/dev/null)" ]] &&
    git check-ignore -q "$nm/.cache" 2>/dev/null; then
    mf_yes+="$1$US"
    return 0
  fi
  mf_no+="$1$US"
  return 1
}
mf_base() {
  local d
  md_config_state "$1" .
  d="${MD_NEAREST%/*}"
  [[ "$d" == "$MD_NEAREST" ]] && d=.
  d="${d#./}"
  while :; do
    MF_BASE="$d"
    mf_nm_ok "$d" && return 0
    [[ "$d" == . ]] && break
    if [[ "$d" == */* ]]; then d="${d%/*}"; else d=.; fi
  done
  MF_BASE=""
}
proot="$(pwd -P)"
mf_bases=() spines=() checks=() mirrors=() made=() mf_status=0
trap 'mf_status=$?; for m in ${made[@]+"${made[@]}"}; do rm -rf -- "${m:?}"; done; checks_finish "$mf_status" || exit 1' EXIT
gcopies=()
for ((i = 0; i < RT_GN; i++)); do
  gcopies[i]=""
  ((runs[i])) || continue
  rt_use "$i"
  for f in "${RT_FILES[@]}"; do
    [[ -L "$f" ]] && continue
    [[ -f "$f" ]] || checks_staged_gone "$f" || continue
    mf_base "$f"
    for ((k = 0; k < ${#mf_bases[@]}; k++)); do
      [[ "${mf_bases[k]}" == "$MF_BASE" ]] && break
    done
    if ((k == ${#mf_bases[@]})); then
      mf_bases[k]="$MF_BASE" spines[k]="$US.$US" checks[k]="$US"
      mirrors[k]="$CHECKS_TMP/mirror$k"
      if [[ -n "$MF_BASE" ]] && cache="$MF_BASE/node_modules/.cache/markdown-format" && cache="${cache#./}" &&
        mkdir -p "$cache" 2>/dev/null && m="$(mktemp -d "$PWD/$cache/lint.XXXXXX" 2>/dev/null)"; then
        made+=("$m")
        mirrors[k]="$m"
      fi
    fi
    checks[k]+="$f$US"
    gcopies[i]+="$k$RS$f$US"
    d="$f"
    while [[ "$d" == */* ]]; do
      d="${d%/*}"
      [[ "${spines[k]}" == *"$US$d$US"* ]] || spines[k]+="$d$US"
    done
  done
done
mf_link() {
  local r="${1#./}"
  [[ -e "$mirror/$r" || -L "$mirror/$r" || "$checked" == *"$US$r$US"* ]] && return 0
  case "$r" in *.md | *.mdc | *.markdown) return 0 ;; *) ;; esac
  case "/$r" in */node_modules/*) return 0 ;; *) ;; esac
  [[ "$r" == */* ]] && mkdir -p "$mirror/${r%/*}"
  ln -s "$PWD/$r" "$mirror/$r"
}
for ((k = 0; k < ${#mf_bases[@]}; k++)); do
  mirror="${mirrors[k]}" spine="${spines[k]}" checked="${checks[k]}"
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
done

out="$CHECKS_TMP/markdownlint"
: >"$out"
rc=0
for ((k = 0; k < ${#mf_bases[@]}; k++)); do
  for ((i = 0; i < RT_GN; i++)); do
    copies=()
    rest="${gcopies[i]:-}"
    while [[ -n "$rest" ]]; do
      e="${rest%%"$US"*}"
      rest="${rest#*"$US"}"
      [[ "${e%%"$RS"*}" == "$k" ]] && copies+=("${mirrors[k]}/${e#*"$RS"}")
    done
    ((${#copies[@]})) || continue
    rt_use "$i"
    RT_DIR="${mirrors[k]}"
    rt_run "${copies[@]}" >>"$out" 2>&1
    one=$?
    ((one > rc)) && rc=$one
  done
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
