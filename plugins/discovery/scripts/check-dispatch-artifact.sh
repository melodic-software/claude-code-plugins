#!/usr/bin/env bash
# Exit 0 = a usable artifact set is on disk (status=usable)
# Exit 1 = the slice is readable but its artifact set is NOT usable — no index,
#          an empty index, an index still marked `Run status: in progress`,
#          an index naming no sidecars, a named sidecar that is
#          missing or empty, an index no newer than the baseline, a payload
#          pointer naming a different file, or a sidecar-count mismatch
#          (status=unusable). The parent discards the run; it does not proceed.
# Exit 2 = the gate cannot grade — the slice path is missing, is not a
#          directory, or names a baseline file that does not exist — plus usage
#          errors, including a missing or malformed `--index-name`. FAIL
#          CLOSED: a slice this gate cannot read is never reported as usable.

set -uo pipefail

usage() {
  cat <<'EOF'
Deterministic acceptance gate for a dispatched /discovery:explore or /discovery:research run.
Usage: check-dispatch-artifact.sh <memory-slice-path> --index-name <EXPLORE.md|RESEARCH.md> [options]
  --index-name <name>      index file to grade at the slice root. Required.
  --newer-than <file>      the index must be newer than this pre-dispatch baseline
  --expect-index <path>    the payload's artifact pointer must resolve to the graded index
  --expect-sidecars <n>    the payload's sidecar count must match the index
Exit: 0 a usable artifact set is on disk; 1 the artifact set is not usable;
2 the gate cannot grade, or a usage error (fail closed).
EOF
}

slice=""
index_name=""
expect_sidecars=""
newer_than=""
expect_index=""

canonical() {
  local path="$1" dir base
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  if [[ -d "$dir" ]]; then
    printf '%s/%s' "$(cd "$dir" && pwd -P)" "$base"
  else
    printf '%s' "$path"
  fi
}

# shellcheck source=../lib/opt-value.sh
opt_value_dir="${BASH_SOURCE[0]%/*}"
[[ "$opt_value_dir" != "${BASH_SOURCE[0]}" ]] || opt_value_dir=.
source "$opt_value_dir/../lib/opt-value.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --index-name)
    require_opt_value check-dispatch-artifact.sh "$@"
    if [[ ! "$2" =~ ^[A-Za-z0-9_-]+\.md$ ]]; then
      echo "error: --index-name must be <NAME>.md with NAME in [A-Za-z0-9_-], got: $2" >&2
      exit 2
    fi
    index_name="$2"
    shift 2
    ;;
  --newer-than)
    require_opt_value check-dispatch-artifact.sh "$@"
    newer_than="$2"
    shift 2
    ;;
  --expect-index)
    require_opt_value check-dispatch-artifact.sh "$@"
    expect_index="$2"
    shift 2
    ;;
  --expect-sidecars)
    require_opt_value check-dispatch-artifact.sh "$@"
    if [[ ! "$2" =~ ^[0-9]+$ ]]; then
      echo "error: --expect-sidecars takes a non-negative integer, got: $2" >&2
      exit 2
    fi
    expect_sidecars="$2"
    shift 2
    ;;
  -*)
    echo "error: unknown argument: $1" >&2
    exit 2
    ;;
  *)
    if [[ -n "$slice" ]]; then
      echo "error: expected exactly one memory-slice path, got a second: $1" >&2
      exit 2
    fi
    slice="$1"
    shift
    ;;
  esac
done

if [[ -z "$slice" ]]; then
  echo "error: a memory-slice path is required" >&2
  exit 2
fi

if [[ -z "$index_name" ]]; then
  echo "error: --index-name is required (EXPLORE.md or RESEARCH.md)" >&2
  exit 2
fi
sidecar_prefix="${index_name%.md}"

while [[ "$slice" == */ && "$slice" != "/" ]]; do
  slice="${slice%/}"
done

if [[ ! -d "$slice" ]]; then
  echo "error: memory slice not found or not a directory: $slice" >&2
  exit 2
fi

if [[ -n "$newer_than" && ! -e "$newer_than" ]]; then
  echo "error: --newer-than baseline does not exist: $newer_than" >&2
  exit 2
fi

freshness="unchecked"
pointer="unchecked"

verdict() {
  printf 'index=%s sidecars=%s missing=%s freshness=%s pointer=%s status=%s\n' \
    "$1" "$2" "$3" "$freshness" "$pointer" "$4"
}

index="$slice/$index_name"

if [[ ! -f "$index" ]]; then
  echo "unusable: no $index_name at $slice" >&2
  verdict "<none>" 0 0 unusable
  exit 1
fi

if [[ ! -s "$index" ]]; then
  echo "unusable: index is empty: $index" >&2
  verdict "$index" 0 0 unusable
  exit 1
fi

slot_state="$(awk '
  function norm(s) {
    sub(/\r+$/, "", s)
    if (FNR == 1 && index(s, bom) == 1) s = substr(s, length(bom) + 1)
    return s
  }
  function yamlish(s) {
    return s ~ /^[ \t]*$/ || s ~ /^[ \t]/ || s ~ /^#/ || s == "-" || s ~ /^- / ||
      s ~ /^[^:[:space:]][^:]*:([ \t]|$)/
  }
  BEGIN { bom = "\357\273\277" }
  NR == FNR {
    line = norm($0)
    if (FNR == 1) { opened = (line == "---"); next }
    if (opened && !fm_end) {
      if (line == "---" || line == "...") fm_end = FNR
      else if (!yamlish(line)) opened = 0
    }
    next
  }
  FNR <= fm_end { next }
  { line = norm($0) }
  titled {
    if (line ~ /^[ \t]*$/) next
    if (tolower(line) ~ /^run[ \t]+status[ \t]*:[ \t]*in[ \t_-]*progress[ \t]*$/) print "in-progress"
    exit
  }
  {
    match(line, /^ */)
    if (RLENGTH <= 3) {
      rest = substr(line, RLENGTH + 1)
      c = substr(rest, 1, 1)
      if (c == "`" || c == "~") {
        n = 0
        while (substr(rest, n + 1, 1) == c) n++
        if (n >= 3 && !fenced) { fenced = 1; fchar = c; flen = n; next }
        if (n >= 3 && c == fchar && n >= flen && substr(rest, n + 1) ~ /^[ \t]*$/) { fenced = 0; next }
      }
    }
  }
  !fenced && line ~ /^# / { titled = 1 }
' "$index" "$index")"
if [[ "$slot_state" == "in-progress" ]]; then
  echo "unusable: index is still marked Run status: in progress; the run stopped before its final write: $index" >&2
  verdict "$index" 0 0 unusable
  exit 1
fi

referenced=()
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  referenced+=("$name")
done < <(grep -oE "${sidecar_prefix}-[A-Za-z0-9._-]+\.md" "$index" | sort -u)

if [[ ${#referenced[@]} -eq 0 ]]; then
  echo "unusable: index names no ${sidecar_prefix}-<section>.md sidecar: $index" >&2
  verdict "$index" 0 0 unusable
  exit 1
fi

missing=0
for name in "${referenced[@]}"; do
  sidecar="$slice/$name"
  if [[ ! -f "$sidecar" ]]; then
    echo "unusable: index names a sidecar that was never written: $sidecar" >&2
    missing=$((missing + 1))
  elif [[ ! -s "$sidecar" ]]; then
    echo "unusable: index names an empty sidecar: $sidecar" >&2
    missing=$((missing + 1))
  fi
done

count=${#referenced[@]}
unusable=$((missing > 0 ? 1 : 0))

if [[ -n "$newer_than" ]]; then
  if [[ "$index" -nt "$newer_than" ]]; then
    freshness="newer"
  else
    freshness="stale"
    echo "unusable: index is not newer than the pre-dispatch baseline — this run may have written nothing: $index" >&2
    unusable=1
  fi
fi

if [[ -n "$expect_index" ]]; then
  if [[ "$(canonical "$expect_index")" == "$(canonical "$index")" ]]; then
    pointer="matches"
  else
    pointer="mismatch"
    echo "unusable: payload pointer names $expect_index; this gate graded $index" >&2
    unusable=1
  fi
fi

if [[ -n "$expect_sidecars" && "$expect_sidecars" -ne "$count" ]]; then
  echo "unusable: payload reported $expect_sidecars sidecar(s); the index names $count" >&2
  unusable=1
fi

if [[ "$unusable" -ne 0 ]]; then
  verdict "$index" "$count" "$missing" unusable
  exit 1
fi

verification="$(awk '
  BEGIN { bom = "\357\273\277" }
  { sub(/\r+$/, "") }
  NR == 1 {
    if (index($0, bom) == 1) $0 = substr($0, length(bom) + 1)
    if ($0 != "---") exit
    next
  }
  $0 == "---" || $0 == "..." { exit }
  /^verification:/ {
    v = $0
    sub(/^verification:[ \t]*/, "", v)
    sub(/[ \t]+$/, "", v)
    if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
    print v
    exit
  }
' "$index")"

verdict "$index" "$count" "$missing" usable
printf 'verification=%s\n' "${verification:-unrecorded}"
exit 0
