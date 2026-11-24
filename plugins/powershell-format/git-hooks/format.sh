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
  rt_print format "$PWD" ${resolve[@]+"${resolve[@]}"}
  exit 0
fi
[[ "$CHECKS_MODE" == pre-commit ]] || exit 0

candidates=()
while IFS= read -r -d '' f; do
  rt_wants "$f" && candidates+=("$f")
done < <(checks_files)
((${#candidates[@]})) || exit 0

rt_group format "$PWD" "${candidates[@]}"
checks_refuse_config_drift "$PSF_SETTINGS" -- "${candidates[@]}" || exit 1
((RT_GN)) || exit 0

runs=()
failed=0
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  rt_require
  case $? in
  0) runs[i]=1 ;;
  2) runs[i]=0 failed=1 ;;
  *) runs[i]=0 ;;
  esac
done

refused=0
for ((i = 0; i < RT_GN; i++)); do
  ((runs[i])) || continue
  rt_use "$i"
  for f in "${RT_FILES[@]}"; do
    if [[ -f "$f" && ! -L "$f" ]] && checks_partly_staged "$f"; then
      printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
      refused=1
    fi
  done
done
((refused)) && exit 1

psf_init "$PWD"
[[ -z "$PSF_LINT_CACHE" ]] || rm -rf -- "${PSF_LINT_CACHE:?}"
lint_out=""
psf_lint_off || lint_out="$CHECKS_TMP/lint-out"
out="$CHECKS_TMP/pwsh-out"
written=()
for ((i = 0; i < RT_GN; i++)); do
  ((runs[i])) || continue
  rt_use "$i"
  present=()
  for f in "${RT_FILES[@]}"; do
    [[ -f "$f" && ! -L "$f" ]] && present+=("$f")
  done
  ((${#present[@]})) || continue
  if [[ -n "$lint_out" ]]; then
    : >"$lint_out"
    rm -f "$lint_out.rc"
  fi
  PSF_LINT_OUT="$lint_out" psf_run "$RT_DIR" "${present[@]}" >"$out" 2>&1
  rc=$?
  PSF_LINT_OUT="$lint_out" psf_lint_store "$rc" "$out" "$RT_DIR" "${present[@]}"
  case $rc in
  0) written+=("${present[@]}") ;;
  3)
    psf_module_missing
    (($? == 2)) && failed=1
    break
    ;;
  6) psf_trust_notice "$out" formatting ;;
  *)
    psf_broken "$out" Invoke-Formatter
    failed=1
    written+=("${present[@]}")
    ;;
  esac
done
((${#written[@]})) && { checks_restage "${written[@]}" || failed=1; }
exit "$failed"
