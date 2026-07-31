#!/usr/bin/env bash
# Retention pruning for the plugin-quality evidence tree.
#
# The skill's retention rule used to be prose telling the model to "delete
# packet directories older than 30 days" — a recursive delete, over the one
# tree that also holds the only copy of an unattended run's emitted work item
# (`item.md`), left entirely to model obedience. This script is that rule as a
# mechanism, so the safety properties hold whether or not the model reads them.
#
# Two properties are enforced HERE, not in prose:
#
#   1. Dry run by default. Nothing is deleted without an explicit `--apply`.
#   2. A packet holding `item.md` is NEVER deleted, at any age. That file is a
#      drafted-but-unemitted deliverable; step 6's unattended clause makes it
#      the ONLY copy of the audit's entire output. Retention must not be the
#      thing that destroys it. Retained packets are reported, so an operator
#      can see the tree is growing and act on it.
#
# Age comes from the nonce directory NAME (`YYYYMMDDTHHMMSSZ`), not from mtime:
# mtime is rewritten by any tool that touches the tree (including the sibling
# PostToolUse formatters that rewrite packet files in place), so grading age by
# mtime would make retention depend on the same mutation the packet exists to
# resist. FAIL CLOSED: a directory whose name is not a parsable nonce is never
# deleted — it is reported as unparsable.
#
# Usage:
#   bash packet-prune.sh --root <evidence-root> [--days N] [--apply]
#   bash packet-prune.sh --help
#
# <evidence-root> is the `evidence/` directory under this plugin's data
# directory. Its layout is <root>/<session-id>/<target-slug>/<run-nonce>/.
#
# Output (stdout, greppable): one `<verdict> <path>` line per packet, then a
# summary line
# `scanned=<n> deleted=<n> retained-item=<n> kept=<n> unparsable=<n> failed=<n>`.
# Verdicts: DELETE (or WOULD-DELETE in dry run), RETAIN-ITEM, KEEP, UNPARSABLE,
# FAILED.
#
# Exit 0 = ran (dry run or apply) with nothing left unresolved.
# Exit 1 = ran, but at least one delete FAILED. Reported, never swallowed: a
#          retention pass that could not delete what it decided to delete has
#          not done its job, and exiting 0 would make that indistinguishable
#          from a clean run.
# Exit 2 = usage error, a refused root, or a userland that cannot grade age.

set -uo pipefail

usage() {
  # Sentinel range rather than fixed line numbers, so the printed usage cannot
  # silently truncate when this header grows.
  sed -n '/^# Retention pruning/,/^# Exit 0/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

root=""
days=30
apply=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --root)
    [[ $# -ge 2 ]] || {
      echo "error: --root needs a value" >&2
      exit 2
    }
    root="$2"
    shift 2
    ;;
  --days)
    [[ $# -ge 2 ]] || {
      echo "error: --days needs a value" >&2
      exit 2
    }
    days="$2"
    shift 2
    ;;
  --apply)
    apply=1
    shift
    ;;
  *)
    echo "error: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

[[ -n "$root" ]] || {
  echo "error: --root is required" >&2
  exit 2
}
[[ "$days" =~ ^[0-9]+$ ]] || {
  echo "error: --days must be a non-negative integer, got: $days" >&2
  exit 2
}
[[ -d "$root" ]] || {
  echo "error: --root is not a directory: $root" >&2
  exit 2
}

# Root containment. This script's only job is deleting directories, so a
# mistyped path is the whole risk surface. Require the root to be literally
# named `evidence` — the one directory name the packet layout gives it — so a
# fat-fingered `--root ~` or `--root .` is refused rather than walked.
root_abs="$(cd "$root" && pwd -P)" || {
  echo "error: cannot resolve --root: $root" >&2
  exit 2
}
case "$root_abs" in
*/evidence) ;;
*)
  echo "error: refusing to prune a root not named 'evidence': $root_abs" >&2
  echo "       (the packet layout is <plugin-data-dir>/evidence/<session>/<slug>/<nonce>/)" >&2
  exit 2
  ;;
esac

# Cutoff as a comparable YYYYMMDDTHHMMSSZ string. Computed with the GNU or BSD
# date dialect; neither available means we cannot grade age, and a retention
# pass that cannot grade age must delete nothing.
# portability-ok: GNU-first of a dual-dialect pair — the BSD (-v) form is the
# `||` fallback on the next line, and a userland with neither is refused below
# rather than defaulting to a cutoff that would delete everything.
cutoff="$(date -u -d "$days days ago" +%Y%m%dT%H%M%SZ 2>/dev/null)" ||
  cutoff="$(date -u -v-"${days}"d +%Y%m%dT%H%M%SZ 2>/dev/null)" || cutoff=""
if [[ -z "$cutoff" ]]; then
  echo "error: neither GNU (date -d) nor BSD (date -v) date is available — cannot grade packet age" >&2
  exit 2
fi

scanned=0
deleted=0
retained_item=0
kept=0
unparsable=0
failed=0

# <root>/<session-id>/<target-slug>/<run-nonce>
for packet in "$root_abs"/*/*/*; do
  [[ -d "$packet" ]] || continue
  scanned=$((scanned + 1))
  nonce="$(basename "$packet")"

  # An unemitted deliverable outranks retention unconditionally, and is checked
  # BEFORE age so the reported reason is the real one.
  if [[ -e "$packet/item.md" ]]; then
    echo "RETAIN-ITEM $packet"
    retained_item=$((retained_item + 1))
    continue
  fi

  if [[ ! "$nonce" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]; then
    echo "UNPARSABLE $packet"
    unparsable=$((unparsable + 1))
    continue
  fi

  # Lexical comparison is chronological for this fixed-width UTC format.
  if [[ "$nonce" < "$cutoff" ]]; then
    if [[ "$apply" -eq 1 ]]; then
      if rm -rf -- "$packet"; then
        echo "DELETE $packet"
        deleted=$((deleted + 1))
      else
        echo "FAILED $packet"
        echo "error: failed to delete: $packet" >&2
        failed=$((failed + 1))
      fi
    else
      echo "WOULD-DELETE $packet"
      deleted=$((deleted + 1))
    fi
  else
    echo "KEEP $packet"
    kept=$((kept + 1))
  fi
done

echo "scanned=$scanned deleted=$deleted retained-item=$retained_item kept=$kept unparsable=$unparsable failed=$failed"
[[ "$apply" -eq 1 ]] || echo "(dry run — re-run with --apply to delete)"
[[ "$failed" -eq 0 ]] || exit 1
exit 0
