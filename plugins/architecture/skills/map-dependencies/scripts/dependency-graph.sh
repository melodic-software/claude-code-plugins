#!/usr/bin/env bash

# shellcheck disable=SC2329 # the readers and their helpers are called as "read_$eco".
set -uo pipefail

NODE_THRESHOLD=40

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/dotnet-references.sh
source "$SCRIPT_DIR/../../../lib/dotnet-references.sh"
# shellcheck source=../../../lib/node-references.sh
source "$SCRIPT_DIR/../../../lib/node-references.sh"
# shellcheck source=../../../lib/go-references.sh
source "$SCRIPT_DIR/../../../lib/go-references.sh"
# shellcheck source=../../../lib/python-references.sh
source "$SCRIPT_DIR/../../../lib/python-references.sh"
# shellcheck source=../../../lib/rust-references.sh
source "$SCRIPT_DIR/../../../lib/rust-references.sh"
# shellcheck source=../../../lib/jvm-references.sh
source "$SCRIPT_DIR/../../../lib/jvm-references.sh"
# shellcheck source=../../../lib/json-escape.sh
source "$SCRIPT_DIR/../../../lib/json-escape.sh"

usage() {
  cat <<'EOF'
Cite a repository's build-declaration dependency graph, as JSON.

Usage: dependency-graph.sh [--out <file>] [--generated-on <date>] <repo-path>
  --out <file>           write the document to <file> instead of stdout
  --generated-on <date>  the generated_on value (default: the HEAD commit date)
  --help                 print this help

The document is in the one-object-per-line layout; node_threshold is the project-node
count above which the diagram aggregates to directories. Schema: reference/dependency-graph-record.md

Exit: 0 a document was emitted; 1 the path is not a readable directory or --out cannot be written; 2 usage
EOF
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
node_ecos=()

CUR_ECO=""

add_node() {
  local id="$1" name="$2" path="$3" kind="$4"
  [[ -n "${NODE_AT[$id]+x}" ]] && return 0
  NODE_AT[$id]="${#node_ids[@]}"
  node_ids+=("$id")
  node_names+=("$name")
  node_paths+=("$path")
  node_kinds+=("$kind")
  node_ecos+=("$CUR_ECO")
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
  [[ "$kind" == "unread-manifest" ]] && key+=$'\x1f'"$evidence"
  [[ -n "${FINDING_SEEN[$key]+x}" ]] && return 0
  FINDING_SEEN[$key]=1
  finding_kind+=("$kind")
  finding_path+=("$path")
  finding_evidence+=("$evidence")
}

add_unread_manifest() {
  add_finding "unread-manifest" "$1" "$1: $2"
}

JSON_OBJ=""
json_object() {
  local out=""
  while [[ $# -ge 2 ]]; do
    json_escape "$2"
    out+="${out:+,}\"$1\":\"$JSON_ESC\""
    shift 2
  done
  JSON_OBJ="{$out}"
}

node_namespace() {
  local ns
  ns="$(dotnet_project_property "$root/$1" RootNamespace)"
  [[ -n "$ns" ]] || ns="$(dotnet_project_property "$root/$1" AssemblyName)"
  printf '%s\n' "$ns"
}

emit_array() {
  local key="$1" after="$2" i sep=","
  shift 2
  if [[ $# -eq 0 ]]; then
    printf '  "%s": []%s\n' "$key" "$after"
    return 0
  fi
  local -a items
  mapfile -t items < <(printf '%s\n' "$@" | LC_ALL=C sort)
  printf '  "%s": [\n' "$key"
  for i in "${!items[@]}"; do
    [[ "$i" -eq $((${#items[@]} - 1)) ]] && sep=""
    printf '    %s%s\n' "${items[$i]}" "$sep"
  done
  printf '  ]%s\n' "$after"
}

root="$(cd "$raw_path" 2>/dev/null && pwd)" || die "not a readable directory: $raw_path" 1
[[ -d "$root" ]] || die "not a readable directory: $raw_path" 1

mapfile -t files < <(
  find "$root" -mindepth 1 \
    \( \( -name '.?*' \
    ! -name '.github' ! -name '.gitlab' ! -name '.circleci' \
    ! -name '.devcontainer' \) \
    -o -name node_modules -o -name vendor -o -name bin -o -name obj \) -prune -o \
    -type f \( \
    -name '*.csproj' -o -name '*.fsproj' -o -name '*.sln' -o -name '*.slnx' \
    -o -name '*.props' -o -name '*.targets' \
    -o -name 'global.json' \
    -o -name 'package.json' -o -name 'pnpm-workspace.yaml' \
    -o -name 'pyproject.toml' -o -name 'requirements*.txt' -o -name 'setup.py' \
    -o -name 'go.mod' -o -name 'go.work' -o -name 'Cargo.toml' \
    -o -name 'pom.xml' -o -name 'build.gradle*' -o -name 'settings.gradle*' \
    -o -name 'Gemfile' -o -name 'composer.json' \
    \) -print 2>/dev/null |
    ROOT="$root/" awk 'index($0, ENVIRON["ROOT"]) == 1 { $0 = substr($0, length(ENVIRON["ROOT"]) + 1) } { print }' |
    LC_ALL=C sort
)

proj_files=()
sln_files=()
msbuild_files=()
declare -A BUILD_FILE=()
has_global_json=0
node_files=()
pnpm_files=()
go_files=()
gowork_files=()
py_files=()
req_files=()
setup_files=()
cargo_files=()
pom_files=()
gradle_files=()
settings_files=()
declare -A OTHER=()

for rel in "${files[@]+"${files[@]}"}"; do
  base="${rel##*/}"
  case "$base" in
  *.csproj | *.fsproj) proj_files+=("$rel") ;;
  *.sln | *.slnx) sln_files+=("$rel") ;;
  Directory.Build.props | Directory.Build.targets)
    msbuild_files+=("$rel")
    BUILD_FILE[$rel]=1
    ;;
  *.props | *.targets) msbuild_files+=("$rel") ;;
  global.json) has_global_json=1 ;;
  package.json) node_files+=("$rel") ;;
  pnpm-workspace.yaml) pnpm_files+=("$rel") ;;
  pyproject.toml) py_files+=("$rel") ;;
  requirements*.txt) req_files+=("$rel") ;;
  setup.py) setup_files+=("$rel") ;;
  go.mod) go_files+=("$rel") ;;
  go.work) gowork_files+=("$rel") ;;
  Cargo.toml) cargo_files+=("$rel") ;;
  pom.xml) pom_files+=("$rel") ;;
  build.gradle | build.gradle.kts) gradle_files+=("$rel") ;;
  settings.gradle | settings.gradle.kts) settings_files+=("$rel") ;;
  Gemfile) OTHER[ruby]="$rel" ;;
  composer.json) OTHER[php]="$rel" ;;
  *) ;;
  esac
done

READERS=(dotnet node go python rust jvm)
readers_list="${READERS[*]}"
readers_list="${readers_list// /, }"

for eco in "${READERS[@]}"; do
  unset "OTHER[$eco]"
done

other_msg=""
if [[ ${#OTHER[@]} -gt 0 ]]; then
  while IFS= read -r eco; do
    [[ -n "$eco" ]] || continue
    [[ -n "$other_msg" ]] && other_msg="$other_msg, "
    other_msg="$other_msg$eco (${OTHER[$eco]})"
  done < <(printf '%s\n' "${!OTHER[@]}" | LC_ALL=C sort)
fi

record_value() {
  awk -F '\t' -v key="$1" '$1 == key { print $2; exit }'
}

add_project_node() {
  local label
  label="$(proj_dir_of "$1")"
  label="${label:-$root}"
  add_node "$1" "${2:-${label##*/}}" "$1" "project"
}

add_member_edges() {
  local rel="$1" records="$2" dot="$3" wdir kind glob decl re cand cdir under ex hit m
  local -a excl=() mems=()
  shift 3
  wdir="$(proj_dir_of "$rel")"
  while IFS=$'\t' read -r kind glob decl; do
    case "$kind" in
    exclude)
      if re="$(node_glob_regex "$glob")"; then excl+=("$re"); else add_unread_manifest "$rel" "$decl"; fi
      ;;
    member) mems+=("$glob"$'\x1f'"$decl") ;;
    *) ;;
    esac
  done <<<"$records"
  for m in "${mems[@]+"${mems[@]}"}"; do
    glob="${m%%$'\x1f'*}"
    decl="${m#*$'\x1f'}"
    [[ "$dot" == skip-dot && ("$glob" == . || "$glob" == ./) ]] && continue
    if ! re="$(node_glob_regex "$glob")"; then
      add_unread_manifest "$rel" "$decl"
      continue
    fi
    hit=0
    for cand in "$@"; do
      cdir="$(proj_dir_of "$cand")"
      [[ -n "$cdir" && "$cand" != "$rel" ]] || continue
      if [[ -z "$wdir" ]]; then
        under="$cdir"
      else
        [[ "$cdir" == "$wdir"/* ]] || continue
        under="${cdir#"$wdir"/}"
      fi
      [[ "$under" =~ $re ]] || continue
      hit=1
      for ex in "${excl[@]+"${excl[@]}"}"; do [[ "$under" =~ $ex ]] && continue 2; done
      add_edge "$rel" "$cand" "project" "resolved" "$rel: $decl"
    done
    if [[ $hit -eq 0 && "$glob" != *[*?]* ]]; then
      add_edge "$rel" "$glob" "project" "unresolved" "$rel: $decl"
    fi
  done
}

declare -A FILE_RECORDS=()
declare -A FILE_CONSUMED=()

has_dotnet() { [[ ${#proj_files[@]} -gt 0 ]]; }

read_dotnet() {
  load_records() {
    [[ -n "${FILE_RECORDS[$1]+x}" ]] || FILE_RECORDS[$1]="$(dotnet_reference_records "$root/$1")"
  }

  nearest_build_file() {
    local dir="$1" name="$2" cand
    while :; do
      cand="${dir:+$dir/}$name"
      if [[ -n "${BUILD_FILE[$cand]+x}" ]]; then
        printf '%s\n' "$cand"
        return 0
      fi
      [[ -n "$dir" ]] || return 1
      case "$dir" in
      */*) dir="${dir%/*}" ;;
      *) dir="" ;;
      esac
    done
  }

  add_reference_edges() {
    local proj_rel="$1" records="$2" source_rel="$3" via="$4"
    local proj_dir rec rec_kind rec_rest rec_inc rec_decl normalized
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
        add_edge "$proj_rel" "pkg:$rec_inc" "package" "resolved" "$source_rel: $rec_decl"
        ;;
      project)
        normalized=""
        if normalized="$(normalize_within_root "$proj_dir" "$rec_inc")" &&
          [[ -n "$normalized" && -f "$root/$normalized" ]]; then
          [[ "$via" == "props" && "$normalized" == "$proj_rel" ]] && continue
          add_node "$normalized" "$(proj_name "$normalized")" "$normalized" "project"
          add_edge "$proj_rel" "$normalized" "project" "resolved" "$source_rel: $rec_decl"
        else
          add_edge "$proj_rel" "$rec_inc" "project" "unresolved" "$source_rel: $rec_decl"
        fi
        ;;
      *) ;;
      esac
    done <<<"$records"
  }

  for proj_rel in "${proj_files[@]}"; do
    add_node "$proj_rel" "$(proj_name "$proj_rel")" "$proj_rel" "project"
    load_records "$proj_rel"
    add_reference_edges "$proj_rel" "${FILE_RECORDS[$proj_rel]}" "$proj_rel" "self"
    proj_dir="$(proj_dir_of "$proj_rel")"
    for build_name in Directory.Build.props Directory.Build.targets; do
      if build_rel="$(nearest_build_file "$proj_dir" "$build_name")"; then
        load_records "$build_rel"
        FILE_CONSUMED[$build_rel]=1
        add_reference_edges "$proj_rel" "${FILE_RECORDS[$build_rel]}" "$build_rel" "props"
      fi
    done
  done

  for unread_rel in "${proj_files[@]}" "${msbuild_files[@]+"${msbuild_files[@]}"}"; do
    unread_n="$(dotnet_reference_unmatched_count "$root/$unread_rel")"
    if ! is_proj_suffix "$unread_rel" && [[ -z "${FILE_CONSUMED[$unread_rel]+x}" ]]; then
      load_records "$unread_rel"
      [[ -n "${FILE_RECORDS[$unread_rel]}" ]] &&
        unread_n=$((unread_n + $(printf '%s\n' "${FILE_RECORDS[$unread_rel]}" | grep -c .)))
    fi
    [[ "$unread_n" -gt 0 ]] && add_finding "unread-reference-tags" "$unread_rel" "$unread_rel: $unread_n reference tag(s) not read"
  done

  for sln_rel in "${sln_files[@]+"${sln_files[@]}"}"; do
    sln_dir="$(proj_dir_of "$sln_rel")"
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      declared="${rec%%$'\t'*}"
      citation="${rec#*$'\t'}"
      if ! is_proj_suffix "$declared"; then
        case "${declared,,}" in *.*proj) add_unread_manifest "$sln_rel" "$citation" ;; *) ;; esac
        continue
      fi
      normalized=""
      if normalized="$(normalize_within_root "$sln_dir" "$declared")" &&
        [[ -n "$normalized" && -f "$root/$normalized" ]]; then
        add_node "$normalized" "$(proj_name "$normalized")" "$normalized" "project"
      else
        add_finding "unresolved-membership" "$declared" "$sln_rel: $citation"
      fi
    done < <(sln_declared_projects "$root/$sln_rel")
  done
}

has_node() { [[ ${#node_files[@]} -gt 0 ]]; }

read_node() {
  local -A pkg_recs=() pkg_name=() ws_decls=() member_at=() roots_of=()
  local rel name rec decl
  local us=$'\x1f'

  for rel in "${node_files[@]}"; do
    pkg_recs[$rel]="$(node_manifest_records "$root/$rel")"
    pkg_name[$rel]="$(printf '%s\n' "${pkg_recs[$rel]}" | record_value name)"
    add_project_node "$rel" "${pkg_name[$rel]}"
  done

  read_ws_records() {
    local src="$1" records="$2" base
    base="$(proj_dir_of "$src")"
    while IFS= read -r rec; do
      case "$rec" in
      workspace$'\t'*) ws_decls[${base:-.}]+="$src"$'\t'"${rec#*$'\t'}"$'\n' ;;
      unread$'\t'*) add_unread_manifest "$src" "${rec#*$'\t'}" ;;
      *) ;;
      esac
    done <<<"$records"
  }
  for rel in "${node_files[@]}"; do
    read_ws_records "$rel" "${pkg_recs[$rel]}"
  done
  for rel in "${pnpm_files[@]+"${pnpm_files[@]}"}"; do
    read_ws_records "$rel" "$(node_pnpm_workspace_records "$root/$rel")"
  done

  local ws_dir ws_rel line src glob re cand cdir under mkey
  if [[ ${#ws_decls[@]} -gt 0 ]]; then
    while IFS= read -r ws_dir; do
      ws_rel="$ws_dir"
      [[ "$ws_dir" == "." ]] && ws_rel=""
      cand="${ws_rel:+$ws_rel/}package.json"
      [[ -n "${pkg_recs[$cand]+x}" ]] && roots_of[$cand]+="$us$ws_dir$us"
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        src="${line%%$'\t'*}"
        line="${line#*$'\t'}"
        glob="${line%%$'\t'*}"
        decl="${line#*$'\t'}"
        if ! re="$(node_glob_regex "$glob")"; then
          add_unread_manifest "$src" "$decl"
          continue
        fi
        for cand in "${node_files[@]}"; do
          cdir="$(proj_dir_of "$cand")"
          [[ -n "$cdir" && "$cdir" != "$ws_rel" ]] || continue
          if [[ -z "$ws_rel" ]]; then
            under="$cdir"
          else
            [[ "$cdir" == "$ws_rel"/* ]] || continue
            under="${cdir#"$ws_rel"/}"
          fi
          [[ "$under" =~ $re ]] || continue
          [[ "${roots_of[$cand]-}" == *"$us$ws_dir$us"* ]] || roots_of[$cand]+="$us$ws_dir$us"
          mkey="$ws_dir$us${pkg_name[$cand]}"
          [[ -n "${pkg_name[$cand]}" && -z "${member_at[$mkey]+x}" ]] && member_at[$mkey]="$cand"
        done
      done <<<"${ws_decls[$ws_dir]}"
    done < <(printf '%s\n' "${!ws_decls[@]}" | LC_ALL=C sort)
  fi

  member_named() {
    local d
    local -a roots
    IFS="$us" read -r -a roots <<<"${roots_of[$1]-}"
    for d in "${roots[@]+"${roots[@]}"}"; do
      [[ -n "$d" && -n "${member_at[$d$us$2]+x}" && "${member_at[$d$us$2]}" != "$1" ]] || continue
      printf '%s\n' "${member_at[$d$us$2]}"
      return 0
    done
    return 1
  }

  add_path_edge() {
    local from="$1" spec="$2" path="$3" evidence="$4" normalized target
    if normalized="$(normalize_within_root "$(proj_dir_of "$from")" "$path")"; then
      target="${normalized:+$normalized/}package.json"
      if [[ -n "${pkg_recs[$target]+x}" && "$target" != "$from" ]]; then
        add_edge "$from" "$target" "project" "resolved" "$evidence"
        return 0
      fi
    fi
    add_edge "$from" "$spec" "project" "unresolved" "$evidence"
  }

  local spec want target
  for rel in "${node_files[@]}"; do
    while IFS= read -r rec; do
      [[ "$rec" == dep$'\t'* ]] || continue
      rec="${rec#*$'\t'}"
      rec="${rec#*$'\t'}"
      name="${rec%%$'\t'*}"
      rec="${rec#*$'\t'}"
      spec="${rec%%$'\t'*}"
      decl="${rec#*$'\t'}"
      case "$spec" in
      catalog:*)
        add_unread_manifest "$rel" "$decl"
        ;;
      file:* | link:*)
        add_path_edge "$rel" "$spec" "${spec#*:}" "$rel: $decl"
        ;;
      workspace:.* | workspace:/*)
        add_path_edge "$rel" "$spec" "${spec#workspace:}" "$rel: $decl"
        ;;
      workspace:*)
        want="$name"
        [[ "${spec#workspace:}" == ?*@* ]] && want="${spec#workspace:}" && want="${want%@*}"
        if target="$(member_named "$rel" "$want")"; then
          add_edge "$rel" "$target" "project" "resolved" "$rel: $decl"
        else
          add_edge "$rel" "$want" "project" "unresolved" "$rel: $decl"
        fi
        ;;
      *)
        if target="$(member_named "$rel" "$name")"; then
          add_edge "$rel" "$target" "project" "resolved" "$rel: $decl"
        else
          add_node "pkg:node:$name" "$name" "" "package"
          add_edge "$rel" "pkg:node:$name" "package" "resolved" "$rel: $decl"
        fi
        ;;
      esac
    done <<<"${pkg_recs[$rel]}"
  done
}

has_go() { [[ ${#go_files[@]} -gt 0 || ${#gowork_files[@]} -gt 0 ]]; }

read_go() {
  local -A mod_recs=() mod_name=() replaced=() ws_members=()
  local rel rec decl target old is_local normalized cand
  local us=$'\x1f'

  for rel in "${go_files[@]+"${go_files[@]}"}"; do
    mod_recs[$rel]="$(go_mod_records "$root/$rel")"
    mod_name[$rel]="$(printf '%s\n' "${mod_recs[$rel]}" | record_value module)"
    add_project_node "$rel" "${mod_name[$rel]}"
    while IFS= read -r rec; do
      [[ "$rec" == unread$'\t'* ]] && add_unread_manifest "$rel" "${rec#*$'\t'}"
    done <<<"${mod_recs[$rel]}"
  done

  for rel in "${go_files[@]+"${go_files[@]}"}"; do
    while IFS= read -r rec; do
      [[ "$rec" == replace$'\t'* ]] || continue
      IFS=$'\t' read -r _ old target is_local decl <<<"$rec"
      [[ "$is_local" == 1 ]] || continue
      replaced[$rel$us$old]=1
      cand=""
      if normalized="$(normalize_within_root "$(proj_dir_of "$rel")" "$target")"; then
        cand="${normalized:+$normalized/}go.mod"
      fi
      if [[ -n "$cand" && "$cand" != "$rel" && -n "${mod_recs[$cand]+x}" ]]; then
        add_edge "$rel" "$cand" "project" "resolved" "$rel: $decl"
      else
        add_edge "$rel" "$target" "project" "unresolved" "$rel: $decl"
      fi
    done <<<"${mod_recs[$rel]}"
  done

  local work
  for work in "${gowork_files[@]+"${gowork_files[@]}"}"; do
    while IFS= read -r rec; do
      case "$rec" in
      unread$'\t'*) add_unread_manifest "$work" "${rec#*$'\t'}" ;;
      use$'\t'*)
        IFS=$'\t' read -r _ target decl <<<"$rec"
        cand=""
        if normalized="$(normalize_within_root "$(proj_dir_of "$work")" "$target")"; then
          cand="${normalized:+$normalized/}go.mod"
        fi
        if [[ -n "$cand" && -n "${mod_recs[$cand]+x}" ]]; then
          ws_members[$work]+="$cand$us$decl"$'\n'
        else
          add_unread_manifest "$work" "$decl"
        fi
        ;;
      *) ;;
      esac
    done <<<"$(go_work_records "$root/$work")"
  done

  local mod hit hit_decl line
  for rel in "${go_files[@]+"${go_files[@]}"}"; do
    while IFS= read -r rec; do
      [[ "$rec" == require$'\t'* ]] || continue
      IFS=$'\t' read -r _ mod _ decl <<<"$rec"
      [[ -z "${replaced[$rel$us$mod]+x}" ]] || continue
      hit=""
      for work in "${gowork_files[@]+"${gowork_files[@]}"}"; do
        [[ "${ws_members[$work]-}" == *"$rel$us"* ]] || continue
        while IFS= read -r line; do
          [[ -n "$line" ]] || continue
          cand="${line%%"$us"*}"
          [[ "$cand" != "$rel" && "${mod_name[$cand]}" == "$mod" ]] || continue
          hit="$cand"
          hit_decl="$work: ${line#*"$us"}"
          break
        done <<<"${ws_members[$work]}"
        [[ -z "$hit" ]] || break
      done
      if [[ -n "$hit" ]]; then
        add_edge "$rel" "$hit" "project" "resolved" "$hit_decl"
      else
        add_node "pkg:go:$mod" "$mod" "" "package"
        add_edge "$rel" "pkg:go:$mod" "package" "resolved" "$rel: $decl"
      fi
    done <<<"${mod_recs[$rel]}"
  done
}

has_python() { [[ ${#py_files[@]} -gt 0 || ${#req_files[@]} -gt 0 || ${#setup_files[@]} -gt 0 ]]; }

read_python() {
  local -A is_pyproject=() is_setup=() seen=() named_path=() recs=()
  local rel rec kind a b c
  local us=$'\x1f'

  for rel in "${py_files[@]+"${py_files[@]}"}"; do is_pyproject[$rel]=1; done
  for rel in "${setup_files[@]+"${setup_files[@]}"}"; do is_setup[$rel]=1; done

  py_owner() {
    local pre
    pre="$(proj_dir_of "$1")"
    pre="${pre:+$pre/}"
    if [[ -n "${is_pyproject[${pre}pyproject.toml]+x}" ]]; then
      printf '%s\n' "${pre}pyproject.toml"
    elif [[ -n "${is_setup[${pre}setup.py]+x}" ]]; then
      printf '%s\n' "${pre}setup.py"
    else
      printf '%s\n' "$1"
    fi
  }

  py_target() {
    local n
    n="$(normalize_within_root "$1" "$2")" || return 1
    n="${n:+$n/}"
    if [[ -n "${is_pyproject[${n}pyproject.toml]+x}" ]]; then
      printf '%s\n' "${n}pyproject.toml"
    elif [[ -n "${is_setup[${n}setup.py]+x}" ]]; then
      printf '%s\n' "${n}setup.py"
    else
      return 1
    fi
  }

  py_path_edge() {
    local id
    if id="$(py_target "$(proj_dir_of "$2")" "$3")"; then
      [[ "$id" == "$1" ]] || add_edge "$1" "$id" "project" "resolved" "$2: $4"
    else
      add_edge "$1" "$3" "project" "unresolved" "$2: $4"
    fi
  }

  py_pkg_edge() {
    add_node "pkg:python:$2" "$2" "" "package"
    add_edge "$1" "pkg:python:$2" "package" "resolved" "$3: $4"
  }

  for rel in "${py_files[@]+"${py_files[@]}"}"; do
    recs[$rel]="$(py_project_records "$root/$rel")"
    add_project_node "$rel" "$(printf '%s\n' "${recs[$rel]}" | record_value name)"
  done
  for rel in "${setup_files[@]+"${setup_files[@]}"}"; do
    add_unread_manifest "$rel" "setup.py is not executed or parsed"
    add_project_node "$rel" ""
  done
  for rel in "${req_files[@]+"${req_files[@]}"}"; do
    [[ "$(py_owner "$rel")" == "$rel" ]] && add_node "$rel" "${rel##*/}" "$rel" "project"
  done

  for rel in "${py_files[@]+"${py_files[@]}"}"; do
    while IFS= read -r rec; do
      IFS=$'\t' read -r kind a b c <<<"$rec"
      case "$kind" in
      path)
        [[ -z "$c" ]] || named_path[$rel$us$c]=1
        py_path_edge "$rel" "$rel" "$a" "$b"
        ;;
      unread) add_unread_manifest "$rel" "$a" ;;
      *) ;;
      esac
    done <<<"${recs[$rel]}"
    while IFS= read -r rec; do
      IFS=$'\t' read -r kind a b <<<"$rec"
      [[ "$kind" == pkg && -z "${named_path[$rel$us$a]+x}" ]] && py_pkg_edge "$rel" "$a" "$rel" "$b"
    done <<<"${recs[$rel]}"
  done

  for rel in "${py_files[@]+"${py_files[@]}"}"; do
    add_member_edges "$rel" "${recs[$rel]}" keep-dot "${py_files[@]}"
  done

  py_read_req() {
    local file="$1" owner="$2" inc rec kind a b c
    seen[$file]=1
    while IFS= read -r rec; do
      IFS=$'\t' read -r kind a b c <<<"$rec"
      case "$kind" in
      pkg) py_pkg_edge "$owner" "$a" "$file" "$b" ;;
      path) py_path_edge "$owner" "$file" "$a" "$b" ;;
      include)
        if inc="$(normalize_within_root "$(proj_dir_of "$file")" "$a")" && [[ -f "$root/$inc" ]]; then
          [[ -n "${seen[$inc]+x}" ]] || py_read_req "$inc" "$owner"
        else
          add_unread_manifest "$file" "$b"
        fi
        ;;
      unread) add_unread_manifest "$file" "$a" ;;
      *) ;;
      esac
    done <<<"$(py_requirements_records "$root/$file")"
  }
  for rel in "${req_files[@]+"${req_files[@]}"}"; do
    seen=()
    py_read_req "$rel" "$(py_owner "$rel")"
  done
}

has_rust() { [[ ${#cargo_files[@]} -gt 0 ]]; }

read_rust() {
  local -A is_cargo=() recs=() has_ws=() wdep=()
  local rel rec kind a b c d us=$'\x1f'

  for rel in "${cargo_files[@]}"; do is_cargo[$rel]=1; done

  rust_path_edge() {
    local n id
    if n="$(normalize_within_root "$(proj_dir_of "$2")" "$3")" && [[ -n "${is_cargo[${n:+$n/}Cargo.toml]+x}" ]]; then
      id="${n:+$n/}Cargo.toml"
      [[ "$id" == "$1" ]] || add_edge "$1" "$id" "project" "resolved" "$4"
    else
      add_edge "$1" "$3" "project" "unresolved" "$4"
    fi
  }

  rust_pkg_edge() {
    add_node "pkg:rust:$2" "$2" "" "package"
    add_edge "$1" "pkg:rust:$2" "package" "resolved" "$3"
  }

  for rel in "${cargo_files[@]}"; do
    recs[$rel]="$(rust_manifest_records "$root/$rel")"
    add_project_node "$rel" "$(printf '%s\n' "${recs[$rel]}" | record_value name)"
  done

  for rel in "${cargo_files[@]}"; do
    while IFS= read -r rec; do
      IFS=$'\t' read -r kind a b c d <<<"$rec"
      case "$kind" in
      workspace) has_ws[$rel]=1 ;;
      path) rust_path_edge "$rel" "$rel" "$a" "$rel: $b" ;;
      pkg) rust_pkg_edge "$rel" "$a" "$rel: $b" ;;
      wpath) wdep[$rel$us$c]="p$us$a$us$b" ;;
      wpkg) wdep[$rel$us$a]="k$us$b$us$c" ;;
      unread) add_unread_manifest "$rel" "$a" ;;
      *) ;;
      esac
    done <<<"${recs[$rel]}"
  done

  local wroot cur entry
  for rel in "${cargo_files[@]}"; do
    while IFS= read -r rec; do
      [[ "$rec" == inherit$'\t'* ]] || continue
      IFS=$'\t' read -r _ a b <<<"$rec"
      wroot=""
      cur="$(proj_dir_of "$rel")"
      while :; do
        if [[ -n "${has_ws[${cur:+$cur/}Cargo.toml]+x}" ]]; then
          wroot="${cur:+$cur/}Cargo.toml"
          break
        fi
        [[ -n "$cur" ]] || break
        cur="$(proj_dir_of "$cur")"
      done
      entry=""
      [[ -z "$wroot" ]] || entry="${wdep[$wroot$us$a]-}"
      if [[ -z "$entry" ]]; then
        add_unread_manifest "$rel" "$b"
        continue
      fi
      IFS=$us read -r kind c d <<<"$entry"
      if [[ "$kind" == p ]]; then
        rust_path_edge "$rel" "$wroot" "$c" "$rel: $b via $wroot: $d"
      else
        rust_pkg_edge "$rel" "$c" "$rel: $b via $wroot: $d"
      fi
    done <<<"${recs[$rel]}"
  done

  for rel in "${cargo_files[@]}"; do
    [[ -n "${has_ws[$rel]+x}" ]] || continue
    add_member_edges "$rel" "${recs[$rel]}" skip-dot "${cargo_files[@]}"
  done
}

has_jvm() { [[ ${#pom_files[@]} -gt 0 || ${#gradle_files[@]} -gt 0 || ${#settings_files[@]} -gt 0 ]]; }

read_jvm() {
  local -A is_pom=() gnode=() is_settings=()
  local rel dir rec kind a b n cur sdir

  gradle_edge() {
    local p="${3#:}" t
    p="${p//://}"
    if t="$(normalize_within_root "$2" "$p")" && [[ -n "${gnode[/$t]+x}" ]]; then
      [[ "${gnode[/$t]}" == "$1" ]] || add_edge "$1" "${gnode[/$t]}" "project" "resolved" "$4"
    else
      add_edge "$1" "$3" "project" "unresolved" "$4"
    fi
  }

  for rel in "${gradle_files[@]+"${gradle_files[@]}"}"; do
    dir="$(proj_dir_of "$rel")"
    add_project_node "$rel" ""
    [[ -n "${gnode[/$dir]+x}" ]] || gnode[/$dir]="$rel"
  done
  for rel in "${settings_files[@]+"${settings_files[@]}"}"; do
    dir="$(proj_dir_of "$rel")"
    is_settings[/$dir]=1
    if [[ -z "${gnode[/$dir]+x}" ]]; then
      add_project_node "$rel" ""
      gnode[/$dir]="$rel"
    fi
  done

  for rel in "${settings_files[@]+"${settings_files[@]}"}"; do
    dir="$(proj_dir_of "$rel")"
    while IFS=$'\t' read -r kind a b; do
      case "$kind" in
      include) gradle_edge "${gnode[/$dir]}" "$dir" "$a" "$rel: $b" ;;
      unread) add_unread_manifest "$rel" "$a" ;;
      *) ;;
      esac
    done < <(jvm_settings_records "$root/$rel")
  done

  for rel in "${gradle_files[@]+"${gradle_files[@]}"}"; do
    dir="$(proj_dir_of "$rel")"
    sdir=""
    cur="$dir"
    while :; do
      if [[ -n "${is_settings[/$cur]+x}" ]]; then
        sdir="$cur"
        break
      fi
      [[ -n "$cur" ]] || break
      cur="$(proj_dir_of "$cur")"
    done
    while IFS=$'\t' read -r kind a b; do
      case "$kind" in
      project)
        if [[ "$a" == :* && -z "${is_settings[/$sdir]+x}" ]]; then
          add_edge "$rel" "$a" "project" "unresolved" "$rel: $b"
        elif [[ "$a" == :* ]]; then
          gradle_edge "$rel" "$sdir" "$a" "$rel: $b"
        else
          gradle_edge "$rel" "$dir" "$a" "$rel: $b"
        fi
        ;;
      unread) add_unread_manifest "$rel" "$a" ;;
      *) ;;
      esac
    done < <(jvm_build_records "$root/$rel")
  done

  for rel in "${pom_files[@]+"${pom_files[@]}"}"; do
    is_pom[$rel]=1
  done
  for rel in "${pom_files[@]+"${pom_files[@]}"}"; do
    add_project_node "$rel" "$(jvm_pom_records "$root/$rel" | record_value name)"
  done
  for rel in "${pom_files[@]+"${pom_files[@]}"}"; do
    dir="$(proj_dir_of "$rel")"
    while IFS=$'\t' read -r kind a b; do
      case "$kind" in
      module)
        if [[ "$a" == *.xml && "${a##*/}" != pom.xml ]]; then
          add_unread_manifest "$rel" "$b"
        elif n="$(normalize_within_root "$dir" "$a")"; then
          [[ "$a" == *.xml ]] || n="${n:+$n/}pom.xml"
          if [[ -n "${is_pom[$n]+x}" ]]; then
            [[ "$n" == "$rel" ]] || add_edge "$rel" "$n" "project" "resolved" "$rel: $b"
          else
            add_edge "$rel" "$a" "project" "unresolved" "$rel: $b"
          fi
        else
          add_edge "$rel" "$a" "project" "unresolved" "$rel: $b"
        fi
        ;;
      unread) add_unread_manifest "$rel" "$a" ;;
      *) ;;
      esac
    done < <(jvm_pom_records "$root/$rel")
  done
}

ecos_read=()
for eco in "${READERS[@]}"; do
  "has_$eco" || continue
  CUR_ECO="$eco"
  "read_$eco"
  ecos_read+=("$eco")
done

result="ok"
message=""
case "${#ecos_read[@]}" in
0) ecosystem="unknown" ;;
1) ecosystem="${ecos_read[0]}" ;;
*) ecosystem="mixed" ;;
esac
if [[ "$ecosystem" == "unknown" ]]; then
  result="unknown"
  if [[ -n "$other_msg" ]]; then
    message="Found build manifests for $other_msg and none that a shipped adapter reads ($readers_list). Those adapters are not shipped, so this run did not invent an empty graph."
  elif [[ "$has_global_json" -eq 1 ]]; then
    message="Found global.json and none that a shipped adapter reads ($readers_list). global.json names an SDK and declares no project graph, so this run did not invent an empty graph."
  else
    message="No recognized build manifest. This run did not invent an empty graph."
  fi
elif [[ -n "$other_msg" ]]; then
  message="Not read: $other_msg. No adapter for it is shipped; an unread ecosystem is left unread rather than drawn as an empty graph."
fi

cycle_json=()
if [[ ${#edge_from[@]} -gt 0 ]]; then
  cycle_feed=""
  for i in "${!edge_from[@]}"; do
    if [[ "${edge_kind[$i]}" == "project" && "${edge_status[$i]}" == "resolved" ]]; then
      cycle_feed+="${edge_from[$i]}"$'\t'"${edge_to[$i]}"$'\n'
    fi
  done
  if [[ -n "$cycle_feed" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      json_object id "$line"
      cycle_json+=("$JSON_OBJ")
    done < <(printf '%s' "$cycle_feed" | LC_ALL=C awk '
      function strong(v,    k, w, c) {
        idx[v] = ++counter
        low[v] = idx[v]
        stk[++sp] = v
        onstk[v] = 1
        for (k = 1; k <= adjn[v]; k++) {
          w = adjv[v, k]
          if (!(w in idx)) {
            strong(w)
            if (low[w] < low[v]) low[v] = low[w]
          } else if (onstk[w] && idx[w] < low[v]) low[v] = idx[w]
        }
        if (low[v] == idx[v]) {
          c = ++ncomp
          do {
            w = stk[sp--]
            onstk[w] = 0
            comp[w] = c
            size[c]++
            if (!(c in cmin) || w < cmin[c]) cmin[c] = w
          } while (w != v)
        }
      }
      function witness(c,    s, head, tail, u, k, w, path, x) {
        s = cmin[c]
        split("", seen)
        split("", par)
        queue[1] = s
        seen[s] = 1
        head = 1
        tail = 1
        while (head <= tail) {
          u = queue[head++]
          for (k = 1; k <= adjn[u]; k++) {
            w = adjv[u, k]
            if (comp[w] != c) continue
            if (w == s) {
              path = u
              for (x = u; x != s; ) { x = par[x]; path = x " -> " path }
              return path " -> " s
            }
            if (!(w in seen)) { seen[w] = 1; par[w] = u; queue[++tail] = w }
          }
        }
        return ""
      }
      BEGIN { FS = "\t" }
      {
        if ($1 == "" || $2 == "") next
        key = $1 "\t" $2
        if (key in seen_edge) next
        seen_edge[key] = 1
        if (!($1 in known)) { known[$1] = 1; nodes[++nn] = $1 }
        if (!($2 in known)) { known[$2] = 1; nodes[++nn] = $2 }
        adjv[$1, ++adjn[$1]] = $2
        if ($1 == $2) selfloop[$1] = 1
      }
      END {
        for (i = 1; i <= nn; i++) if (!(nodes[i] in idx)) strong(nodes[i])
        for (c = 1; c <= ncomp; c++) {
          if (size[c] > 1 || (cmin[c] in selfloop)) print witness(c)
        }
      }
    ')
  fi
fi

node_json=()
for i in "${!node_ids[@]}"; do
  fields=(id "${node_ids[$i]}" name "${node_names[$i]}" path "${node_paths[$i]}" ecosystem "${node_ecos[$i]}" kind "${node_kinds[$i]}")
  if [[ "${node_kinds[$i]}" == "project" ]] && is_proj_suffix "${node_paths[$i]}"; then
    node_ns="$(node_namespace "${node_paths[$i]}")"
    [[ -z "$node_ns" ]] || fields+=(namespace "$node_ns")
    dotnet_is_test_project "$root/${node_paths[$i]}" && fields+=(test yes)
  fi
  json_object "${fields[@]}"
  node_json+=("$JSON_OBJ")
done
edge_json=()
for i in "${!edge_from[@]}"; do
  json_object from "${edge_from[$i]}" to "${edge_to[$i]}" kind "${edge_kind[$i]}" status "${edge_status[$i]}" evidence "${edge_evidence[$i]}"
  edge_json+=("$JSON_OBJ")
done
finding_json=()
for i in "${!finding_kind[@]}"; do
  json_object kind "${finding_kind[$i]}" path "${finding_path[$i]}" evidence "${finding_evidence[$i]}"
  finding_json+=("$JSON_OBJ")
done

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
  printf '  "cycles_truncated": false,\n'
  emit_array "nodes" , "${node_json[@]+"${node_json[@]}"}"
  emit_array "edges" , "${edge_json[@]+"${edge_json[@]}"}"
  emit_array "cycles" , "${cycle_json[@]+"${cycle_json[@]}"}"
  emit_array "findings" "" "${finding_json[@]+"${finding_json[@]}"}"
  printf '}\n'
}

if [[ -n "$out_file" ]]; then
  emit_document >"$out_file" || die "cannot write --out file: $out_file" 1
else
  emit_document
fi

exit 0
