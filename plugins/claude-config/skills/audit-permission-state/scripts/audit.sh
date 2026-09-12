#!/usr/bin/env bash
# audit.sh — run the permission-state stages once each, in order, with sectioned
# output.
#
# WHY THIS EXISTS
#
# Every stage downstream of the inventory consumes the inventory's records. Run
# as separate pipelines, `permission-state.sh` executes once per pipeline: five
# pipelines walked every scope five times and re-printed the whole surface
# inventory at the head of each. This runs it once and fans the records out.
#
# The stage scripts stay independently invocable and are not modified by this
# file. That is load-bearing rather than incidental: draft-auto-mode-rules
# invokes automode-block-lint.sh by path, and audit-pass composes the stages on
# its own terms. This is one convenience caller among several, never a gateway.
#
# DEFAULT BREADTH
#
# Bare invocation runs every READ-ONLY stage. The full pipeline is sub-second, and
# the stages a narrower default skipped (the plane lint, managed conformance, the
# autoMode block lint) are the ones most likely to carry an actionable finding.
# Flags NARROW; they never widen.
#
# Two lanes stay opt-in because neither is read-only in the way the rest are:
#   --oracle    spawns a real `claude -p` session (rewrites ~/.claude.json and
#               adds state under the config directory). Priced; never default.
#   --critique  shells out to `claude auto-mode critique`, which is slow and, in
#               measured runs, truncates or returns nothing while exiting 0.
#
# EXIT STATUS
#
# 0 when every stage that ran reported. Non-zero from a stage propagates: the
# inventory exits 2 without jq, and the merge exits 2 on empty input. A stage's
# own `status=` token, not this script's exit code, says whether what it read was
# complete — a run can exit 0 having been unable to open a single scope, which is
# exactly the confusion the status tokens exist to resolve.
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

# Flags narrow. With none, everything read-only runs.
if [[ "$narrowed" -eq 0 ]]; then
  want_entry=1 want_lint=1 want_managed=1 want_block=1
fi
# --oracle and --critique each imply the stage they modify, so passing one alone
# does what it says instead of silently doing nothing.
[[ "$oracle" -eq 1 ]] && want_entry=1
[[ "$critique" -eq 1 ]] && want_block=1

section() {
  printf '\n===== %s =====\n' "$1"
}

rc=0

# The autoMode block lint reads the CLI, not stdin, so it is the one stage that
# needs no inventory. Run it alone when it is all that was asked for.
if [[ "$want_scopes" -eq 0 && "$want_entry" -eq 0 && "$want_lint" -eq 0 && "$want_managed" -eq 0 && "$want_block" -eq 1 ]]; then
  section "autoMode block lint"
  if [[ "$critique" -eq 1 ]]; then
    bash "$HERE/automode-block-lint.sh" --critique || rc=$?
  else
    bash "$HERE/automode-block-lint.sh" || rc=$?
  fi
  exit "$rc"
fi

# One inventory walk, reused by every consumer below.
if ! records="$(bash "$HERE/permission-state.sh")"; then
  rc=$?
  echo "ERROR: the inventory stage failed (exit $rc); no downstream stage can run without it." >&2
  exit "$rc"
fi

section "Scopes and surfaces"
printf '%s\n' "$records"

if [[ "$want_scopes" -eq 1 ]]; then
  exit 0
fi

# The merge is the spine for the entry diff, so compute it once when either is
# wanted and print it only when the effective set was actually asked for.
merged=""
if [[ "$want_entry" -eq 1 ]]; then
  if merged="$(printf '%s\n' "$records" | bash "$HERE/permission-merge.sh")"; then
    section "Effective set"
    # The merge re-emits the inventory it was given; the section above already
    # printed that, so show only what the merge itself decided.
    printf '%s\n' "$merged" | grep -E '^(CAVEAT:|effective |inert |merge summary)' || true
  else
    rc=$?
    echo "ERROR: the merge stage failed (exit $rc)." >&2
  fi
fi

if [[ "$want_entry" -eq 1 && -n "$merged" ]]; then
  section "Auto-mode entry diff"
  # --diff-only carries the inventory's NOTEs and the merge's CAVEATs through, so
  # that a standalone run never hides an unreadable scope behind a summary of
  # zeros. Here the two sections above already printed them verbatim, so drop the
  # duplicates and keep this stage's own records. The stage keeps its honesty
  # when invoked directly; this caller just refuses to say it all three times.
  entry_filter() { grep -vE '^(NOTE:|MANAGED-NOTE:|LINT-NOTE:|CAVEAT:)' || true; }
  if [[ "$oracle" -eq 1 ]]; then
    printf '%s\n' "$merged" | bash "$HERE/automode-entry-diff.sh" --diff-only --oracle | entry_filter || rc=$?
  else
    printf '%s\n' "$merged" | bash "$HERE/automode-entry-diff.sh" --diff-only | entry_filter || rc=$?
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
  section "autoMode block lint"
  if [[ "$critique" -eq 1 ]]; then
    bash "$HERE/automode-block-lint.sh" --critique || rc=$?
  else
    bash "$HERE/automode-block-lint.sh" || rc=$?
  fi
fi

exit "$rc"
