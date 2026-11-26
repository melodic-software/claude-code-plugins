#!/usr/bin/env bash
# Exit: 0 = a record was written; 1 = the path is not a readable directory;
# 2 = usage; 3 = refused, nothing was written, the reason is on stderr.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACE_AWK="$SCRIPT_DIR/trace-flow.awk"
# shellcheck source=../../../lib/github-remote.sh
source "$SCRIPT_DIR/../../../lib/github-remote.sh"

usage() {
  cat <<'EOF'
Collect a call-sequence trace from one C# entry point.
Usage: collect-flow.sh --repo <path> --entry <entry> [--depth N] [--out <file>] [--generated-on <date>]
  --repo <path>          repository to read (tracked *.cs files only)
  --entry <entry>        a route, a verb and route, Type.Method, or a method name
  --depth N              how deep to follow callees
  --out <file>           where flow.json is written (default stdout)
  --generated-on <date>  date recorded in the record
Writes flow.json, schema_version 1, one hop object per line.
Exit: 0 a record was written; 1 the path is not a readable directory; 2 usage;
3 refused, nothing written, the reason on stderr.
EOF
}

die() {
  printf 'collect-flow.sh: %s\n' "$1" >&2
  exit "$2"
}

repo=""
out_file=""
entry=""
depth="5"
generated_on=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h) usage; exit 0 ;;
  --repo) [[ $# -ge 2 ]] || die "--repo needs a path" 2; repo="$2"; shift 2 ;;
  --repo=*) repo="${1#--repo=}"; shift ;;
  --entry)
    [[ $# -ge 2 ]] || die "--entry needs an entry: a route, a verb and a route, Type.Method, or a method name" 2
    entry="$2"; shift 2 ;;
  --entry=*) entry="${1#--entry=}"; shift ;;
  --depth) [[ $# -ge 2 ]] || die "--depth needs a positive integer" 2; depth="$2"; shift 2 ;;
  --depth=*) depth="${1#--depth=}"; shift ;;
  --out) [[ $# -ge 2 ]] || die "--out needs a path" 2; out_file="$2"; shift 2 ;;
  --out=*) out_file="${1#--out=}"; shift ;;
  --generated-on) [[ $# -ge 2 ]] || die "--generated-on needs a date" 2; generated_on="$2"; shift 2 ;;
  --generated-on=*) generated_on="${1#--generated-on=}"; shift ;;
  *) die "unknown argument: $1" 2 ;;
  esac
done

[[ -n "$entry" ]] || die "--entry is required" 2
[[ "$depth" =~ ^[0-9]+$ && "$depth" -ge 1 ]] || die "--depth must be a positive integer" 2
[[ -n "$repo" ]] || repo="$(pwd)"
[[ -d "$repo" ]] || die "not a directory: $repo" 1
repo="$(cd "$repo" && pwd)"

if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "refused: not a git repository, so there is no tracked C# source to cite: $repo" 3
fi

origin_url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
subject="$(github_repo_name "$origin_url")" || subject="$(basename "$repo")"

if [[ -z "$generated_on" ]]; then
  generated_on="$(git -C "$repo" log -1 --format=%cs 2>/dev/null || true)"
  [[ -n "$generated_on" ]] || generated_on="unknown"
fi

list="$(mktemp)"
status="$(mktemp)"
trap 'rm -f "$list" "$status"' EXIT

while IFS= read -r -d '' rel; do
  case "$rel" in
  *.cs) [[ -f "$repo/$rel" && ! -L "$repo/$rel" ]] && printf '%s\n' "$rel" ;;
  *) ;;
  esac
done < <(git -C "$repo" ls-files -z --cached) >"$list"

[[ -s "$list" ]] || die "refused: no tracked C# source. This adapter reads C# call sites only." 3

record="$(
  FLOW_ROOT="$repo" FLOW_ENTRY="$entry" FLOW_DEPTH="$depth" \
    FLOW_SUBJECT="$subject" FLOW_GENERATED_ON="$generated_on" FLOW_STATUS="$status" \
    awk -f "$TRACE_AWK" "$list"
)" || true

[[ ! -s "$status" ]] || die "$(<"$status")" 3
[[ -n "$record" ]] || die "refused: the tracer produced no record" 3

if [[ -n "$out_file" ]]; then
  mkdir -p "$(dirname "$out_file")"
  printf '%s\n' "$record" >"$out_file"
else
  printf '%s\n' "$record"
fi
exit 0
