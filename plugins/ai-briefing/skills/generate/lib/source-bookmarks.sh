#!/usr/bin/env bash
# Per-source read bookmarks for /ai-briefing:generate.
#
#   source-bookmarks.sh get     --data-dir DIR --profile P --source S
#   source-bookmarks.sh advance --data-dir DIR --profile P --source S --state STATE --read READ --at DATE
#
# One file per source under DIR/<profile>/bookmarks/<source>, holding the
# ISO date (YYYY-MM-DD) the next run reads that source back to.
#   get      prints the stored date, or `none` when the source has no usable bookmark.
#   advance  moves the bookmark to --at only after a full read of the source:
#            --read full and --state data or empty. An unreadable source or a
#            partial read leaves the bookmark where it was.
# Exit: 0 ok (advance prints `advanced` or `unchanged`); 2 usage or an unsafe name;
# 1 the bookmark could not be written.
set -uo pipefail

die() {
  echo "source-bookmarks: $*" >&2
  exit 2
}

cmd="${1:-}"
[[ -n "$cmd" ]] && shift
data_dir="" profile="" source_id="" state="" read_kind="" at=""
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || die "missing value for $1"
  case "$1" in
  --data-dir) data_dir="$2" ;;
  --profile) profile="$2" ;;
  --source) source_id="$2" ;;
  --state) state="$2" ;;
  --read) read_kind="$2" ;;
  --at) at="$2" ;;
  *) die "unknown argument $1" ;;
  esac
  shift 2
done

[[ "$cmd" == get || "$cmd" == advance ]] || die "usage: source-bookmarks.sh get|advance --data-dir DIR --profile P --source S [--state data|empty|unreadable --read full|partial --at YYYY-MM-DD]"
[[ -n "$data_dir" ]] || die "--data-dir is required"
name_ok='^[a-z0-9][a-z0-9._-]{0,127}$'
[[ "$profile" =~ $name_ok && "$profile" != *..* ]] || die "unsafe or missing --profile"
[[ "$source_id" =~ $name_ok && "$source_id" != *..* ]] || die "unsafe or missing --source"

file="${data_dir%/}/$profile/bookmarks/$source_id"
date_ok='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

if [[ "$cmd" == get ]]; then
  if [[ ! -L "$file" && -f "$file" ]]; then
    mark="$(tr -d '[:space:]' <"$file")"
    if [[ "$mark" =~ $date_ok ]]; then
      echo "$mark"
      exit 0
    fi
  fi
  echo none
  exit 0
fi

[[ "$state" == data || "$state" == empty || "$state" == unreadable ]] || die "--state must be data, empty or unreadable"
[[ "$read_kind" == full || "$read_kind" == partial ]] || die "--read must be full or partial"
[[ "$at" =~ ^([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] || die "--at must be YYYY-MM-DD"
# Month length with leap February, in portable arithmetic (no GNU date -d).
y=$((10#${BASH_REMATCH[1]})) m=$((10#${BASH_REMATCH[2]})) d=$((10#${BASH_REMATCH[3]}))
case "$m" in
4 | 6 | 9 | 11) max=30 ;;
2) max=$(((y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28)) ;;
*) max=31 ;;
esac
((d <= max)) || die "--at is not a calendar date"

if [[ "$read_kind" != full || "$state" == unreadable ]]; then
  echo unchanged
  exit 0
fi

# Refuse a symlinked bookmark; write through a fresh mktemp file so a link
# planted at the temp path is never followed.
if [[ -L "$file" ]] || ! mkdir -p "${file%/*}" 2>/dev/null || ! tmp="$(mktemp "$file.XXXXXX" 2>/dev/null)"; then
  echo "source-bookmarks: cannot write bookmark for $source_id" >&2
  exit 1
fi
if ! { printf '%s\n' "$at" >"$tmp" && mv -f "$tmp" "$file"; } 2>/dev/null; then
  rm -f "$tmp"
  echo "source-bookmarks: cannot write bookmark for $source_id" >&2
  exit 1
fi
echo advanced
