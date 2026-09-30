#!/usr/bin/env bash
# Collect a C4 container record from the tracked files of one repository.
#
# WHY. A container is an application or a data store. Directory names are not
# that fact. Every deployable cites the project output, the host builder, a
# Dockerfile, or a process manifest. Every store cites a config key. The raw
# value is never stored.
#
# A C4 container is an application or a data store, and the container diagram
# scopes to one software system. Basis: https://c4model.com/diagrams/container
# and https://c4model.com/ . Verified 2026-09-28. Recheck when that page
# changes what a container is or stops scoping the diagram to one system.
#
# Usage:
#   collect-containers.sh [--repo <path>] [--out <file>] [--focal <name>]
#       [--graph <dependency-graph.json>] [--generated-on <date>]
#   collect-containers.sh --help
#
# Tracked files only (git ls-tree HEAD). Each is read from the working tree, not
# from HEAD, so one edit to a tracked file is charted; when git status reports
# any, the count is the dirty-tracked-files finding. --graph, when set, supplies
# project edges for containment and is not re-derived from ProjectReference.
# Without it the edges come from lib/dotnet-references.sh, the reader
# map-dependencies uses. A reference whose target is missing, escapes the
# repository, is absolute, or is a glob is not a module. Nothing is matched by
# project name. A test project (dotnet_is_test_project) is not a deployable, and
# the count of those that would otherwise be one is the excluded-test-projects
# finding.
#
# schema_version 1, one object per line:
#   containers: {"id": ...}
#   modules:    {"container": ...}
#   edges:      {"from": ...}
#   findings:   {"kind": ...}
# Edge kind shared-infrastructure is one edge per pair of owners of a store, and
# cites the config keys of both. A sql store is one host, port, and database; with
# no database named the id says "database unknown" and an edge between its
# owners says "same server, database unknown".
# Edge kind uses between two deployables is one edge per pair: from the deployable
# whose own config names an http endpoint, to the deployable it resolves to. It
# cites the config key and the fact that resolved it: a compose service whose
# build context is the target's directory (the endpoint host is the service name,
# and a declared port equals the endpoint's), or a launchSettings.json
# applicationUrl on the target (localhost or 127.0.0.1 and the same port). An
# endpoint that resolves to no deployable or to several draws no edge and is an
# external-endpoint finding with its redacted host. A self-reference draws none.
# technology is a runtime, framework, or image, or the literal unknown. A sql
# store's is its URL scheme (mongodb, postgres, mysql), Azure SQL for a
# database.windows.net host, or unknown.
#
# Redaction is plugins/architecture/lib/redact-connection.awk.
# Portability: bash plus POSIX awk/sed. No jq, no python.
#
# Exit: 0 written; 1 unreadable path, not a git commit, or a bad graph; 2 usage.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/dotnet-references.sh
source "$SCRIPT_DIR/../../../lib/dotnet-references.sh"
REDACT_AWK="$SCRIPT_DIR/../../../lib/redact-connection.awk"
ASSIGN_AWK="$SCRIPT_DIR/../../../lib/config-assignments.awk"
# shellcheck source=../../../lib/family-records.sh
source "$SCRIPT_DIR/../../../lib/family-records.sh"
# shellcheck source=../../../lib/github-remote.sh
source "$SCRIPT_DIR/../../../lib/github-remote.sh"

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

normalize_inside() {
  local raw="$1" seg joined="" s
  local -a segs=() out=()
  raw="${raw//\\//}"
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

repo=""
out_file=""
focal=""
graph_file=""
generated_on=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h) usage; exit 0 ;;
  --repo) [[ $# -ge 2 ]] || die "--repo needs a path" 2; repo="$2"; shift 2 ;;
  --repo=*) repo="${1#--repo=}"; shift ;;
  --out) [[ $# -ge 2 ]] || die "--out needs a path" 2; out_file="$2"; shift 2 ;;
  --out=*) out_file="${1#--out=}"; shift ;;
  --focal) [[ $# -ge 2 ]] || die "--focal needs a name" 2; focal="$2"; shift 2 ;;
  --focal=*) focal="${1#--focal=}"; shift ;;
  --graph) [[ $# -ge 2 ]] || die "--graph needs a path" 2; graph_file="$2"; shift 2 ;;
  --graph=*) graph_file="${1#--graph=}"; shift ;;
  --generated-on) [[ $# -ge 2 ]] || die "--generated-on needs a date" 2; generated_on="$2"; shift 2 ;;
  --generated-on=*) generated_on="${1#--generated-on=}"; shift ;;
  *) die "unknown argument: $1" 2 ;;
  esac
done

if [[ -z "$repo" ]]; then
  repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$repo" ]] || repo="$(pwd)"
fi
[[ -d "$repo" ]] || die "not a directory: $repo" 1
root="$(cd -P "$repo" 2>/dev/null && pwd)" || die "unreadable: $repo" 1
git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1 || die "no commit to read: $root" 1
if [[ -n "$graph_file" && ! -r "$graph_file" ]]; then
  die "cannot read graph: $graph_file" 1
fi
[[ -n "$generated_on" ]] || generated_on="$(git -C "$root" log -1 --format=%cs 2>/dev/null || true)"
[[ -n "$generated_on" ]] || generated_on="unknown"

subject="$(basename "$root")"
origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
if [[ -n "$origin" ]]; then
  if resolved="$(github_repo_name "$origin")"; then
    subject="$resolved"
  fi
fi
[[ -n "$focal" ]] || focal="$subject"

files_list="$(mktemp)"
all_proj="$(mktemp)"
deploy="$(mktemp)"
refs="$(mktemp)"
modules="$(mktemp)"
extras="$(mktemp)"
edges="$(mktemp)"
hits="$(mktemp)"
container_body="$(mktemp)"
module_body="$(mktemp)"
edge_body="$(mktemp)"
excluded="$(mktemp)"
finding_body="$(mktemp)"
endpoints="$(mktemp)"
listen="$(mktemp)"
svcmap="$(mktemp)"
trap 'rm -f "$files_list" "$all_proj" "$deploy" "$refs" "$modules" "$extras" "$edges" "$hits" "$container_body" "$module_body" "$edge_body" "$excluded" "$finding_body" "$endpoints" "$listen" "$svcmap"' EXIT

git -C "$root" ls-tree -r --name-only -z HEAD | tr '\0' '\n' | LC_ALL=C sort >"$files_list"
dirty_n="$(git -C "$root" --no-optional-locks status --porcelain --untracked-files=no 2>/dev/null | awk 'END { print NR }')"

has_project() {
  awk -v id="$1" '$0 == id { found = 1 } END { exit !found }' "$all_proj"
}

is_deployable() {
  awk -F'\t' -v id="$1" '$1 == id { found = 1 } END { exit !found }' "$deploy"
}

while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -n "$rel" ]] || continue
  case "$rel" in
  */obj/* | */bin/*) continue ;;
  *.csproj | *.fsproj) ;;
  *) continue ;;
  esac
  printf '%s\n' "$rel" >>"$all_proj"
done <"$files_list"

while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -n "$rel" ]] || continue
  abs="$root/$rel"
  [[ -f "$abs" && ! -L "$abs" ]] || continue
  base="${rel##*/}"
  name="${base%.*}"
  dir="${rel%/*}"
  [[ "$dir" == "$rel" ]] && dir=""
  sdk="$(awk '
    {
      line = $0
      sub(/\r$/, "", line)
      if (match(line, /Sdk="[^"]*"/)) {
        s = substr(line, RSTART, RLENGTH)
        sub(/^Sdk="/, "", s)
        sub(/"$/, "", s)
        print s
        exit
      }
    }
  ' "$abs")"
  output_type="$(awk '
    {
      line = tolower($0)
      sub(/\r$/, "", line)
      if (match(line, /<outputtype>[^<]*<\/outputtype>/)) {
        s = substr(line, RSTART, RLENGTH)
        sub(/^<outputtype>/, "", s)
        sub(/<\/outputtype>$/, "", s)
        print s
        exit
      }
    }
  ' "$abs")"
  tfm="$(awk '
    {
      line = $0
      sub(/\r$/, "", line)
      if (match(line, /<TargetFrameworks?>[^<]*<\/TargetFrameworks?>/)) {
        s = substr(line, RSTART, RLENGTH)
        sub(/^<TargetFrameworks?>/, "", s)
        sub(/<\/TargetFrameworks?>$/, "", s)
        split(s, parts, ";")
        print parts[1]
        exit
      }
    }
  ' "$abs")"
  functions=0
  if [[ "$sdk" == Microsoft.NET.Sdk.Functions || "$sdk" == Microsoft.NET.Sdk.Functions/* ]]; then
    functions=1
  fi
  if awk 'BEGIN { found = 0 } /<AzureFunctionsVersion>/ { found = 1 } END { exit found ? 0 : 1 }' "$abs"; then
    functions=1
  fi
  web_builder=0
  generic_host=0
  api_marker=0
  candidate=0
  if [[ "$functions" -eq 1 || "$sdk" == Microsoft.NET.Sdk.Web || "$sdk" == Microsoft.NET.Sdk.Web/* || "$sdk" == Microsoft.NET.Sdk.Worker || "$sdk" == Microsoft.NET.Sdk.Worker/* || "$output_type" == "exe" || "$output_type" == "winexe" ]]; then
    candidate=1
  fi
  if [[ "$candidate" -eq 1 ]] && dotnet_is_test_project "$abs"; then
    printf '%s\n' "$rel" >>"$excluded"
    continue
  fi
  if [[ "$candidate" -eq 1 ]]; then
    while IFS= read -r src || [[ -n "$src" ]]; do
      case "$src" in
      *.cs | *.fs | *.vb) ;;
      *) continue ;;
      esac
      if [[ -n "$dir" ]]; then
        [[ "$src" == "$dir"/* ]] || continue
      fi
      src_abs="$root/$src"
      [[ -f "$src_abs" && ! -L "$src_abs" ]] || continue
      if grep -q -F 'WebApplication.CreateBuilder' "$src_abs"; then
        web_builder=1
      fi
      if grep -q -E -e 'Host\.CreateDefaultBuilder' -e 'Host\.CreateApplicationBuilder' "$src_abs"; then
        generic_host=1
      fi
      if grep -q -E -e 'ApiController' -e 'MapGet\(' -e 'MapPost\(' -e 'MapPut\(' -e 'MapDelete\(' -e 'MapControllers\(' "$src_abs"; then
        api_marker=1
      fi
    done <"$files_list"
  fi
  kind=""
  if [[ "$functions" -eq 1 ]]; then
    kind="function"
  elif [[ "$sdk" == Microsoft.NET.Sdk.Web || "$sdk" == Microsoft.NET.Sdk.Web/* || "$web_builder" -eq 1 ]]; then
    if [[ "$api_marker" -eq 1 ]]; then
      kind="api"
    else
      kind="web"
    fi
  elif [[ "$sdk" == Microsoft.NET.Sdk.Worker || "$sdk" == Microsoft.NET.Sdk.Worker/* || "$generic_host" -eq 1 ]]; then
    kind="worker"
  elif [[ "$output_type" == "exe" || "$output_type" == "winexe" ]]; then
    kind="cli"
  fi
  [[ -n "$kind" ]] || continue
  case "$kind" in
  web | api) tech_base="ASP.NET Core" ;;
  worker) tech_base=".NET Worker" ;;
  function) tech_base="Azure Functions" ;;
  cli) tech_base=".NET" ;;
  *) tech_base="unknown" ;;
  esac
  if [[ -n "$tfm" && "$tech_base" != "unknown" ]]; then
    technology="$tech_base ($tfm)"
  else
    technology="$tech_base"
  fi
  evidence="$rel: Sdk=${sdk:-unknown}"
  [[ -n "$output_type" ]] && evidence="$evidence; $rel: OutputType=$output_type"
  [[ "$web_builder" -eq 1 ]] && evidence="$evidence; $rel: WebApplication.CreateBuilder"
  [[ "$generic_host" -eq 1 ]] && evidence="$evidence; $rel: Host.CreateDefaultBuilder"
  [[ "$api_marker" -eq 1 ]] && evidence="$evidence; $rel: api-endpoint"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$name" "$kind" "$technology" "$evidence" "$dir" >>"$deploy"
done <"$all_proj"

containment="project-references"
if [[ -n "$graph_file" ]]; then
  containment="dependency-graph.json"
  grep -q '"schema_version"[[:space:]]*:[[:space:]]*1' "$graph_file" ||
    die "graph is not schema_version 1: $graph_file" 1
  graph_problem="$(awk '
    function open_array(key,   rest) {
      if (!match($0, "\"" key "\"[[:space:]]*:[[:space:]]*\\[")) return
      rest = substr($0, RSTART + RLENGTH)
      if (rest ~ /^[[:space:]]*\]/) { seen[key] = 1; return }
      if (substr($0, 1, RSTART - 1) ~ /^[[:space:]]*$/ && rest ~ /^[[:space:]]*$/) { open = key; return }
      problem = "the " key " array does not start on a line of its own"
    }
    BEGIN { shape["edges"] = "^[[:space:]]*[{]\"from\":" }
    open != "" {
      if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) { seen[open] = 1; open = ""; next }
      if ($0 !~ shape[open]) { problem = "line " NR " is not one edges object"; exit }
      next
    }
    { open_array("edges"); if (problem != "") exit }
    END {
      if (problem == "" && open != "") problem = "the edges array never closes"
      if (problem == "" && !("edges" in seen)) problem = "no edges array was found"
      print problem
    }
  ' "$graph_file")"
  [[ -z "$graph_problem" ]] || die "graph is not one object per line ($graph_problem): $graph_file" 1
  awk '
    function jstr(line, key,    pat, i, rest, out, c, n) {
      pat = "\"" key "\""
      i = index(line, pat)
      if (i == 0) return ""
      rest = substr(line, i + length(pat))
      if (!sub(/^[[:space:]]*:[[:space:]]*"/, "", rest)) return ""
      out = ""
      n = length(rest)
      i = 1
      while (i <= n) {
        c = substr(rest, i, 1)
        if (c == "\\") {
          i++
          c = substr(rest, i, 1)
          if (c == "n") out = out "\n"
          else if (c == "t") out = out "\t"
          else out = out c
          i++
          continue
        }
        if (c == "\"") return out
        out = out c
        i++
      }
      return out
    }
    /^[[:space:]]*\{"from":/ {
      kind = jstr($0, "kind")
      if (kind != "project" || jstr($0, "status") == "unresolved") next
      from = jstr($0, "from")
      to = jstr($0, "to")
      ev = jstr($0, "evidence")
      if (from != "" && to != "") printf "%s\t%s\t%s\n", from, to, ev
    }
  ' "$graph_file" >"$refs"
else
  while IFS= read -r id || [[ -n "$id" ]]; do
    [[ -n "$id" ]] || continue
    dir="${id%/*}"
    [[ "$dir" == "$id" ]] && dir=""
    while IFS=$'\t' read -r ref_kind include decl; do
      [[ "$ref_kind" == "project" && -n "$include" ]] || continue
      case "$include" in
      *'*'* | *'?'* | /* | [A-Za-z]:*) continue ;;
      *) ;;
      esac
      if [[ -n "$dir" ]]; then
        joined="$dir/${include//\\//}"
      else
        joined="${include//\\//}"
      fi
      if ! resolved="$(normalize_inside "$joined")"; then
        continue
      fi
      has_project "$resolved" || continue
      printf '%s\t%s\t%s: %s\n' "$id" "$resolved" "$id" "$decl" >>"$refs"
    done < <(dotnet_reference_records "$root/$id")
  done <"$all_proj"
fi

declare -A seen_mod=()
queue="$(mktemp)"
while IFS=$'\t' read -r id _rest; do
  [[ -n "$id" ]] || continue
  printf '%s\t%s\n' "$id" "$id" >>"$queue"
done <"$deploy"
while IFS=$'\t' read -r origin_id current || [[ -n "$origin_id" ]]; do
  [[ -n "$origin_id" ]] || continue
  while IFS=$'\t' read -r to ev; do
    [[ -n "$to" ]] || continue
    is_deployable "$to" && continue
    has_project "$to" || continue
    mark="$origin_id|$to"
    [[ -n "${seen_mod[$mark]+x}" ]] && continue
    seen_mod["$mark"]=1
    mod_name="$(basename "$to")"
    mod_name="${mod_name%.*}"
    printf '%s\t%s\t%s\t%s\n' "$origin_id" "$mod_name" "$to" "$ev" >>"$modules"
    printf '%s\t%s\n' "$origin_id" "$to" >>"$queue"
  done < <(awk -F'\t' -v cur="$current" '$1 == cur { printf "%s\t%s\n", $2, $3 }' "$refs")
done <"$queue"
rm -f "$queue"

while IFS= read -r rel || [[ -n "$rel" ]]; do
  base="$(basename "$rel")"
  case "$base" in
  Dockerfile | *.Dockerfile) ;;
  *) continue ;;
  esac
  abs="$root/$rel"
  [[ -f "$abs" && ! -L "$abs" ]] || continue
  # The last FROM is the image that ships. Leading --flag tokens are options, a
  # name that is an earlier stage resolves to that stage's image, and a variable
  # is not an image name, so the image is unknown.
  image="$(awk '
    {
      line = $0
      sub(/\r$/, "", line)
      if (tolower(line) ~ /^from[[:space:]]+/) {
        sub(/^[Ff][Rr][Oo][Mm][[:space:]]+/, "", line)
        while (line ~ /^--[^[:space:]]*[[:space:]]+/) sub(/^--[^[:space:]]*[[:space:]]+/, "", line)
        n = split(line, w, /[[:space:]]+/)
        img = w[1]
        if (img == "") next
        if (index(img, "$") > 0) img = "unknown"
        else if (tolower(img) in stage) img = stage[tolower(img)]
        if (n >= 3 && tolower(w[2]) == "as") stage[tolower(w[3])] = img
        last = img
      }
    }
    END { if (last != "") print last }
  ' "$abs")"
  image="${image%%@*}"
  attached=""
  best_len=-1
  while IFS=$'\t' read -r id _name _kind _tech _ev dir; do
    [[ -n "$id" ]] || continue
    len=-1
    if [[ -n "$dir" && "$rel" == "$dir"/* ]]; then
      len=${#dir}
    fi
    if [[ "$len" -gt "$best_len" ]]; then
      attached="$id"
      best_len=$len
    fi
  done <"$deploy"
  if [[ -n "$attached" ]]; then
    extra="$rel: Dockerfile"
    [[ -n "$image" ]] && extra="$extra FROM $image"
    awk -F'\t' -v id="$attached" -v extra="$extra" 'BEGIN { OFS="\t" }
      $1 == id { $5 = $5 "; " extra }
      { print }
    ' "$deploy" >"$deploy.tmp"
    mv "$deploy.tmp" "$deploy"
    continue
  fi
  image_l="$(printf '%s' "$image" | tr '[:upper:]' '[:lower:]')"
  kind="process"
  [[ "$image_l" == *aspnet* ]] && kind="api"
  tech="$image"
  [[ -n "$tech" ]] || tech="unknown"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$base" "$kind" "$tech" "-" "$rel: Dockerfile" >>"$extras"
done <"$files_list"

while IFS= read -r rel || [[ -n "$rel" ]]; do
  base="$(basename "$rel")"
  case "$base" in
  docker-compose.yml | docker-compose.yaml | compose.yml | compose.yaml) ;;
  *) continue ;;
  esac
  abs="$root/$rel"
  [[ -f "$abs" && ! -L "$abs" ]] || continue
  parsed="$(mktemp)"
  awk '
    function flush() {
      if (name == "") return
      gsub(/\047/, "", image)
      gsub(/"/, "", image)
      gsub(/\047/, "", build)
      gsub(/"/, "", build)
      printf "%s\034%s\034%s\034%s\n", name, image, build, ports
    }
    function add_port(p) {
      gsub(/\r/, "", p)
      gsub(/["\047[:space:]]/, "", p)
      sub(/\/[A-Za-z]+$/, "", p)
      sub(/^.*:/, "", p)
      if (p ~ /^[0-9]+$/) ports = ports (ports == "" ? "" : ",") p
    }
    /^services:[[:space:]]*$/ { in_s = 1; next }
    in_s && /^[^ \t#]/ { flush(); exit }
    in_s && /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ {
      flush()
      name = $0
      sub(/^  /, "", name)
      sub(/:[[:space:]]*$/, "", name)
      image = ""
      build = ""
      ports = ""
      in_ports = 0
      next
    }
    in_s && /^    [A-Za-z_]+:/ {
      key = $0
      sub(/^    /, "", key)
      sub(/:.*$/, "", key)
      in_ports = (key == "ports" || key == "expose")
    }
    in_s && in_ports && /^      -[[:space:]]+[^[:space:]#]/ {
      item = $0
      sub(/^      -[[:space:]]+/, "", item)
      sub(/[[:space:]]+#.*$/, "", item)
      if (item !~ /^[A-Za-z_]+:[[:space:]]/ || item ~ /^target:/) add_port(item)
    }
    in_s && in_ports && /^        target:[[:space:]]*[0-9]/ {
      item = $0
      sub(/^        target:[[:space:]]*/, "", item)
      add_port(item)
    }
    in_s && /^    image:[[:space:]]*/ {
      image = $0
      sub(/^    image:[[:space:]]*/, "", image)
      gsub(/\r/, "", image)
    }
    in_s && /^    build:[[:space:]]*[^[:space:]]/ {
      build = $0
      sub(/^    build:[[:space:]]*/, "", build)
      gsub(/\r/, "", build)
    }
    in_s && /^      context:[[:space:]]*/ {
      build = $0
      sub(/^      context:[[:space:]]*/, "", build)
      gsub(/\r/, "", build)
    }
    END { flush() }
  ' "$abs" >"$parsed"
  # Unit separator, not tab: bash read collapses empty tab fields, and a service
  # with a build and no image would slide the build into the image.
  while IFS=$'\034' read -r svc image build ports; do
    [[ -n "$svc" ]] || continue
    context="${build#./}"
    context="${context%/}"
    matched=""
    match_n=0
    while IFS=$'\t' read -r id _name _kind _tech _ev dir; do
      if [[ -n "$context" && "$dir" == "$context" ]]; then
        matched="$id"
        match_n=$((match_n + 1))
      fi
    done <"$deploy"
    if [[ "$match_n" -eq 1 ]]; then
      svc_host="$(printf '%s' "$svc" | tr '[:upper:]' '[:lower:]')"
      printf '%s\034%s\034%s\034%s\n' "$svc_host" "$matched" "$ports" "$rel: service $svc build $context" >>"$svcmap"
      awk -F'\t' -v id="$matched" -v extra="$rel: service $svc" 'BEGIN { OFS="\t" }
        $1 == id { $5 = $5 "; " extra }
        { print }
      ' "$deploy" >"$deploy.tmp"
      mv "$deploy.tmp" "$deploy"
      continue
    fi
    leaf="$(printf '%s' "$image" | tr '[:upper:]' '[:lower:]')"
    leaf="${leaf%%@*}"
    leaf="${leaf%%:*}"
    leaf="${leaf##*/}"
    case "$leaf" in
    postgres | mysql | mariadb | mssql | mongo | mongodb)
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "store:image:$rel:$svc" "$svc" "store" "${image:-unknown}" "sql" "$rel: image ${image:-unknown}" >>"$extras"
      ;;
    redis)
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "store:image:$rel:$svc" "$svc" "store" "${image:-unknown}" "cache" "$rel: image ${image:-unknown}" >>"$extras"
      ;;
    elasticsearch | opensearch)
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "store:image:$rel:$svc" "$svc" "store" "${image:-unknown}" "search" "$rel: image ${image:-unknown}" >>"$extras"
      ;;
    rabbitmq | nats | kafka)
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "store:image:$rel:$svc" "$svc" "store" "${image:-unknown}" "broker" "$rel: image ${image:-unknown}" >>"$extras"
      ;;
    "")
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "manifest:$rel:$svc" "$svc" "process" "unknown" "-" "$rel: service $svc" >>"$extras"
      ;;
    *)
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "manifest:$rel:$svc" "$svc" "process" "$image" "-" "$rel: image $image" >>"$extras"
      ;;
    esac
  done <"$parsed"
  rm -f "$parsed"
done <"$files_list"

while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -n "$rel" ]] || continue
  abs="$root/$rel"
  [[ -f "$abs" && ! -L "$abs" ]] || continue
  base="$(basename "$rel")"
  is_family_record "$base" && continue
  case "$base" in
  package.json | package-lock.json | npm-shrinkwrap.json)
    continue
    ;;
  *) ;;
  esac
  bytes="$(wc -c <"$abs" | tr -d ' ')"
  [[ "$bytes" -le 524288 ]] || continue
  mode=""
  if [[ "$base" == *.json ]]; then
    mode="json"
  elif [[ "$base" == *.yml || "$base" == *.yaml ]]; then
    mode="yaml"
  elif [[ "$base" == *.xml || "$base" == *.config ]]; then
    mode="xml"
  elif [[ "$base" == *.tf || "$base" == *.tfvars || "$base" == *.bicep || "$base" == *.toml ]]; then
    mode="hcl"
  elif [[ "$base" == *.properties || "$base" == *.ini || "$base" == *.conf ]]; then
    mode="ini"
  elif [[ "$base" == *.env || "$base" == .env || "$base" == .env.* ]]; then
    mode="env"
  fi
  [[ -n "$mode" ]] || continue
  ASSIGN_MODE="$mode" awk -v redact_local_http=1 -f "$REDACT_AWK" -f "$ASSIGN_AWK" "$abs" |
    awk -F'\t' -v rel="$rel" -v endpoints="$endpoints" -v listen="$listen" '
      $1 != "" && $2 != "" && $4 != "" {
        kind = $1
        if (kind == "http") {
          if ($6 != "http" && $6 != "https") next
          leaf = tolower($4)
          n = split(leaf, seg, /[.:]/)
          leaf = seg[n]
          gsub(/[^a-z0-9]/, "", leaf)
          if ($2 ~ /\.search\.windows\.net$|\.es\.amazonaws\.com$|\.aoss\.amazonaws\.com$|\.elastic-cloud\.com$|\.found\.io$/ ||
              leaf ~ /elasticsearch|opensearch|searchendpoint|searchservice/) kind = "search"
        }
        if (kind == "http") {
          if ($3 !~ /^[0-9]*$/) next
          if (rel ~ /(^|\/)Properties\/launchSettings\.json$/ && tolower($4) ~ /(^|\.)applicationurl$/) {
            if ($3 != "" && ($2 == "localhost" || $2 == "127.0.0.1")) printf "%s\t%s\t%s\t%s\n", $2, $3, rel, $4 >> listen
          } else printf "%s\t%s\t%s\t%s\t%s\n", $2, $3, rel, $4, $6 >> endpoints
          next
        }
        if (kind !~ /^(sql|storage|broker|cache|search)$/) next
        if ($2 ~ /[^a-z0-9.-]/ || index($2, ".") == 0 || index($2, "..") > 0) next
        if ($3 != "" && $3 !~ /^[0-9]+$/) next
        db = $5
        scheme = $6
        if (kind != "sql" || db !~ /^[a-z0-9_.-]+$/) db = ""
        if (kind != "sql" || scheme !~ /^[a-z][a-z0-9]*$/) scheme = ""
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", kind, $2, $3, rel, $4, db, scheme
      }
    ' >>"$hits"
done <"$files_list"

if [[ -s "$hits" ]]; then
  LC_ALL=C sort -u "$hits" >"$hits.sorted"
  mv "$hits.sorted" "$hits"
fi

bind_deployable() {
  local file="$1" best="" best_len=-1 id dir len
  while IFS=$'\t' read -r id _name _kind _tech _ev dir; do
    [[ -n "$id" ]] || continue
    if [[ -z "$dir" ]]; then
      len=0
    elif [[ "$file" == "$dir"/* ]]; then
      len=${#dir}
    else
      continue
    fi
    if [[ "$len" -gt "$best_len" ]]; then
      best="$id"
      best_len=$len
    fi
  done <"$deploy"
  printf '%s' "$best"
}

store_technology() {
  local kind="$1" host="$2" scheme="$3"
  case "$kind" in
  sql)
    case "$host" in
    *.database.windows.net) printf 'Azure SQL' ;;
    *) printf '%s' "${scheme:-unknown}" ;;
    esac
    ;;
  broker)
    case "$host" in
    *.servicebus.windows.net) printf 'Azure Service Bus' ;;
    *) printf 'message broker' ;;
    esac
    ;;
  cache)
    case "$host" in
    *redis*) printf 'Redis' ;;
    *) printf 'cache' ;;
    esac
    ;;
  storage) printf 'Azure Blob Storage' ;;
  search)
    case "$host" in
    *.search.windows.net) printf 'Azure AI Search' ;;
    *.es.amazonaws.com | *.aoss.amazonaws.com) printf 'OpenSearch' ;;
    *.elastic-cloud.com | *.found.io) printf 'Elasticsearch' ;;
    *) printf 'unknown' ;;
    esac
    ;;
  *) printf 'unknown' ;;
  esac
}

# Unit separator, not tab: bash read collapses empty tab fields, and a blank
# port would slide the file path into the port.
if [[ -s "$hits" ]]; then
  while IFS=$'\034' read -r skind host port file key db scheme; do
    [[ -n "$host" ]] || continue
    owner="$(bind_deployable "$file")"
    sid="store:${skind}:${host}:${port}"
    [[ "$skind" == sql ]] && sid="$sid:${db:-database unknown}"
    printf '%s\036%s\036%s\036%s\036%s\036%s\036%s\036%s\n' "$sid" "$skind" "$host" "$owner" "$file: $key" "$scheme" "$port" "$db"
  done < <(awk -F'\t' '{ printf "%s\034%s\034%s\034%s\034%s\034%s\034%s\n", $1, $2, $3, $4, $5, $6, $7 }' "$hits") >"$hits.grouped"
else
  : >"$hits.grouped"
fi

# Every pair of owners of one store is one shared-infrastructure edge, and each
# cites the config keys of both owners.
if [[ -s "$hits.grouped" ]]; then
  while IFS= read -r sid; do
    [[ -n "$sid" ]] || continue
    IFS=$'\036' read -r skind host db scheme < <(awk -F'\036' -v sid="$sid" '
      $1 == sid { if (kind == "") { kind = $2; host = $3; db = $8 } if (scheme == "") scheme = $6 }
      END { printf "%s\036%s\036%s\036%s\n", kind, host, db, scheme }
    ' "$hits.grouped")
    name="$host"
    if [[ "$skind" == sql ]]; then
      name="$host (database unknown)"
      [[ -z "$db" ]] || name="$host/$db"
    fi
    tech="$(store_technology "$skind" "$host" "$scheme")"
    cites="$(awk -F'\036' -v sid="$sid" '$1 == sid { print $5 }' "$hits.grouped" | LC_ALL=C sort -u | awk 'BEGIN { ORS="" } { if (n++) printf "; "; printf "%s", $0 }')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sid" "$name" "store" "$tech" "$skind" "$cites" >>"$extras"
    awk -F'\036' -v sid="$sid" '$1 == sid && $4 != "" { printf "%s\t%s\tuses\t-\t%s\n", $4, sid, $5 }' "$hits.grouped" |
      LC_ALL=C sort -u >>"$edges"
    note=""
    [[ "$skind" == sql && -z "$db" ]] && note="same server, database unknown: "
    LC_ALL=C awk -F'\036' -v sid="$sid" -v note="$note" '
      $1 == sid && $4 != "" {
        if (!($4 in cites)) owners[++n] = $4
        if (!(($4 SUBSEP $5) in seen)) {
          seen[$4 SUBSEP $5] = 1
          cites[$4] = cites[$4] (cites[$4] == "" ? "" : "; ") $5
        }
      }
      END {
        for (i = 2; i <= n; i++) {
          v = owners[i]
          for (j = i - 1; j >= 1 && owners[j] > v; j--) owners[j + 1] = owners[j]
          owners[j + 1] = v
        }
        for (i = 1; i <= n; i++)
          for (j = i + 1; j <= n; j++)
            printf "%s\t%s\tshared-infrastructure\t%s\t%s%s; %s\n", owners[i], owners[j], sid, note, cites[owners[i]], cites[owners[j]]
      }
    ' "$hits.grouped" >>"$edges"
  done < <(awk -F'\036' '{ print $1 }' "$hits.grouped" | LC_ALL=C sort -u)
fi
rm -f "$hits.grouped"

# An endpoint a deployable's own config names is an edge to another deployable
# only through a cited fact: a compose service whose build context is that
# deployable's directory (host equals the service name, and a declared port equals
# the endpoint's), or a launchSettings applicationUrl on that deployable (loopback
# host and the same port). Nothing is matched by a name's resemblance. An endpoint
# that resolves to no deployable or to several draws no edge and is a finding.
if [[ -s "$listen" ]]; then
  while IFS=$'\t' read -r _host lport lfile lkey; do
    parent="${lfile%Properties/launchSettings.json}"
    parent="${parent%/}"
    while IFS=$'\t' read -r id _name _kind _tech _ev dir; do
      [[ -n "$id" && "$dir" == "$parent" ]] || continue
      printf '%s\t%s\t%s: %s\n' "$id" "$lport" "$lfile" "$lkey" >>"$listen.map"
    done <"$deploy"
  done <"$listen"
fi
if [[ -s "$endpoints" ]]; then
  ep_edges="$(mktemp)"
  while IFS=$'\034' read -r host port file key scheme; do
    owner="$(bind_deployable "$file")"
    [[ -n "$owner" ]] || continue
    targets="$(
      awk -F'\034' -v host="$host" -v port="$port" -v scheme="$scheme" '
        $1 == host {
          ok = ($3 == "")
          n = split($3, p, ",")
          for (i = 1; i <= n; i++) if (p[i] == (port == "" ? (scheme == "https" ? 443 : 80) : port)) ok = 1
          if (ok) printf "%s\t%s\n", $2, $4
        }' "$svcmap"
      if [[ ( "$host" == localhost || "$host" == 127.0.0.1 ) && -s "$listen.map" ]]; then
        awk -F'\t' -v port="$port" 'port != "" && $2 == port { printf "%s\t%s\n", $1, $3 }' "$listen.map"
      fi
    )"
    target_n="$(printf '%s\n' "$targets" | awk -F'\t' 'NF && !($1 in seen) { seen[$1] = 1; n++ } END { print n + 0 }')"
    if [[ "$target_n" -eq 1 ]]; then
      target="${targets%%$'\t'*}"
      [[ "$target" == "$owner" ]] && continue
      printf '%s\n' "$targets" | awk -F'\t' -v owner="$owner" -v cite="$file: $key" 'NF { printf "%s\t%s\t%s\t%s\n", owner, $1, cite, $2 }' >>"$ep_edges"
      continue
    fi
    shown="$host"
    [[ -z "$port" ]] || shown="$host:$port"
    why="resolves to no deployable in this repository"
    [[ "$target_n" -gt 1 ]] && why="matches more than one deployable"
    json_escape "$file: $key names host $shown; $why"
    printf '{"kind":"external-endpoint","count":1,"evidence":"%s"}\n' "$JSON_ESC" >>"$finding_body"
  done < <(LC_ALL=C sort -u "$endpoints" | awk -F'\t' '{ printf "%s\034%s\034%s\034%s\034%s\n", $1, $2, $3, $4, $5 }')
  if [[ -s "$ep_edges" ]]; then
    LC_ALL=C sort -u "$ep_edges" | LC_ALL=C awk -F'\t' '
      {
        k = $1 SUBSEP $2
        if (!(k in from)) { order[++n] = k; from[k] = $1; to[k] = $2 }
        if (!((k SUBSEP $3) in seen_cfg)) { seen_cfg[k SUBSEP $3] = 1; cfg[k] = cfg[k] (cfg[k] == "" ? "" : "; ") $3 }
        if (!((k SUBSEP $4) in seen_res)) { seen_res[k SUBSEP $4] = 1; res[k] = res[k] (res[k] == "" ? "" : "; ") $4 }
      }
      END {
        for (i = 1; i <= n; i++) printf "%s\t%s\tuses\t-\t%s; %s\n", from[order[i]], to[order[i]], cfg[order[i]], res[order[i]]
      }
    ' >>"$edges"
  fi
  rm -f "$ep_edges"
fi
rm -f "$listen.map"

emit_container() {
  local id="$1" name="$2" kind="$3" technology="$4" store_kind="$5" evidence="$6" summary="$7"
  json_escape "$id"
  local obj="{\"id\":\"$JSON_ESC\""
  json_escape "$name"
  obj="$obj,\"name\":\"$JSON_ESC\""
  json_escape "$kind"
  obj="$obj,\"kind\":\"$JSON_ESC\""
  json_escape "$technology"
  obj="$obj,\"technology\":\"$JSON_ESC\""
  json_escape "$store_kind"
  obj="$obj,\"store_kind\":\"$JSON_ESC\""
  json_escape "$summary"
  obj="$obj,\"summary\":\"$JSON_ESC\""
  json_escape "$evidence"
  obj="$obj,\"evidence\":\"$JSON_ESC\"}"
  printf '%s\n' "$obj"
}

while IFS=$'\t' read -r id name kind technology evidence _dir; do
  [[ -n "$id" ]] || continue
  summary="$(awk -F'\t' -v id="$id" '$1 == id { print $2 }' "$modules" | LC_ALL=C sort -u | awk 'BEGIN { ORS="" } { if (n++) printf ", "; printf "%s", $0 }')"
  if [[ -n "$summary" ]]; then
    summary="Contains: $summary"
  fi
  emit_container "$id" "$name" "$kind" "$technology" "" "$evidence" "$summary"
done <"$deploy" >>"$container_body"

while IFS=$'\t' read -r id name kind technology store_kind evidence; do
  [[ -n "$id" ]] || continue
  [[ "$store_kind" == "-" ]] && store_kind=""
  emit_container "$id" "$name" "$kind" "$technology" "$store_kind" "$evidence" ""
done <"$extras" >>"$container_body"

if [[ -s "$container_body" ]]; then
  LC_ALL=C sort -u "$container_body" >"$container_body.sorted"
  mv "$container_body.sorted" "$container_body"
fi

if [[ -s "$modules" ]]; then
  LC_ALL=C sort -u "$modules" | while IFS=$'\t' read -r container name path evidence; do
    json_escape "$container"
    obj="{\"container\":\"$JSON_ESC\""
    json_escape "$name"
    obj="$obj,\"name\":\"$JSON_ESC\""
    json_escape "$path"
    obj="$obj,\"path\":\"$JSON_ESC\""
    json_escape "$evidence"
    obj="$obj,\"evidence\":\"$JSON_ESC\"}"
    printf '%s\n' "$obj"
  done >"$module_body"
fi

if [[ -s "$edges" ]]; then
  LC_ALL=C sort -u "$edges" | while IFS=$'\t' read -r from to kind via evidence; do
    [[ -n "$from" && -n "$to" ]] || continue
    [[ "$via" == "-" ]] && via=""
    json_escape "$from"
    obj="{\"from\":\"$JSON_ESC\""
    json_escape "$to"
    obj="$obj,\"to\":\"$JSON_ESC\""
    json_escape "$kind"
    obj="$obj,\"kind\":\"$JSON_ESC\""
    json_escape "$via"
    obj="$obj,\"via\":\"$JSON_ESC\""
    json_escape "$evidence"
    obj="$obj,\"evidence\":\"$JSON_ESC\"}"
    printf '%s\n' "$obj"
  done >"$edge_body"
fi

if [[ "$dirty_n" -gt 0 ]]; then
  printf 'collect-containers.sh: %d tracked file(s) differ from HEAD; their contents are read from the working tree\n' "$dirty_n" >&2
  printf '{"kind":"dirty-tracked-files","count":%d,"evidence":"%d tracked file(s) differ from HEAD; their contents are read from the working tree"}\n' "$dirty_n" "$dirty_n" >>"$finding_body"
fi
excluded_n="$(awk 'END { print NR }' "$excluded")"
if [[ "$excluded_n" -gt 0 ]]; then
  json_escape "$(LC_ALL=C sort "$excluded" | awk 'BEGIN { ORS="" } { if (n++) printf "; "; printf "%s", $0 }')"
  printf '{"kind":"excluded-test-projects","count":%d,"evidence":"not charted as deployables: %s"}\n' "$excluded_n" "$JSON_ESC" >>"$finding_body"
fi

emit_lines() {
  local key="$1" file="$2" comma="$3"
  if [[ ! -s "$file" ]]; then
    printf '  "%s": []%s\n' "$key" "$comma"
    return
  fi
  printf '  "%s": [\n' "$key"
  awk '
    NF { lines[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) printf "    %s%s\n", lines[i], (i < n ? "," : "")
    }
  ' "$file"
  printf '  ]%s\n' "$comma"
}

record_body="$(
  json_escape "$generated_on"
  printf '{\n  "schema_version": 1,\n  "generated_on": "%s",\n' "$JSON_ESC"
  json_escape "$subject"
  printf '  "subject": "%s",\n' "$JSON_ESC"
  json_escape "$focal"
  printf '  "focal": "%s",\n' "$JSON_ESC"
  json_escape "$containment"
  printf '  "containment": "%s",\n' "$JSON_ESC"
  emit_lines containers "$container_body" ","
  emit_lines modules "$module_body" ","
  emit_lines edges "$edge_body" ","
  emit_lines findings "$finding_body" ""
  printf '}\n'
)"

if [[ -n "$out_file" ]]; then
  printf '%s\n' "$record_body" >"$out_file" || die "cannot write --out file: $out_file" 1
else
  printf '%s\n' "$record_body"
fi
exit 0
