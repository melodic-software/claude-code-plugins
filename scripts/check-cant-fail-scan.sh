#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SCAN="$SELF_DIR/../plugins/testing/skills/audit/scripts/cant-fail-scan.sh"
PRUNED='(^|/)(\.git|node_modules|vendor|dist|build|out|obj|bin|target|\.work|__pycache__|\.venv|venv)/|(^|/)evals/fixtures/'

[[ -f "$SCAN" ]] || {
  printf 'ERROR: scanner not found: %s\n' "$SCAN" >&2
  exit 2
}
[[ $# -le 1 ]] || {
  printf 'Usage: %s [<base-ref>]\n' "${0##*/}" >&2
  exit 2
}

if [[ -z "${1:-}" ]]; then
  out="$(bash "$SCAN" --check 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf '%s\n' "${out##*$'\n'}"
  else
    printf '%s\n' "$out" >&2
  fi
  exit "$rc"
fi

top="$(git rev-parse --show-toplevel)" || exit 2
all="$(git -C "$top" diff --name-only "$1...HEAD")" || {
  printf 'ERROR: cannot diff against %s\n' "$1" >&2
  exit 2
}
if [[ -z "$all" ]]; then
  if [[ "$(git -C "$top" rev-list --count "$1...HEAD")" == 0 ]]; then
    printf '::notice::Not applicable: HEAD is %s, so there is no change to scan.\n' "$1"
    exit 0
  fi
  printf '::error::no file changed since %s, yet HEAD is not %s: its commits change nothing the base lacks, so the pull request is most likely superseded by work already on the base. Close it, or rebase it if it should still add something.\n' "$1" "$1" >&2
  exit 2
fi
total="$(grep -c '' <<<"$all")"
changed="$(git -C "$top" diff --name-only --diff-filter=ACMR "$1...HEAD")" || exit 2

scanned=0
worst=0
while IFS= read -r path; do
  [[ -n "$path" && ! "$path" =~ $PRUNED ]] || continue
  out="$(bash "$SCAN" --check --file "$top/$path" 2>&1)"
  rc=$?
  if [[ $rc -eq 2 ]] && grep -q '^  adapter: none (' <<<"$out"; then
    continue
  fi
  scanned=$((scanned + 1))
  if [[ $rc -eq 0 ]]; then
    printf 'clean: %s\n' "$path"
    continue
  fi
  printf '%s\n' "$out" >&2
  if [[ $rc -eq 1 && $worst -ne 2 ]]; then worst=1; else worst=2; fi
done <<<"$changed"

if [[ $scanned -eq 0 ]]; then
  printf '::notice::Not applicable: %d file(s) changed since %s, none a test file the scan covers; check-tests scans the whole tree when there is no diff base.\n' "$total" "$1"
  exit 0
fi
[[ $worst -eq 0 ]] && printf 'PASS: %d changed test file(s), no gating findings.\n' "$scanned"
exit "$worst"
