#!/usr/bin/env bash
# Cite a repository's build-declaration dependency graph, as JSON.
#
# WHY. A diagram of which project depends on which is model recall unless every
# edge is a declaration a script read. This collector reads declarations only.
# It does not read source imports, and it does not guess a missing project by
# file name.
#
# ProjectReference is a reference to another project. Basis:
# https://learn.microsoft.com/en-us/visualstudio/msbuild/common-msbuild-project-items
# PackageReference Include is the package id. Basis:
# https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files
# Verified 2026-09-28. Recheck when either page renames the item or stops using
# Include as that string.
#
# The human render is not a C4 diagram. C4's diagrams are system context,
# containers, components, and code, plus system landscape, dynamic, and
# deployment. Basis: https://c4model.com/ Verified 2026-09-28. Recheck when
# that page adds a diagram type for a build-declaration graph.
#
# Usage:
#   dependency-graph.sh [--out <file>] [--generated-on <date>] <repo-path>
#   dependency-graph.sh --help
#
# Output: one JSON document on stdout, or in --out <file> with nothing on
# stdout; a failed write exits 1 with a message. generated_on defaults to the
# date of the repository's HEAD commit (git log -1 --format=%cs), so a second
# run on the same commit is byte-identical, and to "unknown" when there is no
# commit. --generated-on overrides it. The document is in the
# one-object-per-line layout. Readers match objects by line, the same way landscape.json does. A reader
# given any other layout must fail rather than report an empty graph.
# render-dependencies.sh is that reader.
#
#   {
#     "schema_version": 1,
#     "generated_on": "YYYY-MM-DD" | "unknown",
#     "result": "ok" | "unknown",
#     "message": "...",
#     "ecosystem": "dotnet" | "unknown",
#     "node_threshold": 40,
#     "cycles_truncated": false,
#     "nodes": [ <one node object per line> ],
#     "edges": [ <one edge object per line> ],
#     "cycles": [ <one cycle object per line> ],
#     "findings": [ <one finding object per line> ]
#   }
#
#   node     {"id","name","path","ecosystem","kind"}
#            kind is "project" or "package". id of a project is its
#            repo-relative path. id of a package is "pkg:" plus the Include.
#   edge     {"from","to","kind","status","evidence"}
#            kind is "project" or "package". status is "resolved" or
#            "unresolved". evidence is the repo-relative file, a colon, and
#            the matched declaration text.
#   cycle    {"id"}  project ids joined by " -> ", rotated to start at the
#            smallest id, first id repeated at the end.
#   finding  {"kind","path","evidence"}
#            kind "unresolved-membership" is a solution project whose declared
#            path is missing or outside the repository root.
#
# result "unknown" means this run did not read a shipped adapter. The arrays
# are empty and message says why. That is not an empty graph: an empty graph
# is result "ok" with project nodes and no edges.
#
# The first shipped adapter is .NET. ProjectReference is a directed internal
# edge whose target is the Include path relative to the project file.
# PackageReference is an external package edge. A ProjectReference that is
# missing or escapes the repository root is status "unresolved" and is never
# matched to a similarly named project elsewhere. Solution files
# (*.sln, *.slnx) contribute membership, not dependency edges.
#
# node_threshold is the documented count of internal project nodes above which
# the human diagram aggregates to directories. This file stays at project
# resolution either way. The diagram is render-dependencies.sh.
#
# Build output directories named bin and obj are not walked. Dot-directories
# other than .github, .gitlab, .circleci, and .devcontainer are not walked.
# node_modules and vendor are not walked.
#
# Nothing here fetches. The only write is --out.
#
# Portability: bash plus POSIX awk. No jq, no `grep -P`, no python.
#
# Exit: 0 = a document was emitted (result ok or unknown); 1 = the path is
# not a readable directory or --out cannot be written; 2 = usage.
set -uo pipefail

NODE_THRESHOLD=40
CYCLE_STEP_CAP=200000
CYCLE_LIST_CAP=50

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/dotnet-references.sh
source "$SCRIPT_DIR/../../../lib/dotnet-references.sh"

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'dependency-graph.sh: %s\n' "$1" >&2
  exit "$2"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

raw_path=""
out_file=""
generated_on=""
while [[ $# -gt 0 ]]; do
  case "$1" in
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
  -*)
    die "unknown argument: $1" 2
    ;;
  *)
    if [[ -n "$raw_path" ]]; then
      usage >&2
      exit 2
    fi
    raw_path="$1"
    shift
    ;;
  esac
done
if [[ -z "$raw_path" ]]; then
  usage >&2
  exit 2
fi

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

# Print the repo-relative path of base/raw with . and .. resolved, or return 1
# when the path is absolute or escapes the repository root. The target does
# not have to exist. Nothing outside the root is looked up.
normalize_within_root() {
  local base="$1" raw="$2" rel combined part
  local -a stack=()
  rel="${raw//\\//}"
  case "$rel" in
  [A-Za-z]:* | //* | /*) return 1 ;;
  *) ;;
  esac
  if [[ -z "$base" || "$base" == "." ]]; then
    combined="$rel"
  else
    combined="$base/$rel"
  fi
  local IFS=/
  # IFS is slash so the unquoted expansion splits path segments and keeps spaces.
  # shellcheck disable=SC2086
  for part in $combined; do
    case "$part" in
    '' | '.') ;;
    '..')
      [[ ${#stack[@]} -gt 0 ]] || return 1
      stack=("${stack[@]:0:${#stack[@]}-1}")
      ;;
    *) stack+=("$part") ;;
    esac
  done
  local out="" p
  for p in "${stack[@]+"${stack[@]}"}"; do
    [[ -n "$out" ]] && out="$out/"
    out="$out$p"
  done
  printf '%s\n' "$out"
}

proj_name() {
  local base="${1##*/}"
  printf '%s\n' "${base%.*}"
}

proj_dir_of() {
  case "$1" in
  */*) printf '%s\n' "${1%/*}" ;;
  *) printf '\n' ;;
  esac
}

is_proj_suffix() {
  local ext="${1##*.}"
  ext="${ext,,}"
  [[ "$ext" == "csproj" || "$ext" == "fsproj" ]]
}

# Solution project paths. One line per declared path: path<TAB>citation.
sln_declared_projects() {
  local file="$1" ext
  ext="${file##*.}"
  ext="${ext,,}"
  if [[ "$ext" == "slnx" ]]; then
    awk '
      {
        line = $0
        sub(/\r$/, "", line)
        rest = line
        while (match(rest, /<Project[^>]*Path="[^"]*"/)) {
          decl = substr(rest, RSTART, RLENGTH)
          path = decl
          sub(/^.*Path="/, "", path)
          sub(/"$/, "", path)
          printf "%s\t%s\n", path, decl
          rest = substr(rest, RSTART + RLENGTH)
        }
      }
    ' "$file"
    return 0
  fi
  awk '
    /^Project\(/ {
      if (match($0, /= "[^"]*", "[^"]*"/)) {
        seg = substr($0, RSTART, RLENGTH)
        sub(/^= "[^"]*", "/, "", seg)
        sub(/"$/, "", seg)
        line = $0
        sub(/\r$/, "", line)
        printf "%s\t%s\n", seg, line
      }
    }
  ' "$file"
}

declare -A NODE_AT=()
node_ids=()
node_names=()
node_paths=()
node_kinds=()

add_node() {
  local id="$1" name="$2" path="$3" kind="$4"
  [[ -n "${NODE_AT[$id]+x}" ]] && return 0
  NODE_AT[$id]="${#node_ids[@]}"
  node_ids+=("$id")
  node_names+=("$name")
  node_paths+=("$path")
  node_kinds+=("$kind")
}

declare -A EDGE_SEEN=()
edge_from=()
edge_to=()
edge_kind=()
edge_status=()
edge_evidence=()

add_edge() {
  local from="$1" to="$2" kind="$3" status="$4" evidence="$5"
  local key
  key="${from}"$'\x1f'"${to}"$'\x1f'"${kind}"$'\x1f'"${status}"
  [[ -n "${EDGE_SEEN[$key]+x}" ]] && return 0
  EDGE_SEEN[$key]=1
  edge_from+=("$from")
  edge_to+=("$to")
  edge_kind+=("$kind")
  edge_status+=("$status")
  edge_evidence+=("$evidence")
}

declare -A FINDING_SEEN=()
finding_kind=()
finding_path=()
finding_evidence=()

add_finding() {
  local kind="$1" path="$2" evidence="$3" key
  key="${kind}"$'\x1f'"${path}"
  [[ -n "${FINDING_SEEN[$key]+x}" ]] && return 0
  FINDING_SEEN[$key]=1
  finding_kind+=("$kind")
  finding_path+=("$path")
  finding_evidence+=("$evidence")
}

json_node() {
  local id="$1" name="$2" path="$3" kind="$4"
  local e_id e_name e_path e_kind
  json_escape "$id"
  e_id="$JSON_ESC"
  json_escape "$name"
  e_name="$JSON_ESC"
  json_escape "$path"
  e_path="$JSON_ESC"
  json_escape "$kind"
  e_kind="$JSON_ESC"
  printf '{"id":"%s","name":"%s","path":"%s","ecosystem":"dotnet","kind":"%s"}' \
    "$e_id" "$e_name" "$e_path" "$e_kind"
}

json_edge() {
  local from="$1" to="$2" kind="$3" status="$4" evidence="$5"
  local e_from e_to e_kind e_status e_evidence
  json_escape "$from"
  e_from="$JSON_ESC"
  json_escape "$to"
  e_to="$JSON_ESC"
  json_escape "$kind"
  e_kind="$JSON_ESC"
  json_escape "$status"
  e_status="$JSON_ESC"
  json_escape "$evidence"
  e_evidence="$JSON_ESC"
  printf '{"from":"%s","to":"%s","kind":"%s","status":"%s","evidence":"%s"}' \
    "$e_from" "$e_to" "$e_kind" "$e_status" "$e_evidence"
}

json_cycle() {
  local id="$1" e_id
  json_escape "$id"
  e_id="$JSON_ESC"
  printf '{"id":"%s"}' "$e_id"
}

json_finding() {
  local kind="$1" path="$2" evidence="$3"
  local e_kind e_path e_evidence
  json_escape "$kind"
  e_kind="$JSON_ESC"
  json_escape "$path"
  e_path="$JSON_ESC"
  json_escape "$evidence"
  e_evidence="$JSON_ESC"
  printf '{"kind":"%s","path":"%s","evidence":"%s"}' "$e_kind" "$e_path" "$e_evidence"
}

emit_array() {
  local key="$1" trailing="$2"
  shift 2
  local -a items=("$@")
  local comma="" i item_comma
  [[ "$trailing" == "comma" ]] && comma=","
  if [[ ${#items[@]} -eq 0 ]]; then
    printf '  "%s": []%s\n' "$key" "$comma"
    return 0
  fi
  printf '  "%s": [\n' "$key"
  for i in "${!items[@]}"; do
    item_comma=","
    [[ "$i" -eq $((${#items[@]} - 1)) ]] && item_comma=""
    printf '    %s%s\n' "${items[$i]}" "$item_comma"
  done
  printf '  ]%s\n' "$comma"
}

sort_lines() {
  local -a incoming=("$@")
  local -a sorted=()
  local line
  if [[ ${#incoming[@]} -eq 0 ]]; then
    return 0
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    sorted+=("$line")
  done < <(printf '%s\n' "${incoming[@]}" | LC_ALL=C sort)
  printf '%s\n' "${sorted[@]}"
}

root="$(cd "$raw_path" 2>/dev/null && pwd)" || die "not a readable directory: $raw_path" 1
[[ -d "$root" ]] || die "not a readable directory: $raw_path" 1

files=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  files+=("$line")
done < <(
  find "$root" -mindepth 1 \
    \( \( -name '.?*' \
    ! -name '.github' ! -name '.gitlab' ! -name '.circleci' \
    ! -name '.devcontainer' \) \
    -o -name node_modules -o -name vendor -o -name bin -o -name obj \) -prune -o \
    -type f \( \
    -name '*.csproj' -o -name '*.fsproj' -o -name '*.sln' -o -name '*.slnx' \
    -o -name 'global.json' \
    -o -name 'package.json' \
    -o -name 'pyproject.toml' -o -name 'requirements*.txt' -o -name 'setup.py' \
    -o -name 'go.mod' -o -name 'Cargo.toml' \
    -o -name 'pom.xml' -o -name 'build.gradle*' \
    -o -name 'Gemfile' -o -name 'composer.json' \
    \) -print 2>/dev/null |
    ROOT="$root/" awk 'index($0, ENVIRON["ROOT"]) == 1 { $0 = substr($0, length(ENVIRON["ROOT"]) + 1) } { print }' |
    LC_ALL=C sort
)

proj_files=()
sln_files=()
has_global_json=0
declare -A OTHER=()

for rel in "${files[@]+"${files[@]}"}"; do
  base="${rel##*/}"
  case "$base" in
  *.csproj | *.fsproj) proj_files+=("$rel") ;;
  *.sln | *.slnx) sln_files+=("$rel") ;;
  global.json) has_global_json=1 ;;
  package.json) OTHER[node]="$rel" ;;
  pyproject.toml | requirements*.txt | setup.py) OTHER[python]="$rel" ;;
  go.mod) OTHER[go]="$rel" ;;
  Cargo.toml) OTHER[rust]="$rel" ;;
  pom.xml | build.gradle*) OTHER[jvm]="$rel" ;;
  Gemfile) OTHER[ruby]="$rel" ;;
  composer.json) OTHER[php]="$rel" ;;
  *) ;;
  esac
done

other_msg=""
if [[ ${#OTHER[@]} -gt 0 ]]; then
  while IFS= read -r eco; do
    [[ -n "$eco" ]] || continue
    [[ -n "$other_msg" ]] && other_msg="$other_msg, "
    other_msg="$other_msg$eco (${OTHER[$eco]})"
  done < <(printf '%s\n' "${!OTHER[@]}" | LC_ALL=C sort)
fi

result="ok"
ecosystem="dotnet"
message=""
if [[ ${#proj_files[@]} -eq 0 ]]; then
  result="unknown"
  ecosystem="unknown"
  if [[ -n "$other_msg" ]]; then
    message="Found build manifests for $other_msg and no .NET project file (*.csproj, *.fsproj). That adapter is not shipped, so this run did not invent an empty graph."
  elif [[ "$has_global_json" -eq 1 ]]; then
    message="Found global.json and no .NET project file (*.csproj, *.fsproj). global.json names an SDK and declares no project graph, so this run did not invent an empty graph."
  else
    message="No recognized build manifest. This run did not invent an empty graph."
  fi
else
  if [[ -n "$other_msg" ]]; then
    message="Not read: $other_msg. The first adapter is .NET; an unread ecosystem is left unread rather than drawn as an empty graph."
  fi

  for proj_rel in "${proj_files[@]}"; do
    add_node "$proj_rel" "$(proj_name "$proj_rel")" "$proj_rel" "project"
    proj_dir="$(proj_dir_of "$proj_rel")"
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      rec_kind="${rec%%$'\t'*}"
      rec_rest="${rec#*$'\t'}"
      rec_inc="${rec_rest%%$'\t'*}"
      rec_decl="${rec_rest#*$'\t'}"
      [[ -n "$rec_inc" ]] || continue
      case "$rec_kind" in
      package)
        add_node "pkg:$rec_inc" "$rec_inc" "" "package"
        add_edge "$proj_rel" "pkg:$rec_inc" "package" "resolved" "$proj_rel: $rec_decl"
        ;;
      project)
        normalized=""
        if normalized="$(normalize_within_root "$proj_dir" "$rec_inc")" &&
          [[ -n "$normalized" && -f "$root/$normalized" ]]; then
          add_node "$normalized" "$(proj_name "$normalized")" "$normalized" "project"
          add_edge "$proj_rel" "$normalized" "project" "resolved" "$proj_rel: $rec_decl"
        else
          add_edge "$proj_rel" "$rec_inc" "project" "unresolved" "$proj_rel: $rec_decl"
        fi
        ;;
      *) ;;
      esac
    done < <(dotnet_reference_records "$root/$proj_rel")
  done

  for sln_rel in "${sln_files[@]+"${sln_files[@]}"}"; do
    sln_dir="$(proj_dir_of "$sln_rel")"
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      declared="${rec%%$'\t'*}"
      citation="${rec#*$'\t'}"
      is_proj_suffix "$declared" || continue
      normalized=""
      if normalized="$(normalize_within_root "$sln_dir" "$declared")" &&
        [[ -n "$normalized" && -f "$root/$normalized" ]]; then
        add_node "$normalized" "$(proj_name "$normalized")" "$normalized" "project"
      else
        add_finding "unresolved-membership" "$declared" "$sln_rel: $citation"
      fi
    done < <(sln_declared_projects "$root/$sln_rel")
  done
fi

cycle_lines=()
cycles_truncated_json="false"
if [[ ${#edge_from[@]} -gt 0 ]]; then
  cycle_feed=""
  for i in "${!edge_from[@]}"; do
    if [[ "${edge_kind[$i]}" == "project" && "${edge_status[$i]}" == "resolved" ]]; then
      cycle_feed+="${edge_from[$i]}"$'\t'"${edge_to[$i]}"$'\n'
    fi
  done
  if [[ -n "$cycle_feed" ]]; then
    cycle_raw="$(printf '%s' "$cycle_feed" | awk -v step_cap="$CYCLE_STEP_CAP" -v list_cap="$CYCLE_LIST_CAP" '
      function dfs(u,    rest, v, nl, k, from, min, minpos, rotated) {
        if (truncated) return
        if (steps > step_cap) { truncated = 1; return }
        steps++
        on[u] = 1
        stack[++sp] = u
        rest = adj[u]
        while (rest != "") {
          nl = index(rest, "\n")
          if (nl == 0) { v = rest; rest = "" }
          else { v = substr(rest, 1, nl - 1); rest = substr(rest, nl + 1) }
          if (v == "") continue
          if (on[v]) {
            from = 0
            for (k = 1; k <= sp; k++) if (stack[k] == v) from = k
            if (from == 0) continue
            min = ""
            minpos = from
            for (k = from; k <= sp; k++) if (min == "" || stack[k] < min) { min = stack[k]; minpos = k }
            rotated = ""
            for (k = minpos; k <= sp; k++) rotated = rotated (rotated == "" ? "" : " -> ") stack[k]
            for (k = from; k < minpos; k++) rotated = rotated " -> " stack[k]
            rotated = rotated " -> " min
            if (!(rotated in seen_cycle)) {
              if (cycn >= list_cap) { truncated = 1; break }
              seen_cycle[rotated] = 1
              cycn++
              found[cycn] = rotated
            }
          } else {
            dfs(v)
            if (truncated) break
          }
        }
        on[u] = 0
        sp--
      }
      BEGIN { FS = "\t"; steps = 0; truncated = 0; cycn = 0; sp = 0; nn = 0 }
      {
        if ($1 == "" || $2 == "") next
        key = $1 "\t" $2
        if (key in seen_edge) next
        seen_edge[key] = 1
        if (!($1 in started)) { started[$1] = 1; nodes[++nn] = $1 }
        if (!($2 in started)) { started[$2] = 1; nodes[++nn] = $2 }
        adj[$1] = adj[$1] $2 "\n"
      }
      END {
        for (i = 1; i <= nn; i++) if (!truncated) dfs(nodes[i])
        if (truncated) print "TRUNCATED"
        for (i = 1; i <= cycn; i++) print found[i]
      }
    ')"
    if [[ "$cycle_raw" == TRUNCATED* ]]; then
      cycles_truncated_json="true"
      cycle_raw="${cycle_raw#TRUNCATED}"
      cycle_raw="${cycle_raw#$'\n'}"
    fi
    if [[ -n "$cycle_raw" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        cycle_lines+=("$line")
      done <<<"$cycle_raw"
    fi
  fi
fi

node_json=()
for i in "${!node_ids[@]}"; do
  node_json+=("$(json_node "${node_ids[$i]}" "${node_names[$i]}" "${node_paths[$i]}" "${node_kinds[$i]}")")
done
edge_json=()
for i in "${!edge_from[@]}"; do
  edge_json+=("$(json_edge "${edge_from[$i]}" "${edge_to[$i]}" "${edge_kind[$i]}" "${edge_status[$i]}" "${edge_evidence[$i]}")")
done
cycle_json=()
for cyc in "${cycle_lines[@]+"${cycle_lines[@]}"}"; do
  cycle_json+=("$(json_cycle "$cyc")")
done
finding_json=()
for i in "${!finding_kind[@]}"; do
  finding_json+=("$(json_finding "${finding_kind[$i]}" "${finding_path[$i]}" "${finding_evidence[$i]}")")
done

sorted_nodes=()
sorted_edges=()
sorted_cycles=()
sorted_findings=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  sorted_nodes+=("$line")
done < <(sort_lines "${node_json[@]+"${node_json[@]}"}")
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  sorted_edges+=("$line")
done < <(sort_lines "${edge_json[@]+"${edge_json[@]}"}")
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  sorted_cycles+=("$line")
done < <(sort_lines "${cycle_json[@]+"${cycle_json[@]}"}")
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  sorted_findings+=("$line")
done < <(sort_lines "${finding_json[@]+"${finding_json[@]}"}")

[[ -n "$generated_on" ]] || generated_on="$(git -C "$root" log -1 --format=%cs 2>/dev/null || true)"
[[ -n "$generated_on" ]] || generated_on="unknown"
json_escape "$generated_on"
e_generated_on="$JSON_ESC"
json_escape "$message"
e_message="$JSON_ESC"
json_escape "$ecosystem"
e_ecosystem="$JSON_ESC"

emit_document() {
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "generated_on": "%s",\n' "$e_generated_on"
  printf '  "result": "%s",\n' "$result"
  printf '  "message": "%s",\n' "$e_message"
  printf '  "ecosystem": "%s",\n' "$e_ecosystem"
  printf '  "node_threshold": %s,\n' "$NODE_THRESHOLD"
  printf '  "cycles_truncated": %s,\n' "$cycles_truncated_json"
  emit_array "nodes" comma "${sorted_nodes[@]+"${sorted_nodes[@]}"}"
  emit_array "edges" comma "${sorted_edges[@]+"${sorted_edges[@]}"}"
  emit_array "cycles" comma "${sorted_cycles[@]+"${sorted_cycles[@]}"}"
  emit_array "findings" none "${sorted_findings[@]+"${sorted_findings[@]}"}"
  printf '}\n'
}

if [[ -n "$out_file" ]]; then
  emit_document >"$out_file" || die "cannot write --out file: $out_file" 1
else
  emit_document
fi

exit 0
