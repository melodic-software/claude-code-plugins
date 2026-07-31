#!/usr/bin/env bash
# Retention pruning for the plugin-quality evidence tree.
#
# The skill's retention rule used to be prose telling the model to "delete
# packet directories older than 30 days" — a recursive delete, over the one
# tree that also holds the only copy of an unattended run's emitted work item
# (`item.md`), left entirely to model obedience. This script is that rule as a
# mechanism, so the safety properties hold whether or not the model reads them.
#
# Three properties are enforced HERE, not in prose:
#
#   1. Dry run by default. Nothing is deleted without an explicit `--apply`.
#   2. A packet holding `item.md` ANYWHERE beneath it is NEVER deleted, at any
#      age. That file is a drafted-but-unemitted deliverable; step 6's
#      unattended clause makes it the ONLY copy of the audit's entire output.
#      Retention must not be the thing that destroys it. The search is recursive
#      and case-insensitive, because a deliverable one directory down is exactly
#      as unrecoverable as one at the top. Retained packets are reported, so an
#      operator can see the tree is growing and act on it.
#   3. Nothing outside the evidence root is ever touched. Containment is
#      re-established per candidate by canonicalizing it (`cd` + `pwd -P`), not
#      once for the root: a symlink anywhere on the way down — a symlinked
#      session directory suffices — otherwise yields a path whose real location
#      is elsewhere, and `rm -rf` follows real locations. Such candidates are
#      reported as ESCAPED and skipped, and deletion targets the canonical path.
#
# Age comes from the nonce directory NAME (`YYYYMMDDTHHMMSSZ`), not from mtime:
# mtime is rewritten by any tool that touches the tree (including the sibling
# PostToolUse formatters that rewrite packet files in place), so grading age by
# mtime would make retention depend on the same mutation the packet exists to
# resist. FAIL CLOSED: a directory whose name is not a parsable nonce is never
# deleted — it is reported as unparsable. Parsable means a real UTC instant, not
# merely the right characters: `00000000T000000Z` has a nonce's exact shape and
# names no date, so it is graded UNPARSABLE rather than compared as an ancient
# timestamp and destroyed.
#
# Usage:
#   bash packet-prune.sh --root <evidence-root> [--days N] [--apply]
#   bash packet-prune.sh --help
#
# <evidence-root> is the `evidence/` directory under this plugin's data
# directory. Its layout is <root>/<session-id>/<target-slug>/<run-nonce>/.
#
# Output (stdout, greppable): one `<verdict> <path>` line per packet, then a
# summary line. An apply run reports `deleted=<n>`; a dry run reports
# `would-delete=<n>` instead, so a summary never claims deletions that did not
# happen. Both carry
# `scanned= retained-item= kept= unparsable= escaped= failed=`.
# Verdicts: DELETE (or WOULD-DELETE in dry run), RETAIN-ITEM, KEEP, UNPARSABLE,
# ESCAPED, FAILED.
#
# Exit 0 = ran (dry run or apply) with nothing left unresolved.
# Exit 1 = ran, but at least one delete FAILED. Reported, never swallowed: a
#          retention pass that could not delete what it decided to delete has
#          not done its job, and exiting 0 would make that indistinguishable
#          from a clean run.
# Exit 2 = usage error, a refused root, a --days that yields no usable cutoff,
#          or a userland with neither date dialect.

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

# Cutoff as a comparable YYYYMMDDTHHMMSSZ string. A retention pass that cannot
# grade age must delete nothing, so both the missing-binary and the
# unusable-value cases refuse rather than fall back to a permissive cutoff.
# Probe which date dialect exists BEFORE computing the cutoff, so a computation
# that fails for a different reason — an out-of-range --days, say — is not
# misreported as a missing binary and sent to the wrong fix.
if date -u -d "1 days ago" +%Y >/dev/null 2>&1; then # portability-ok: GNU-first probe of a dual-dialect pair; the BSD (-v) form is the elif below
  date_dialect=gnu
elif date -u -v-1d +%Y >/dev/null 2>&1; then
  date_dialect=bsd
else
  echo "error: neither GNU (date -d) nor BSD (date -v) date is available — cannot grade packet age" >&2
  exit 2
fi

if [[ "$date_dialect" == gnu ]]; then
  # portability-ok: reached only when the GNU dialect was probed successfully above
  cutoff="$(date -u -d "$days days ago" +%Y%m%dT%H%M%SZ 2>/dev/null)" || cutoff=""
else
  cutoff="$(date -u -v-"${days}"d +%Y%m%dT%H%M%SZ 2>/dev/null)" || cutoff=""
fi
if [[ ! "$cutoff" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]; then
  echo "error: --days $days did not yield a usable cutoff from the $date_dialect date implementation (out of range?) — refusing to prune" >&2
  exit 2
fi

# True when <nonce> names a real UTC instant, not merely something shaped like
# one. The character-shape regex below is not a date check: `00000000T000000Z`
# and `20260231T000000Z` both match it, neither names an instant that exists, and
# lexical comparison grades both as ancient — so a shape-only test hands them to
# `rm -rf` under `--apply`, destroying an ungradable packet the fail-closed rule
# promises to keep. Round-trip the calendar value through `date` and require it
# to reproduce the nonce EXACTLY: a value the implementation rejects outright
# (GNU) or silently normalizes to a different day (BSD turns Feb 31 into Mar 3)
# cannot come back identical. Fail closed in every uncertain case — a missing
# binary, a non-zero exit, empty output, or any mismatch returns false, which
# routes the packet to UNPARSABLE and never to DELETE.
nonce_is_real_utc() {
  local nonce="$1" ymd="${1:0:8}" hms="${1:9:6}" round=""
  if [[ "$date_dialect" == gnu ]]; then
    # portability-ok: reached only when the GNU dialect was probed successfully above
    round="$(date -u -d "${ymd:0:4}-${ymd:4:2}-${ymd:6:2} ${hms:0:2}:${hms:2:2}:${hms:4:2}" +%Y%m%dT%H%M%SZ 2>/dev/null)"
  else
    round="$(date -u -j -f %Y%m%dT%H%M%SZ "$nonce" +%Y%m%dT%H%M%SZ 2>/dev/null)"
  fi
  [[ -n "$round" && "$round" == "$nonce" ]]
}

# Self-check the round-trip against a value already known to be a real instant:
# the cutoff this script just computed and validated. If a known-good nonce does
# not reproduce itself, the round-trip is broken in this userland — a dialect
# whose `-j -f` parse is unavailable or spells its output differently, say — and
# EVERY packet would grade UNPARSABLE. That is fail-closed, but silently: pruning
# would stop forever while still reporting success and exiting 0. Refuse loudly
# instead, the same way a missing `date` already does. This is also the only
# check that can catch a broken BSD branch, which no GNU-only CI can reach.
if ! nonce_is_real_utc "$cutoff"; then
  echo "error: the $date_dialect date implementation cannot round-trip a known-good nonce ($cutoff) — cannot grade packet age, refusing to prune" >&2
  exit 2
fi

scanned=0
deleted=0
retained_item=0
kept=0
unparsable=0
failed=0
escaped=0

# <root>/<session-id>/<target-slug>/<run-nonce>
for packet in "$root_abs"/*/*/*; do
  [[ -d "$packet" ]] || continue
  scanned=$((scanned + 1))
  nonce="$(basename "$packet")"

  # Containment is re-established per candidate, not once for the root. Checking
  # only the root is insufficient: a symlink ANYWHERE on the way down — a
  # symlinked session directory is enough — makes the glob yield a path whose
  # real location is outside the tree, and `rm -rf` follows the real location.
  # Canonicalize the candidate and require it to still live under the root.
  packet_real="$(cd "$packet" 2>/dev/null && pwd -P)" || packet_real=""
  if [[ -z "$packet_real" || ("$packet_real" != "$root_abs"/*) ]]; then
    echo "ESCAPED $packet"
    escaped=$((escaped + 1))
    continue
  fi
  # Never delete through a symlink even when its target is inside the root:
  # removing the link is not removing the packet, and following it is how the
  # containment check above becomes load-bearing rather than decorative.
  if [[ -L "$packet" ]]; then
    echo "ESCAPED $packet"
    escaped=$((escaped + 1))
    continue
  fi

  # An unemitted deliverable outranks retention unconditionally, and is checked
  # BEFORE age so the reported reason is the real one. Searched RECURSIVELY and
  # case-insensitively: the packet layout does not forbid an item written into a
  # subdirectory, and a deliverable one level down is exactly as unrecoverable.
  if [[ -n "$(find "$packet_real" -iname 'item.md' -print -quit 2>/dev/null)" ]]; then
    echo "RETAIN-ITEM $packet"
    retained_item=$((retained_item + 1))
    continue
  fi

  # Shape THEN calendar. The shape test alone is not a date test, and a name that
  # merely looks like a nonce must not be graded as one — see nonce_is_real_utc.
  if [[ ! "$nonce" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || ! nonce_is_real_utc "$nonce"; then
    echo "UNPARSABLE $packet"
    unparsable=$((unparsable + 1))
    continue
  fi

  # Lexical comparison is chronological for this fixed-width UTC format.
  if [[ "$nonce" < "$cutoff" ]]; then
    if [[ "$apply" -eq 1 ]]; then
      if rm -rf -- "$packet_real"; then
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

if [[ "$apply" -eq 1 ]]; then
  echo "scanned=$scanned deleted=$deleted retained-item=$retained_item kept=$kept unparsable=$unparsable escaped=$escaped failed=$failed"
else
  # Never report `deleted=` for a run that deleted nothing: a summary line is
  # what a caller greps, and one that claims deletions in a dry run is a lie a
  # log reader cannot catch.
  echo "scanned=$scanned would-delete=$deleted retained-item=$retained_item kept=$kept unparsable=$unparsable escaped=$escaped failed=$failed"
  echo "(dry run — re-run with --apply to delete)"
fi
[[ "$failed" -eq 0 ]] || exit 1
exit 0
