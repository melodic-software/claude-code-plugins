#!/usr/bin/env bash
# Collect a C4 container record from tracked project output, Dockerfiles, and config.
#
# WHY. A container is an application or a data store that has to be running.
# Directory names are not that fact, and neither is source. This script reads
# git HEAD: SDK and OutputType in project files, Dockerfiles, and committed
# configuration those deployables sit with. Host-builder calls in source are
# not read.
#
# Usage:
#   collect-containers.sh [--repo <path>] [--out <file>] [--generated-on <date>]
#       [--system <name>]
#   collect-containers.sh --help
#
# containers.json is schema_version 1, one object per line:
#   nodes:   {"id","name","kind","output_kind","technology","evidence"}
#   modules: {"container","path","name","evidence"}
#   edges:   {"from","to","kind","evidence"}
#
# A library project referenced by a deployable is a module, not a container.
# Two deployables that name the same store host produce one shared-infrastructure
# edge whose evidence cites both config keys. Credential values are not written.
#
# Portability: bash plus POSIX awk. No jq, no grep -P, no python.
#
# Exit: 0 = a record was written; 1 = unreadable repo or no commit; 2 = usage.
set -uo pipefail

NODE_THRESHOLD=24
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../../../lib"
REDACT_AWK="$LIB_DIR/redact-connection.awk"
SCAN_AWK="$SCRIPT_DIR/scan-json-shapes.awk"

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'collect-containers.sh: %s\n' "$1" >&2
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

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

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
      [[ ${#out[@]} -eq 0 ]] && return 1
      unset 'out[${#out[@]}-1]'
      ;;
    *) out+=("$seg") ;;
    esac
  done
  for s in "${out[@]+"${out[@]}"}"; do
    if [[ -z "$joined" ]]; then joined="$s"; else joined="$joined/$s"; fi
  done
  [[ -n "$joined" ]] || return 1
  printf '%s' "$joined"
}

repo=""
out_file=""
generated_on=""
system_filter=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h) usage; exit 0 ;;
  --repo) [[ $# -ge 2 ]] || die "--repo needs a path" 2; repo="$2"; shift 2 ;;
  --repo=*) repo="${1#--repo=}"; shift ;;
  --out) [[ $# -ge 2 ]] || die "--out needs a file" 2; out_file="$2"; shift 2 ;;
  --out=*) out_file="${1#--out=}"; shift ;;
  --generated-on) [[ $# -ge 2 ]] || die "--generated-on needs a date" 2; generated_on="$2"; shift 2 ;;
  --generated-on=*) generated_on="${1#--generated-on=}"; shift ;;
  --system) [[ $# -ge 2 ]] || die "--system needs a name" 2; system_filter="$2"; shift 2 ;;
  --system=*) system_filter="${1#--system=}"; shift ;;
  *) die "unknown argument: $1" 2 ;;
  esac
done

[[ -n "$repo" ]] || repo="$(pwd)"
[[ -d "$repo" ]] || die "not a directory: $repo" 1
git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1 || die "no commit to read: $repo" 1
[[ -n "$generated_on" ]] || generated_on="$(date -u +%Y-%m-%d)"
root="$(cd "$repo" && pwd)"
subject="$(basename "$root")"
remote="$(git -C "$root" remote get-url origin 2>/dev/null)" || remote=""
if [[ "$remote" == *github.com* ]]; then
  url="${remote%/}"
  url="${url%.git}"
  url="${url#*://}"
  url="${url#*@}"
  rest="${url#*/}"
  repo_name="${rest%%/*}"
  [[ "$rest" == */* ]] && repo_name="${rest#*/}" && repo_name="${repo_name%%/*}"
  [[ -n "$repo_name" && "$repo_name" != "$rest" ]] && subject="$repo_name"
fi

declare -a ALL=()
declare -A TRACKED=()
while IFS= read -r -d '' rel; do
  case "$rel" in
  */node_modules/* | node_modules/* | */vendor/* | */obj/* | */bin/* | */packages/*) continue ;;
  esac
  ALL+=("$rel")
  TRACKED["$rel"]=1
done < <(git -C "$root" ls-tree -r --name-only -z HEAD)

git_show() {
  git -C "$root" show "HEAD:$1" 2>/dev/null
}

D_N=0
S_N=0
B_N=0
M_N=0
declare -a D_ID D_NAME D_OUT D_TECH D_EV D_DIR
declare -a S_ID S_NAME S_KIND S_OUT S_TECH S_EV
declare -a B_FROM B_TO B_EV
declare -a M_C M_PATH M_NAME M_EV
declare -A D_AT=() S_AT=() IS_DEPLOY=()

add_deployable() {
  local id="$1" name="$2" outk="$3" tech="$4" ev="$5" dir="$6"
  [[ -n "${D_AT[$id]:-}" ]] && return 0
  [[ -n "$tech" ]] || tech="unknown"
  [[ -n "$outk" ]] || outk="unknown"
  D_AT["$id"]=$D_N
  IS_DEPLOY["$id"]=1
  D_ID[$D_N]="$id"
  D_NAME[$D_N]="$name"
  D_OUT[$D_N]="$outk"
  D_TECH[$D_N]="$tech"
  D_EV[$D_N]="$ev"
  D_DIR[$D_N]="$dir"
  D_N=$((D_N + 1))
}

add_store() {
  local id="$1" name="$2" skind="$3" outk="$4" tech="$5" ev="$6" idx
  [[ -n "$tech" ]] || tech="unknown"
  [[ -n "$name" ]] || name="unknown"
  if [[ -n "${S_AT[$id]:-}" ]]; then
    idx="${S_AT[$id]}"
    case "${S_EV[$idx]}" in
    *"$ev"*) ;;
    *) S_EV[$idx]="${S_EV[$idx]}; $ev" ;;
    esac
    return 0
  fi
  S_AT["$id"]=$S_N
  S_ID[$S_N]="$id"
  S_NAME[$S_N]="$name"
  S_KIND[$S_N]="$skind"
  S_OUT[$S_N]="$outk"
  S_TECH[$S_N]="$tech"
  S_EV[$S_N]="$ev"
  S_N=$((S_N + 1))
}

add_bind() {
  local from="$1" to="$2" ev="$3" i
  for ((i = 0; i < B_N; i++)); do
    [[ "${B_FROM[$i]}" == "$from" && "${B_TO[$i]}" == "$to" && "${B_EV[$i]}" == "$ev" ]] && return 0
  done
  B_FROM[$B_N]="$from"
  B_TO[$B_N]="$to"
  B_EV[$B_N]="$ev"
  B_N=$((B_N + 1))
}

project_kind() {
  local body="$1" line
  while IFS= read -r line; do
    case "$line" in
    *AzureFunctionsVersion*) printf 'function'; return 0 ;;
    esac
  done <<<"$body"
  while IFS= read -r line; do
    case "$line" in
    *Microsoft.NET.Sdk.Web*) printf 'web'; return 0 ;;
    esac
  done <<<"$body"
  while IFS= read -r line; do
    case "$line" in
    *Microsoft.NET.Sdk.Worker*) printf 'worker'; return 0 ;;
    esac
  done <<<"$body"
  while IFS= read -r line; do
    case "$line" in
    *'<OutputType>'*Exe* | *OutputType*Exe*) printf 'cli'; return 0 ;;
    esac
  done <<<"$body"
  return 1
}

project_tfm() {
  local body="$1" line inner
  while IFS= read -r line; do
    case "$line" in
    *'<TargetFramework>'*)
      inner="$line"
      inner="${inner#*<TargetFramework>}"
      inner="${inner%%</TargetFramework>*}"
      printf '%s' "$(trim "$inner")"
      return 0
      ;;
    esac
  done <<<"$body"
  printf 'unknown'
}

evidence_line() {
  local body="$1" needle="$2" line
  while IFS= read -r line; do
    case "$line" in
    *"$needle"*)
      printf '%s' "$(trim "$line")"
      return 0
      ;;
    esac
  done <<<"$body"
  printf '%s' "$needle"
}

for rel in "${ALL[@]+"${ALL[@]}"}"; do
  case "$rel" in
  *.csproj | *.fsproj) ;;
  *) continue ;;
  esac
  body="$(git_show "$rel")" || continue
  outk="$(project_kind "$body")" || continue
  tfm="$(project_tfm "$body")"
  base="$(basename "$rel")"
  name="${base%.*}"
  case "$outk" in
  function) needle="AzureFunctionsVersion" ;;
  web) needle="Microsoft.NET.Sdk.Web" ;;
  worker) needle="Microsoft.NET.Sdk.Worker" ;;
  cli) needle="OutputType" ;;
  *) needle="$outk" ;;
  esac
  dir="${rel%/*}"
  [[ "$dir" == "$rel" ]] && dir="."
  add_deployable "$rel" "$name" "$outk" "$tfm" "$rel: $(evidence_line "$body" "$needle")" "$dir"
done

from_image() {
  local rest tok img=""
  rest="${1#FROM }"
  rest="$(trim "$rest")"
  for tok in $rest; do
    case "$tok" in
    --*) continue ;;
    [Aa][Ss]) break ;;
    *) img="$tok" ;;
    esac
  done
  printf '%s' "${img%%@*}"
}

is_dockerfile() {
  local low
  low="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$low" in
  dockerfile | containerfile | dockerfile.* | *.dockerfile) return 0 ;;
  *) return 1 ;;
  esac
}

for rel in "${ALL[@]+"${ALL[@]}"}"; do
  is_dockerfile "$rel" || continue
  body="$(git_show "$rel")" || continue
  image=""
  from_line=""
  while IFS= read -r line; do
    line="$(trim "${line%$'\r'}")"
    case "$line" in
    FROM\ *)
      image="$(from_image "$line")"
      from_line="$line"
      ;;
    esac
  done <<<"$body"
  low="$(printf '%s' "$image" | tr '[:upper:]' '[:lower:]')"
  outk="unknown"
  case "$low" in
  *aspnet*) outk="api" ;;
  *nginx* | *httpd* | *caddy*) outk="web" ;;
  *azure-functions* | *functions-runtime*) outk="function" ;;
  esac
  [[ -n "$image" ]] || image="unknown"
  dir="${rel%/*}"
  [[ "$dir" == "$rel" ]] && dir="."
  add_deployable "$rel" "$(basename "$rel")" "$outk" "$image" "$rel: ${from_line:-no image}" "$dir"
done

# Libraries cited by a deployable project are modules, not containers.
project_refs() {
  local rel="$1" body line inc raw dir norm
  body="$(git_show "$rel")" || return 0
  dir="${rel%/*}"
  [[ "$dir" == "$rel" ]] && dir=""
  while IFS= read -r line; do
    case "$line" in
    *ProjectReference*) ;;
    *) continue ;;
    esac
    inc="$line"
    inc="${inc#*Include=\"}"
    [[ "$inc" == "$line" ]] && continue
    inc="${inc%%\"*}"
    inc="${inc//\\//}"
    if [[ -n "$dir" ]]; then raw="$dir/$inc"; else raw="$inc"; fi
    norm="$(normalize_inside "$raw")" || continue
    printf '%s\n' "$norm"
  done <<<"$body"
}

for ((i = 0; i < D_N; i++)); do
  id="${D_ID[$i]}"
  case "$id" in
  *.csproj | *.fsproj) ;;
  *) continue ;;
  esac
  declare -a QUEUE=()
  declare -A SEEN=()
  QUEUE+=("$id")
  SEEN["$id"]=1
  qi=0
  while [[ $qi -lt ${#QUEUE[@]} ]]; do
    cur="${QUEUE[$qi]}"
    qi=$((qi + 1))
    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      [[ -n "${SEEN[$ref]:-}" ]] && continue
      SEEN["$ref"]=1
      if [[ -n "${IS_DEPLOY[$ref]:-}" ]]; then
        continue
      fi
      [[ -n "${TRACKED[$ref]:-}" ]] || continue
      base="$(basename "$ref")"
      M_C[$M_N]="$id"
      M_PATH[$M_N]="$ref"
      M_NAME[$M_N]="${base%.*}"
      M_EV[$M_N]="$cur: ProjectReference Include=\"$ref\""
      M_N=$((M_N + 1))
      QUEUE+=("$ref")
    done < <(project_refs "$cur")
  done
  unset QUEUE SEEN
done

assign_mode() {
  case "$1" in
  *.json) printf 'json' ;;
  *.yml | *.yaml) printf 'yaml' ;;
  *.env) printf 'env' ;;
  *.xml | *.config) printf 'xml' ;;
  *.tf | *.bicep) printf 'hcl' ;;
  *.ini | *.properties) printf 'ini' ;;
  *) return 1 ;;
  esac
}

leaf_key() {
  local k="$1"
  k="${k##*.}"
  k="${k%%\[*}"
  printf '%s' "$k"
}

scan_config() {
  local deploy_id="$1" file="$2" mode skind host port key leaf sid outk sk
  mode="$(assign_mode "$file")" || return 0
  [[ "$mode" == "json" ]] || return 0
  while IFS='|' read -r skind host port key; do
    [[ -n "$host" ]] || continue
    leaf="$(leaf_key "$key")"
    [[ -n "$leaf" ]] || leaf="value"
    sid="store:${skind}|${host}"
    [[ -n "$port" ]] && sid="${sid}|${port}"
    case "$skind" in
    broker) sk="broker"; outk="queue" ;;
    sql) sk="store"; outk="database" ;;
    cache) sk="store"; outk="cache" ;;
    storage) sk="store"; outk="blob" ;;
    *) sk="store"; outk="unknown" ;;
    esac
    add_store "$sid" "$host" "$sk" "$outk" "unknown" "$file: $leaf"
    add_bind "$deploy_id" "$sid" "$file: $leaf"
  done < <(git_show "$file" | awk -f "$REDACT_AWK" -f "$SCAN_AWK" | awk -F '\t' 'NF >= 4 { printf "%s|%s|%s|%s\n", $1, $2, $3, $4 }')
}

for ((i = 0; i < D_N; i++)); do
  dir="${D_DIR[$i]}"
  for rel in "${ALL[@]+"${ALL[@]}"}"; do
    file_dir="${rel%/*}"
    [[ "$file_dir" == "$rel" ]] && file_dir="."
    [[ "$file_dir" == "$dir" ]] || continue
    assign_mode "$rel" >/dev/null || continue
    case "$rel" in
    *.csproj | *.fsproj) continue ;;
    esac
    is_dockerfile "$rel" && continue
    scan_config "${D_ID[$i]}" "$rel"
  done
done

SH_N=0
declare -a SH_FROM SH_TO SH_EV
declare -A BINDERS=()
for ((i = 0; i < B_N; i++)); do
  BINDERS["${B_TO[$i]}"]+="${B_FROM[$i]}"$'\t'"${B_EV[$i]}"$'\n'
done
for sid in "${!BINDERS[@]}"; do
  [[ -n "$sid" ]] || continue
  declare -A ONE=()
  while IFS=$'\t' read -r from ev; do
    [[ -n "$from" ]] || continue
    [[ -z "${ONE[$from]:-}" ]] && ONE["$from"]="$ev"
  done <<<"${BINDERS[$sid]}"
  mapfile -t ids < <(printf '%s\n' "${!ONE[@]}" | LC_ALL=C sort)
  if [[ ${#ids[@]} -ge 2 ]]; then
    for ((a = 0; a < ${#ids[@]}; a++)); do
      for ((b = a + 1; b < ${#ids[@]}; b++)); do
        SH_FROM[$SH_N]="${ids[$a]}"
        SH_TO[$SH_N]="${ids[$b]}"
        SH_EV[$SH_N]="${ONE[${ids[$a]}]}; ${ONE[${ids[$b]}]}"
        SH_N=$((SH_N + 1))
      done
    done
  fi
  unset ONE
done

if [[ -n "$system_filter" && "$system_filter" != "$subject" ]]; then
  declare -A KEEP=()
  for ((i = 0; i < D_N; i++)); do
    if [[ "${D_NAME[$i]}" == "$system_filter" || "${D_ID[$i]}" == "$system_filter" ]]; then
      KEEP["${D_ID[$i]}"]=1
    fi
  done
  declare -a ND_ID ND_NAME ND_OUT ND_TECH ND_EV ND_DIR
  nn=0
  for ((i = 0; i < D_N; i++)); do
    [[ -n "${KEEP[${D_ID[$i]}]:-}" ]] || continue
    ND_ID[$nn]="${D_ID[$i]}"
    ND_NAME[$nn]="${D_NAME[$i]}"
    ND_OUT[$nn]="${D_OUT[$i]}"
    ND_TECH[$nn]="${D_TECH[$i]}"
    ND_EV[$nn]="${D_EV[$i]}"
    ND_DIR[$nn]="${D_DIR[$i]}"
    nn=$((nn + 1))
  done
  D_ID=("${ND_ID[@]+"${ND_ID[@]}"}")
  D_NAME=("${ND_NAME[@]+"${ND_NAME[@]}"}")
  D_OUT=("${ND_OUT[@]+"${ND_OUT[@]}"}")
  D_TECH=("${ND_TECH[@]+"${ND_TECH[@]}"}")
  D_EV=("${ND_EV[@]+"${ND_EV[@]}"}")
  D_DIR=("${ND_DIR[@]+"${ND_DIR[@]}"}")
  D_N=$nn
fi

node_lines=""
for ((i = 0; i < D_N; i++)); do
  if [[ -n "$system_filter" && "$system_filter" != "$subject" && -z "${KEEP[${D_ID[$i]}]:-}" ]]; then
    continue
  fi
  json_escape "${D_ID[$i]}"
  line="{\"id\":\"$JSON_ESC\""
  json_escape "${D_NAME[$i]}"
  line="$line,\"name\":\"$JSON_ESC\""
  line="$line,\"kind\":\"deployable\""
  json_escape "${D_OUT[$i]}"
  line="$line,\"output_kind\":\"$JSON_ESC\""
  json_escape "${D_TECH[$i]}"
  line="$line,\"technology\":\"$JSON_ESC\""
  json_escape "${D_EV[$i]}"
  line="$line,\"evidence\":\"$JSON_ESC\"}"
  node_lines="$node_lines$line"$'\n'
done
for ((i = 0; i < S_N; i++)); do
  json_escape "${S_ID[$i]}"
  line="{\"id\":\"$JSON_ESC\""
  json_escape "${S_NAME[$i]}"
  line="$line,\"name\":\"$JSON_ESC\""
  json_escape "${S_KIND[$i]}"
  line="$line,\"kind\":\"$JSON_ESC\""
  json_escape "${S_OUT[$i]}"
  line="$line,\"output_kind\":\"$JSON_ESC\""
  json_escape "${S_TECH[$i]}"
  line="$line,\"technology\":\"$JSON_ESC\""
  json_escape "${S_EV[$i]}"
  line="$line,\"evidence\":\"$JSON_ESC\"}"
  node_lines="$node_lines$line"$'\n'
done

module_lines=""
for ((i = 0; i < M_N; i++)); do
  if [[ -n "$system_filter" && "$system_filter" != "$subject" && -z "${KEEP[${M_C[$i]}]:-}" ]]; then
    continue
  fi
  json_escape "${M_C[$i]}"
  line="{\"container\":\"$JSON_ESC\""
  json_escape "${M_PATH[$i]}"
  line="$line,\"path\":\"$JSON_ESC\""
  json_escape "${M_NAME[$i]}"
  line="$line,\"name\":\"$JSON_ESC\""
  json_escape "${M_EV[$i]}"
  line="$line,\"evidence\":\"$JSON_ESC\"}"
  module_lines="$module_lines$line"$'\n'
done

edge_lines=""
for ((i = 0; i < B_N; i++)); do
  if [[ -n "$system_filter" && "$system_filter" != "$subject" && -z "${KEEP[${B_FROM[$i]}]:-}" ]]; then
    continue
  fi
  json_escape "${B_FROM[$i]}"
  line="{\"from\":\"$JSON_ESC\""
  json_escape "${B_TO[$i]}"
  line="$line,\"to\":\"$JSON_ESC\""
  line="$line,\"kind\":\"binds\""
  json_escape "${B_EV[$i]}"
  line="$line,\"evidence\":\"$JSON_ESC\"}"
  edge_lines="$edge_lines$line"$'\n'
done
for ((i = 0; i < SH_N; i++)); do
  if [[ -n "$system_filter" && "$system_filter" != "$subject" ]]; then
    [[ -n "${KEEP[${SH_FROM[$i]}]:-}" && -n "${KEEP[${SH_TO[$i]}]:-}" ]] || continue
  fi
  json_escape "${SH_FROM[$i]}"
  line="{\"from\":\"$JSON_ESC\""
  json_escape "${SH_TO[$i]}"
  line="$line,\"to\":\"$JSON_ESC\""
  line="$line,\"kind\":\"shared-infrastructure\""
  json_escape "${SH_EV[$i]}"
  line="$line,\"evidence\":\"$JSON_ESC\"}"
  edge_lines="$edge_lines$line"$'\n'
done

sort_lines() {
  [[ -z "$1" ]] && return 0
  printf '%s\n' "$1" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u
}
node_lines="$(sort_lines "$node_lines")"
module_lines="$(sort_lines "$module_lines")"
edge_lines="$(sort_lines "$edge_lines")"

emit_array() {
  local key="$1" body="$2" comma="$3"
  if [[ -z "$body" ]]; then
    printf '  "%s": []%s\n' "$key" "$comma"
    return
  fi
  printf '  "%s": [\n' "$key"
  printf '%s\n' "$body" | awk 'NF { lines[++n] = $0 } END { for (i = 1; i <= n; i++) printf "    %s%s\n", lines[i], (i < n ? "," : "") }'
  printf '  ]%s\n' "$comma"
}

n_deploy=0
n_store=0
n_broker=0
n_bind=0
n_shared=0
n_mod=0
if [[ -n "$node_lines" ]]; then
  n_deploy="$(printf '%s\n' "$node_lines" | grep -c '"kind":"deployable"' || true)"
  n_store="$(printf '%s\n' "$node_lines" | grep -c '"kind":"store"' || true)"
  n_broker="$(printf '%s\n' "$node_lines" | grep -c '"kind":"broker"' || true)"
fi
if [[ -n "$edge_lines" ]]; then
  n_bind="$(printf '%s\n' "$edge_lines" | grep -c '"kind":"binds"' || true)"
  n_shared="$(printf '%s\n' "$edge_lines" | grep -c '"kind":"shared-infrastructure"' || true)"
fi
[[ -n "$module_lines" ]] && n_mod="$(printf '%s\n' "$module_lines" | grep -c . || true)"

record_body="$(
  json_escape "$generated_on"
  printf '{\n  "schema_version": 1,\n  "generated_on": "%s",\n' "$JSON_ESC"
  json_escape "$subject"
  printf '  "subject": "%s",\n' "$JSON_ESC"
  printf '  "dependencies": "absent",\n'
  printf '  "node_threshold": %s,\n' "$NODE_THRESHOLD"
  json_escape "$system_filter"
  printf '  "system_filter": "%s",\n' "$JSON_ESC"
  emit_array nodes "$node_lines" ","
  emit_array modules "$module_lines" ","
  emit_array edges "$edge_lines" ""
  printf '}\n'
)"

if [[ -n "$out_file" ]]; then
  mkdir -p "$(dirname "$out_file")"
  printf '%s\n' "$record_body" >"$out_file"
else
  printf '%s\n' "$record_body"
fi
printf 'containers: deployables=%s stores=%s brokers=%s modules=%s binds=%s shared=%s dependencies=absent\n' \
  "$n_deploy" "$n_store" "$n_broker" "$n_mod" "$n_bind" "$n_shared"
exit 0
