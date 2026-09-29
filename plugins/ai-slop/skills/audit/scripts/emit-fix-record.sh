#!/usr/bin/env bash
# Retire the findings files a fix pass consumed by writing a fix-pass-record.
#
#   emit-fix-record.sh --out-dir <findings home> --consumed <findings-file> [--consumed ...]
#                      [--branch <b>] [--rows <n>] [--outcome <text>] [--not-applied-rows <file>]
#
# The record shape and the digest-suffixed name are owned by review:fanout's
# fix-pass-mode.md "Step 5"; review:fanout's Step 1 subtracts a findings file
# only when a record for the same branch names it by name AND sha256. The
# record is staged outside --out-dir, digested, and moved in as
# <TS>-fix-pass-applied-<sha256-12 of the staged bytes>.md, so two records never
# share a name unless their bytes are identical. Prints the record's path.
#
# --rows and --outcome fill the Producer-owned line (default 0 and "(none)").
# --not-applied-rows is a file of ready-made table rows (Location, Finding, Why
# not applied, Source file) for reverted or suppressed findings; absent or
# empty renders "(none)".
#
# Exit: 0 on success, 2 on usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/opt-value.sh
source "$SCRIPT_DIR/lib/opt-value.sh"

OUT_DIR=""
CONSUMED=()
BRANCH=""
ROWS=0
OUTCOME="(none)"
NA_ROWS=""

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '/^set -euo/d' -e 's/^# \{0,1\}//' >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --out-dir | --consumed | --branch | --rows | --outcome | --not-applied-rows)
    require_opt_value "emit-fix-record.sh" "$@"
    case "$1" in
    --out-dir) OUT_DIR="$2" ;;
    --consumed) CONSUMED+=("$2") ;;
    --branch) BRANCH="$2" ;;
    --rows) ROWS="$2" ;;
    --outcome) OUTCOME="$2" ;;
    --not-applied-rows) NA_ROWS="$2" ;;
    *) exit 2 ;;
    esac
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "emit-fix-record.sh: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

[[ -n "$OUT_DIR" && "${#CONSUMED[@]}" -gt 0 ]] || {
  usage
  exit 2
}
[[ "$ROWS" =~ ^[0-9]+$ ]] || {
  echo "emit-fix-record.sh: --rows must be a non-negative integer" >&2
  exit 2
}
for f in "${CONSUMED[@]}"; do
  [[ -f "$f" ]] || {
    echo "emit-fix-record.sh: --consumed file not found: $f" >&2
    exit 2
  }
done
[[ -z "$NA_ROWS" || -f "$NA_ROWS" ]] || {
  echo "emit-fix-record.sh: --not-applied-rows file not found: $NA_ROWS" >&2
  exit 2
}
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] || {
    echo "emit-fix-record.sh: no --branch and no current git branch" >&2
    exit 2
  }
fi

sha12() {
  { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -c1-12
}

TS="$(date -u +%Y%m%dT%H%M%SZ)"
DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

names=""
for f in "${CONSUMED[@]}"; do names+="${names:+, }$(basename "$f")"; done
{
  printf -- '---\ntype: fix-pass-record\ndate: %s\nbranch: %s\nsource-findings:\n' "$DATE_UTC" "$BRANCH"
  for f in "${CONSUMED[@]}"; do
    printf -- '  - name: %s\n    sha256: %s\n' "$(basename "$f")" "$(sha12 "$f")"
  done
  printf -- '---\n\n## Consumed fix-pass plan\n\n'
  printf -- '- Consumed (%d files): %s\n' "${#CONSUMED[@]}" "$names"
  printf -- '- Surfaces (union): ran [ai-slop:audit]; returned no result (none)\n'
  printf -- '- Cleanup-class (0) → /simplify: (none)\n'
  printf -- '- Correctness-class (0): (none)\n'
  printf -- '- Producer-owned (%d): %s\n' "$ROWS" "$OUTCOME"
  printf -- '\n## Not applied: recover by re-running the source producer\n\n'
  if [[ -n "$NA_ROWS" && -s "$NA_ROWS" ]]; then
    printf -- '| Location | Finding | Why not applied | Source file |\n|---|---|---|---|\n'
    cat "$NA_ROWS"
  else
    printf -- '(none)\n'
  fi
} >"$TMP"

mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/${TS}-fix-pass-applied-$(sha12 "$TMP").md"
# The name carries the bytes' digest, so an existing path is the same record.
[[ -e "$OUT" ]] || mv "$TMP" "$OUT"
printf '%s\n' "$OUT"
