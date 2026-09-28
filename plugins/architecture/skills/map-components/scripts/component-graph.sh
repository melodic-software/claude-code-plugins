#!/usr/bin/env bash
# Collect a cited .NET build-declaration graph for one repository.
#
# WHY. map-components draws a C4 component view from dependency-graph.json. Until
# map-dependencies is what writes that file, this script emits the same
# schema_version 1 record from ProjectReference and PackageReference
# declarations. It does not read source imports, evaluate MSBuild, or fetch.
# A present dependency-graph.json from map-dependencies wins; the skill does
# not run this script over one.
#
# Usage:
#   component-graph.sh [--repo <path>] [--out <file>] [--generated-on <date>]
#   component-graph.sh --help
#
# Output: the record on stdout, or in --out when that flag is set.
#
#   {
#     "schema_version": 1,
#     "generated_on": "YYYY-MM-DD",
#     "subject": "<directory basename>",
#     "ecosystem": "dotnet" | "unknown",
#     "unknown_reason": "<empty when ecosystem is dotnet>",
#     "unshipped": "<other build manifests seen, or empty>",
#     "node_threshold": 24,
#     "nodes": [ one {"id":...} object per line, or [] ],
#     "edges": [ one {"from":...} object per line, or [] ]
#   }
#
#   nodes: id, name, path, ecosystem, kind (project|package)
#   edges: from, to, kind (project|package|unresolved), evidence
#          evidence is "<repo-relative file>: <matched declaration>"
#
# A ProjectReference is kind "project" only when the Include path, resolved
# relative to the declaring project and with . and .. collapsed, is a project
# file this scan charted inside the repository root. A missing target, a path
# that escapes the root, an absolute path, or a glob is kind "unresolved".
# Nothing is matched by project name against some other file on disk.
# PackageReference edges point at id "nuget:<Include>".
#
# The matched form is an opening tag whose Include attribute sits on that same
# line, double-quoted. A multiline opening tag, a single-quoted Include, and
# an Update attribute are not read.
#
# No .NET project file is ecosystem "unknown", with empty node and edge arrays
# and a reason. That is not an empty architecture.
#
# generated_on defaults to the subject repository's HEAD commit date, not the
# wall clock, so a second run on the same checkout does not churn. A tree with
# no commit records "unknown". --generated-on overrides it.
#
# Portability: bash plus POSIX awk/grep/sed/find. No jq, no grep -P, no python.
#
# Exit: 0 = a record was written (including ecosystem unknown); 1 = the path
# is not a readable directory; 2 = usage.
set -uo pipefail

NODE_THRESHOLD=24

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'component-graph.sh: %s\n' "$1" >&2
  exit "$2"
}

JSON_ESC=""
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  JSON_ESC="$s"
}

# Collapse . and .. . Return 1 when the path escapes above its start.
normalize_inside() {
  local raw="$1" seg joined="" s
  local -a segs=() out=()
  local IFS=/
  # shellcheck disable=SC2206
  segs=($raw)
  for seg in "${segs[@]}"; do
    case "$seg" in
    '' | '.') continue ;;
    '..')
      if [[ ${#out[@]} -eq 0 ]]; then
        return 1
      fi
      unset 'out[${#out[@]}-1]'
      ;;
    *) out+=("$seg") ;;
    esac
  done
  for s in "${out[@]+"${out[@]}"}"; do
    if [[ -z "$joined" ]]; then
      joined="$s"
    else
      joined="$joined/$s"
    fi
  done
  [[ -n "$joined" ]] || return 1
  printf '%s' "$joined"
}

# Print absolute paths of regular files whose basename matches one of the
# globs. Prune VCS, dependency, and .NET build output directories.
walk_files() {
  local root="$1"
  shift
  local -a name_args=()
  local pattern
  for pattern in "$@"; do
    if [[ ${#name_args[@]} -gt 0 ]]; then
      name_args+=(-o)
    fi
    name_args+=(-name "$pattern")
  done
  find "$root" -mindepth 1 \
    \( \
    -name .git -o -name node_modules -o -name bin -o -name obj \
    -o -name vendor -o -name .vs -o -name packages -o -name TestResults \
    \) -prune -o \
    \( -type f \( "${name_args[@]}" \) -print \)
}

# kind<TAB>include<TAB>declaration for Include attributes on the opening line.
item_records() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    {
      line = $0
      sub(/\r$/, "", line)
      rest = line
      while (match(rest, /<(Package|Project)Reference[^>]*Include="[^"]*"/)) {
        tag = substr(rest, RSTART, RLENGTH)
        kind = (substr(tag, 2, 7) == "Package" ? "package" : "project")
        inc = tag
        sub(/^.*Include="/, "", inc)
        sub(/"$/, "", inc)
        printf "%s\t%s\t%s\n", kind, inc, tag
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
  ' "$file"
}

repo=""
out_file=""
generated_on=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --repo)
    [[ $# -ge 2 ]] || die "--repo needs a path" 2
    repo="$2"
    shift 2
    ;;
  --repo=*)
    repo="${1#--repo=}"
    shift
    ;;
  --out)
    [[ $# -ge 2 ]] || die "--out needs a path" 2
    out_file="$2"
    shift 2
    ;;
  --out=*)
    out_file="${1#--out=}"
    shift
    ;;
  --generated-on)
    [[ $# -ge 2 ]] || die "--generated-on needs a date" 2
    generated_on="$2"
    shift 2
    ;;
  --generated-on=*)
    generated_on="${1#--generated-on=}"
    shift
    ;;
  *)
    die "unknown argument: $1" 2
    ;;
  esac
done

if [[ -z "$repo" ]]; then
  repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$repo" ]] || repo="$(pwd)"
fi

if [[ ! -d "$repo" ]]; then
  die "not a directory: $repo" 1
fi
root="$(cd -P "$repo" 2>/dev/null && pwd)" || die "unreadable: $repo" 1

if [[ -z "$generated_on" ]]; then
  generated_on="$(git -C "$root" log -1 --format=%cs 2>/dev/null || true)"
  [[ -n "$generated_on" ]] || generated_on="unknown"
fi

subject="$(basename "$root")"

proj_list=()
while IFS= read -r abs; do
  [[ -n "$abs" ]] || continue
  proj_list+=("${abs#"$root"/}")
done < <(walk_files "$root" '*.csproj' '*.fsproj' | LC_ALL=C sort)

proj_file="$(mktemp)"
trap 'rm -f "$proj_file"' EXIT
printf '%s\n' "${proj_list[@]+"${proj_list[@]}"}" >"$proj_file"

other_list=()
while IFS= read -r abs; do
  [[ -n "$abs" ]] || continue
  rel="${abs#"$root"/}"
  case "$rel" in
  *.csproj | *.fsproj) continue ;;
  *) ;;
  esac
  other_list+=("$rel")
done < <(walk_files "$root" \
  'package.json' 'go.mod' 'pyproject.toml' 'requirements*.txt' 'setup.py' \
  'Cargo.toml' 'pom.xml' 'build.gradle' 'build.gradle.kts' \
  'Gemfile' 'composer.json' 'global.json' '*.sln' '*.slnx' | LC_ALL=C sort)

manifests=""
if [[ ${#other_list[@]} -gt 0 ]]; then
  shown=0
  for rel in "${other_list[@]}"; do
    [[ "$shown" -ge 8 ]] && break
    if [[ -n "$manifests" ]]; then
      manifests="$manifests, "
    fi
    manifests="$manifests$rel"
    shown=$((shown + 1))
  done
fi

ecosystem="dotnet"
unknown_reason=""
unshipped=""
if [[ ${#proj_list[@]} -eq 0 ]]; then
  ecosystem="unknown"
  if [[ -n "$manifests" ]]; then
    unknown_reason="found ${manifests}; the shipped adapter reads only .NET ProjectReference and PackageReference, so this ecosystem is unknown"
  else
    unknown_reason="no .NET project file and no recognized build manifest; ecosystem unknown"
  fi
elif [[ ${#other_list[@]} -gt 0 ]]; then
  shown=0
  for rel in "${other_list[@]}"; do
    case "$rel" in
    *.sln | *.slnx | global.json) continue ;;
    *) ;;
    esac
    [[ "$shown" -ge 8 ]] && break
    if [[ -n "$unshipped" ]]; then
      unshipped="$unshipped, "
    fi
    unshipped="$unshipped$rel"
    shown=$((shown + 1))
  done
fi

node_lines=""
edge_lines=""

add_node() {
  local id="$1" name="$2" path="$3" eco="$4" kind="$5" line
  json_escape "$id"
  line="{\"id\":\"$JSON_ESC\""
  json_escape "$name"
  line="$line,\"name\":\"$JSON_ESC\""
  json_escape "$path"
  line="$line,\"path\":\"$JSON_ESC\""
  json_escape "$eco"
  line="$line,\"ecosystem\":\"$JSON_ESC\""
  json_escape "$kind"
  line="$line,\"kind\":\"$JSON_ESC\"}"
  node_lines="$node_lines$line"$'\n'
}

add_edge() {
  local from="$1" to="$2" kind="$3" evidence="$4" line
  json_escape "$from"
  line="{\"from\":\"$JSON_ESC\""
  json_escape "$to"
  line="$line,\"to\":\"$JSON_ESC\""
  json_escape "$kind"
  line="$line,\"kind\":\"$JSON_ESC\""
  json_escape "$evidence"
  line="$line,\"evidence\":\"$JSON_ESC\"}"
  edge_lines="$edge_lines$line"$'\n'
}

is_project() {
  grep -Fxq -- "$1" "$proj_file"
}

if [[ "$ecosystem" == "dotnet" ]]; then
  for rel in "${proj_list[@]}"; do
    base="${rel##*/}"
    name="${base%.*}"
    add_node "$rel" "$name" "$rel" "dotnet" "project"
  done

  for rel in "${proj_list[@]}"; do
    from_dir="${rel%/*}"
    [[ "$from_dir" == "$rel" ]] && from_dir=""
    while IFS=$'\t' read -r kind include decl; do
      [[ -n "${kind:-}" ]] || continue
      evidence="$rel: $decl"
      if [[ "$kind" == "package" ]]; then
        [[ -n "$include" ]] || continue
        add_node "nuget:$include" "$include" "" "nuget" "package"
        add_edge "$rel" "nuget:$include" "package" "$evidence"
        continue
      fi
      inc="${include//\\//}"
      case "$inc" in
      '' | /* | [A-Za-z]:* | *'*'* | *'?'* | *'['*)
        add_edge "$rel" "$include" "unresolved" "$evidence"
        continue
        ;;
      *) ;;
      esac
      if [[ -n "$from_dir" ]]; then
        raw="$from_dir/$inc"
      else
        raw="$inc"
      fi
      if ! norm="$(normalize_inside "$raw")"; then
        add_edge "$rel" "$include" "unresolved" "$evidence"
        continue
      fi
      if is_project "$norm" && [[ -f "$root/$norm" ]]; then
        add_edge "$rel" "$norm" "project" "$evidence"
      else
        add_edge "$rel" "$include" "unresolved" "$evidence"
      fi
    done < <(item_records "$root/$rel")
  done
fi

if [[ -n "$node_lines" ]]; then
  node_lines="$(printf '%s\n' "$node_lines" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u)"
fi
if [[ -n "$edge_lines" ]]; then
  edge_lines="$(printf '%s\n' "$edge_lines" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u)"
fi

emit_array() {
  local key="$1" body="$2" comma="$3"
  if [[ -z "$body" ]]; then
    printf '  "%s": []%s\n' "$key" "$comma"
    return
  fi
  printf '  "%s": [\n' "$key"
  printf '%s\n' "$body" | awk '
    NF { lines[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) printf "    %s%s\n", lines[i], (i < n ? "," : "")
    }
  '
  printf '  ]%s\n' "$comma"
}

record_body="$(
  json_escape "$generated_on"
  printf '{\n  "schema_version": 1,\n  "generated_on": "%s",\n' "$JSON_ESC"
  json_escape "$subject"
  printf '  "subject": "%s",\n' "$JSON_ESC"
  json_escape "$ecosystem"
  printf '  "ecosystem": "%s",\n' "$JSON_ESC"
  json_escape "$unknown_reason"
  printf '  "unknown_reason": "%s",\n' "$JSON_ESC"
  json_escape "$unshipped"
  printf '  "unshipped": "%s",\n' "$JSON_ESC"
  printf '  "node_threshold": %s,\n' "$NODE_THRESHOLD"
  emit_array nodes "$node_lines" ","
  emit_array edges "$edge_lines" ""
  printf '}\n'
)"

if [[ -n "$out_file" ]]; then
  printf '%s\n' "$record_body" >"$out_file"
else
  printf '%s\n' "$record_body"
fi

exit 0
