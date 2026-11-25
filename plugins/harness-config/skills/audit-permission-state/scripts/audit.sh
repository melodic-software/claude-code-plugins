#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: audit.sh [--scopes] [--entry-diff] [--lint] [--managed] [--block] [--oracle] [--critique]

  (no flags)    every read-only stage: inventory, merge, entry diff, plane lint,
                managed conformance, autoMode block lint
  --scopes      surface records only, no rule inventory and no downstream stage
  --entry-diff  inventory, merge, and the auto-mode entry diff
  --lint        inventory and the permission-plane lint
  --managed     inventory and the managed-conformance report
  --block       the autoMode block lint only (reads the CLI, not the inventory)
  --oracle      with --entry-diff, cross-check against the harness's own drop
                narration. SPAWNS A REAL `claude -p` SESSION. Never fires unless
                passed explicitly.
  --critique    with --block, add `claude auto-mode critique`. Slow, and known to
                truncate or return nothing while exiting 0.
  -h, --help    this message
EOF
}

want_scopes=0 want_entry=0 want_lint=0 want_managed=0 want_block=0
oracle=0 critique=0 narrowed=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --scopes) want_scopes=1 narrowed=1 ;;
  --entry-diff) want_entry=1 narrowed=1 ;;
  --lint) want_lint=1 narrowed=1 ;;
  --managed) want_managed=1 narrowed=1 ;;
  --block) want_block=1 narrowed=1 ;;
  --oracle) oracle=1 ;;
  --critique) critique=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown argument '$1'" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

if [[ "$narrowed" -eq 0 ]]; then
  want_entry=1 want_lint=1 want_managed=1 want_block=1
fi
[[ "$oracle" -eq 1 ]] && want_entry=1
[[ "$critique" -eq 1 ]] && want_block=1

section() {
  printf '\n===== %s =====\n' "$1"
}

run_block_lint() {
  section "autoMode block lint"
  if [[ "$critique" -eq 1 ]]; then
    bash "$HERE/automode-block-lint.sh" --critique
  else
    bash "$HERE/automode-block-lint.sh"
  fi
}

rc=0

if [[ "$want_scopes" -eq 0 && "$want_entry" -eq 0 && "$want_lint" -eq 0 && "$want_managed" -eq 0 && "$want_block" -eq 1 ]]; then
  run_block_lint || rc=$?
  exit "$rc"
fi

inv_rc=0
records="$(bash "$HERE/permission-state.sh")" || inv_rc=$?
if [[ "$inv_rc" -ne 0 ]]; then
  echo "ERROR: the inventory stage failed (exit $inv_rc); no downstream stage can run without it." >&2
  exit "$inv_rc"
fi

section "Scopes and surfaces"
printf '%s\n' "$records"

if [[ "$want_scopes" -eq 1 ]]; then
  exit 0
fi

if [[ "$want_entry" -eq 1 ]]; then
  if merged="$(printf '%s\n' "$records" | bash "$HERE/permission-merge.sh")"; then
    section "Effective set"
    printf '%s\n' "$merged" | grep -E '^(CAVEAT:|effective |inert |carveout |merge summary)' || true
  else
    rc=$?
    echo "ERROR: the merge stage failed (exit $rc)." >&2
  fi

  if [[ -n "$merged" ]]; then
    section "Auto-mode entry diff"
    entry_args=(--diff-only)
    [[ "$oracle" -eq 1 ]] && entry_args+=(--oracle)
    printf '%s\n' "$merged" | bash "$HERE/automode-entry-diff.sh" "${entry_args[@]}" |
      { grep -vE '^(NOTE:|MANAGED-NOTE:|LINT-NOTE:|CAVEAT:)' || true; } || rc=$?
  fi
fi

if [[ "$want_lint" -eq 1 ]]; then
  section "Permission-plane lint"
  printf '%s\n' "$records" | bash "$HERE/permission-plane-lint.sh" || rc=$?
fi

if [[ "$want_managed" -eq 1 ]]; then
  section "Managed conformance"
  printf '%s\n' "$records" | bash "$HERE/managed-conformance.sh" || rc=$?
fi

if [[ "$want_block" -eq 1 ]]; then
  run_block_lint || rc=$?
fi

exit "$rc"
