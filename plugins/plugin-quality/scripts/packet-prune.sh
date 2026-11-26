#!/usr/bin/env bash
# Exit 0 = ran (dry run or apply) with nothing left unresolved.
# Exit 1 = ran, but at least one delete FAILED. Reported, never swallowed: a
#          retention pass that could not delete what it decided to delete has
#          not done its job, and exiting 0 would make that indistinguishable
#          from a clean run.
# Exit 2 = usage error, a refused root, a --days that yields no usable cutoff,
#          or a userland with neither date dialect.

set -uo pipefail

usage() {
  cat <<'EOF'
Retention pruning for the plugin-quality evidence tree: dry run unless --apply; a packet holding item*.md is never deleted.

Usage:
  bash packet-prune.sh --root <evidence-root> [--days N] [--apply]
  bash packet-prune.sh --help

  --root <dir>  the evidence/ directory: <root>/<session-id>/<target-slug>/<run-nonce>/
  --days N      delete packets whose nonce is older than N days (default 30)
  --apply       delete; without it, report what would be deleted
  --help, -h    print this help

Exit 0 = ran with nothing left unresolved; 1 = at least one delete failed;
2 = usage error, a refused root, an unusable --days, or no supported date dialect.
EOF
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

for packet in "$root_abs"/*/*/*; do
  [[ -d "$packet" ]] || continue
  scanned=$((scanned + 1))
  nonce="${packet##*/}"

  packet_real="$(cd "$packet" 2>/dev/null && pwd -P)" || packet_real=""
  if [[ -z "$packet_real" || "$packet_real" != "$root_abs"/* || -L "$packet" ]]; then
    echo "ESCAPED $packet"
    escaped=$((escaped + 1))
    continue
  fi

  if [[ -n "$(find "$packet_real" -iname 'item*.md' -print -quit 2>/dev/null)" ]]; then
    echo "RETAIN-ITEM $packet"
    retained_item=$((retained_item + 1))
    continue
  fi

  if [[ ! "$nonce" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || ! nonce_is_real_utc "$nonce"; then
    echo "UNPARSABLE $packet"
    unparsable=$((unparsable + 1))
    continue
  fi

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

deleted_key=would-delete
[[ "$apply" -eq 0 ]] || deleted_key=deleted
echo "scanned=$scanned $deleted_key=$deleted retained-item=$retained_item kept=$kept unparsable=$unparsable escaped=$escaped failed=$failed"
[[ "$apply" -eq 1 ]] || echo "(dry run — re-run with --apply to delete)"
[[ "$failed" -eq 0 ]] || exit 1
exit 0
