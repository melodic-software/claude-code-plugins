#!/usr/bin/env bash
# Render containers.json. The record is the fact. A reformatted record exits 1
# and writes nothing. diagram_dialect.system is likec4 or c4-plantuml. Mermaid
# is not a value of that key. Unset writes the fact report and no C4 view.
#
# Usage:
#   render-containers.sh --record <file> --out <dir>
#       [--dialect unset|c4-plantuml|likec4] [--convention-home <dir>]
#       [--node-threshold <N>]
#   render-containers.sh --help
#
# Summary line:
#   containers: deployables=<n> stores=<n> brokers=<n> modules=<n> binds=<n>
#   shared=<n> thin=<yes|no> dialect=<...> aggregated=<yes|no>
#
# Exit: 0 written; 1 unreadable or wrong layout (nothing written); 2 usage.
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'render-containers.sh: %s\n' "$1" >&2
  exit "$2"
}

record=""
outdir=""
dialect=""
convention_home=""
threshold_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h) usage; exit 0 ;;
  --record) [[ $# -ge 2 ]] || die "--record needs a path" 2; record="$2"; shift 2 ;;
  --record=*) record="${1#--record=}"; shift ;;
  --out) [[ $# -ge 2 ]] || die "--out needs a directory" 2; outdir="$2"; shift 2 ;;
  --out=*) outdir="${1#--out=}"; shift ;;
  --dialect) [[ $# -ge 2 ]] || die "--dialect needs a value" 2; dialect="$2"; shift 2 ;;
  --dialect=*) dialect="${1#--dialect=}"; shift ;;
  --convention-home) [[ $# -ge 2 ]] || die "--convention-home needs a directory" 2; convention_home="$2"; shift 2 ;;
  --convention-home=*) convention_home="${1#--convention-home=}"; shift ;;
  --node-threshold) [[ $# -ge 2 ]] || die "--node-threshold needs a whole number" 2; threshold_override="$2"; shift 2 ;;
  --node-threshold=*) threshold_override="${1#--node-threshold=}"; shift ;;
  *) die "unknown argument: $1" 2 ;;
  esac
done

[[ -n "$record" && -n "$outdir" ]] || { usage >&2; exit 2; }
if [[ -n "$threshold_override" ]]; then
  case "$threshold_override" in
  '' | *[!0-9]*) die "--node-threshold needs a whole number, got: $threshold_override" 2 ;;
  esac
fi

read_dialect() {
  local home="$1" file line fence=0 in_diagram=0 value
  file="$home/authoring-formats/README.md"
  [[ -f "$file" ]] || { printf 'unset'; return; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
    '```yaml' | '```yml') fence=1; in_diagram=0; continue ;;
    '```') fence=0; in_diagram=0; continue ;;
    esac
    [[ $fence -eq 1 ]] || continue
    case "$line" in
    diagram_dialect:*) in_diagram=1 ;;
    system:*)
      [[ $in_diagram -eq 1 ]] || continue
      value="${line#system:}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%%#*}"
      value="${value%"${value##*[![:space:]]}"}"
      value="${value#\"}"
      value="${value%\"}"
      [[ -n "$value" ]] || continue
      printf '%s' "$value"
      return
      ;;
    esac
  done <"$file"
  printf 'unset'
}

if [[ -z "$dialect" ]]; then
  if [[ -n "$convention_home" ]]; then
    dialect="$(read_dialect "$convention_home")"
  else
    dialect="unset"
  fi
fi
case "$dialect" in
unset | c4-plantuml | likec4) ;;
mermaid) die "mermaid is not a value of diagram_dialect.system; allowed: likec4, c4-plantuml, or unset" 2 ;;
*) die "unknown dialect: $dialect" 2 ;;
esac

[[ -r "$record" ]] || die "cannot read record: $record" 1
[[ -d "$outdir" ]] || die "not a directory: $outdir" 1
grep -q '"schema_version"[[:space:]]*:[[:space:]]*1' "$record" || die "not a schema_version 1 record: $record" 1

layout_problem="$(awk '
BEGIN {
  shape["nodes"] = "^[[:space:]]*[{]\"id\":"
  shape["modules"] = "^[[:space:]]*[{]\"container\":"
  shape["edges"] = "^[[:space:]]*[{]\"from\":"
}
function open_array(key,   rest) {
  if (!match($0, "\"" key "\"[[:space:]]*:[[:space:]]*\\[")) return
  rest = substr($0, RSTART + RLENGTH)
  if (rest ~ /^[[:space:]]*\]/) { seen[key] = 1; return }
  if (substr($0, 1, RSTART - 1) ~ /^[[:space:]]*$/ && rest ~ /^[[:space:]]*$/) { open = key; return }
  problem = "the " key " array does not start on a line of its own"
}
open != "" {
  if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) { seen[open] = 1; open = ""; next }
  if ($0 !~ shape[open]) { problem = "line " NR " is not one " open " object"; exit }
  next
}
{
  open_array("nodes")
  if (problem == "" && open == "") open_array("modules")
  if (problem == "" && open == "") open_array("edges")
  if (problem != "") exit
}
END {
  if (problem == "" && open != "") problem = "the " open " array never closes"
  if (problem == "" && !("nodes" in seen)) problem = "no nodes array was found"
  if (problem == "" && !("modules" in seen)) problem = "no modules array was found"
  if (problem == "" && !("edges" in seen)) problem = "no edges array was found"
  print problem
}
' "$record")"
[[ -z "$layout_problem" ]] ||
  die "record is not in the one-object-per-line layout collect-containers.sh writes ($layout_problem); regenerate it: $record" 1

parsed="$(awk '
function unesc(s,    i, n, c, out) {
  n = length(s); out = ""; i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") { i++; c = substr(s, i, 1); if (c == "n") out = out "\n"; else if (c == "t") out = out "\t"; else out = out c }
    else out = out c
    i++
  }
  return out
}
function field(line, want,    i, n, c, k, v, start) {
  n = length(line); i = index(line, "{"); if (i == 0) return ""; i++
  while (i <= n) {
    while (i <= n && (substr(line, i, 1) == " " || substr(line, i, 1) == ",")) i++
    if (substr(line, i, 1) == "}") return ""
    if (substr(line, i, 1) != "\"") return ""
    i++; start = i
    while (i <= n) {
      c = substr(line, i, 1)
      if (c == "\\") { i += 2; continue }
      if (c == "\"") break
      i++
    }
    k = substr(line, start, i - start); i++
    while (i <= n && (substr(line, i, 1) == " " || substr(line, i, 1) == ":")) i++
    c = substr(line, i, 1)
    if (c == "\"") {
      i++; start = i
      while (i <= n) {
        c = substr(line, i, 1)
        if (c == "\\") { i += 2; continue }
        if (c == "\"") break
        i++
      }
      v = unesc(substr(line, start, i - start)); i++
    } else {
      start = i
      while (i <= n && substr(line, i, 1) != "," && substr(line, i, 1) != "}") i++
      v = substr(line, start, i - start)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
    }
    if (k == want) return v
  }
  return ""
}
function sanitize(s) { gsub(/\t/, " ", s); gsub(/\n/, " ", s); gsub(/\r/, "", s); return s }
/^[[:space:]]*\{"id":/ {
  printf "NODE\t%s\t%s\t%s\t%s\t%s\t%s\n", sanitize(field($0, "id")), sanitize(field($0, "name")), sanitize(field($0, "kind")), sanitize(field($0, "output_kind")), sanitize(field($0, "technology")), sanitize(field($0, "evidence"))
}
/^[[:space:]]*\{"container":/ {
  printf "MODULE\t%s\t%s\t%s\t%s\n", sanitize(field($0, "container")), sanitize(field($0, "path")), sanitize(field($0, "name")), sanitize(field($0, "evidence"))
}
/^[[:space:]]*\{"from":/ {
  printf "EDGE\t%s\t%s\t%s\t%s\n", sanitize(field($0, "from")), sanitize(field($0, "to")), sanitize(field($0, "kind")), sanitize(field($0, "evidence"))
}
/^[[:space:]]*"subject"/ { printf "META\tsubject\t%s\n", sanitize(field("{" $0 "}", "subject")) }
/^[[:space:]]*"node_threshold"/ { printf "META\tnode_threshold\t%s\n", sanitize(field("{" $0 "}", "node_threshold")) }
' "$record")"

subject="unknown"
threshold=24
declare -a N_ID N_NAME N_KIND N_OUT N_TECH N_EV
declare -a M_C M_PATH M_NAME M_EV
declare -a E_FROM E_TO E_KIND E_EV
N_N=0
M_N=0
E_N=0
while IFS=$'\t' read -r tag a b c d e f; do
  [[ -n "$tag" ]] || continue
  case "$tag" in
  META)
    case "$a" in
    subject) subject="$b" ;;
    node_threshold) threshold="$b" ;;
    esac
    ;;
  NODE)
    N_ID[$N_N]="$a"; N_NAME[$N_N]="$b"; N_KIND[$N_N]="$c"; N_OUT[$N_N]="$d"
    N_TECH[$N_N]="${e:-unknown}"; [[ -n "${N_TECH[$N_N]}" ]] || N_TECH[$N_N]="unknown"
    N_EV[$N_N]="$f"; N_N=$((N_N + 1))
    ;;
  MODULE)
    M_C[$M_N]="$a"; M_PATH[$M_N]="$b"; M_NAME[$M_N]="$c"; M_EV[$M_N]="$d"; M_N=$((M_N + 1))
    ;;
  EDGE)
    E_FROM[$E_N]="$a"; E_TO[$E_N]="$b"; E_KIND[$E_N]="$c"; E_EV[$E_N]="$d"; E_N=$((E_N + 1))
    ;;
  esac
done <<<"$parsed"

[[ -n "$threshold_override" ]] && threshold="$threshold_override"
n_deploy=0; n_store=0; n_broker=0; n_bind=0; n_shared=0
for ((i = 0; i < N_N; i++)); do
  case "${N_KIND[$i]}" in
  deployable) n_deploy=$((n_deploy + 1)) ;;
  store) n_store=$((n_store + 1)) ;;
  broker) n_broker=$((n_broker + 1)) ;;
  esac
done
for ((i = 0; i < E_N; i++)); do
  case "${E_KIND[$i]}" in
  binds) n_bind=$((n_bind + 1)) ;;
  shared-infrastructure) n_shared=$((n_shared + 1)) ;;
  esac
done
thin="no"
if [[ $((n_deploy + n_store + n_broker)) -lt 2 || $((n_bind + n_shared)) -eq 0 ]]; then
  thin="yes"
fi
aggregated="no"
[[ $((n_deploy + n_store + n_broker)) -gt $threshold ]] && aggregated="yes"

q() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\'}"
  printf '%s' "$s"
}

md="# Containers"$'\n\n'
md+="subject: $subject"$'\n'
if [[ "$dialect" == "unset" ]]; then
  md+="dialect: unset (no C4 view emitted)"$'\n'
else
  md+="dialect: $dialect"$'\n'
fi
md+="thin: $thin"$'\n'
md+="aggregated: $aggregated"$'\n\n'
if [[ "$thin" == "yes" ]]; then
  md+="This result is thin. A container view answers which deployables exist and which stores they bind. What is inside one deployable is the component rung. Environment topology is the deployment rung. Message choreography is the events rung."$'\n\n'
fi

md+="## Deployables"$'\n\n'
[[ $n_deploy -eq 0 ]] && md+="None."$'\n\n'
for ((i = 0; i < N_N; i++)); do
  [[ "${N_KIND[$i]}" == "deployable" ]] || continue
  md+="### $(q "${N_NAME[$i]}")"$'\n\n'
  md+="- id: $(q "${N_ID[$i]}")"$'\n'
  md+="- output_kind: ${N_OUT[$i]}"$'\n'
  md+="- technology: ${N_TECH[$i]}"$'\n'
  md+="- evidence: ${N_EV[$i]}"$'\n'
  names=""
  for ((m = 0; m < M_N; m++)); do
    [[ "${M_C[$m]}" == "${N_ID[$i]}" ]] || continue
    if [[ -n "$names" ]]; then names+=", "; fi
    names+="${M_NAME[$m]}"
  done
  if [[ -n "$names" ]]; then
    md+="Contains: $names"$'\n'
    for ((m = 0; m < M_N; m++)); do
      [[ "${M_C[$m]}" == "${N_ID[$i]}" ]] || continue
      md+="- module ${M_NAME[$m]}: ${M_PATH[$m]} (${M_EV[$m]})"$'\n'
    done
  fi
  md+=$'\n'
done

md+="## Stores and brokers"$'\n\n'
if [[ $((n_store + n_broker)) -eq 0 ]]; then
  md+="None."$'\n\n'
fi
for ((i = 0; i < N_N; i++)); do
  [[ "${N_KIND[$i]}" == "store" || "${N_KIND[$i]}" == "broker" ]] || continue
  md+="### $(q "${N_NAME[$i]}")"$'\n\n'
  md+="- kind: ${N_KIND[$i]}"$'\n'
  md+="- output_kind: ${N_OUT[$i]}"$'\n'
  md+="- technology: ${N_TECH[$i]}"$'\n'
  md+="- evidence: ${N_EV[$i]}"$'\n\n'
done

md+="## Edges"$'\n\n'
if [[ $E_N -eq 0 ]]; then
  md+="None. Two deployables in one repository are not an edge."$'\n\n'
else
  for ((i = 0; i < E_N; i++)); do
    md+="- kind ${E_KIND[$i]} from ${E_FROM[$i]} to ${E_TO[$i]}: ${E_EV[$i]}"$'\n'
  done
  md+=$'\n'
fi

puml=""
likec4=""
if [[ "$dialect" == "c4-plantuml" ]]; then
  puml+="@startuml"$'\n'
  puml+="!include <C4/C4_Container>"$'\n'
  puml+="title $(q "$subject") containers"$'\n'
  puml+="System_Boundary(sys, \"$(q "$subject")\") {"$'\n'
  alias=1
  declare -A ALIAS=()
  for ((i = 0; i < N_N; i++)); do
    a="n$alias"; alias=$((alias + 1)); ALIAS["${N_ID[$i]}"]="$a"
    case "${N_KIND[$i]}" in
    broker) puml+="  ContainerQueue($a, \"$(q "${N_NAME[$i]}")\", \"$(q "${N_TECH[$i]}")\", \"$(q "${N_OUT[$i]}")\")"$'\n' ;;
    store) puml+="  ContainerDb($a, \"$(q "${N_NAME[$i]}")\", \"$(q "${N_TECH[$i]}")\", \"$(q "${N_OUT[$i]}")\")"$'\n' ;;
    *) puml+="  Container($a, \"$(q "${N_NAME[$i]}")\", \"$(q "${N_TECH[$i]}")\", \"$(q "${N_OUT[$i]}")\")"$'\n' ;;
    esac
  done
  for ((i = 0; i < E_N; i++)); do
    fa="${ALIAS[${E_FROM[$i]}]:-}"; ta="${ALIAS[${E_TO[$i]}]:-}"
    [[ -n "$fa" && -n "$ta" ]] || continue
    puml+="  Rel($fa, $ta, \"$(q "${E_KIND[$i]}")\")"$'\n'
  done
  puml+="}"$'\n'"@enduml"$'\n'
elif [[ "$dialect" == "likec4" ]]; then
  likec4+="specification {"$'\n'"  element deployable"$'\n'"  element store"$'\n'"  element broker"$'\n'"  element module"$'\n'"}"$'\n'
  likec4+="model {"$'\n'
  alias=1
  declare -A ALIAS=()
  for ((i = 0; i < N_N; i++)); do
    a="n$alias"; alias=$((alias + 1)); ALIAS["${N_ID[$i]}"]="$a"
    el="${N_KIND[$i]}"
    [[ "$el" == "deployable" || "$el" == "store" || "$el" == "broker" ]] || el="deployable"
    safe="${N_NAME[$i]//\'/}"
    tech="${N_TECH[$i]//\'/}"
    likec4+="  $a = $el '$safe' {"$'\n'
    likec4+="    technology '$tech'"$'\n'
    likec4+="  }"$'\n'
  done
  for ((i = 0; i < E_N; i++)); do
    fa="${ALIAS[${E_FROM[$i]}]:-}"; ta="${ALIAS[${E_TO[$i]}]:-}"
    [[ -n "$fa" && -n "$ta" ]] || continue
    likec4+="  $fa -> $ta '${E_KIND[$i]}'"$'\n'
  done
  likec4+="}"$'\n'"views {"$'\n'"  view containers {"$'\n'"    include *"$'\n'"  }"$'\n'"}"$'\n'
fi

printf '%s' "$md" >"$outdir/containers.md"
[[ -n "$puml" ]] && printf '%s' "$puml" >"$outdir/containers.puml"
[[ -n "$likec4" ]] && printf '%s' "$likec4" >"$outdir/containers.likec4"

printf 'containers: deployables=%s stores=%s brokers=%s modules=%s binds=%s shared=%s thin=%s dialect=%s aggregated=%s\n' \
  "$n_deploy" "$n_store" "$n_broker" "$M_N" "$n_bind" "$n_shared" "$thin" "$dialect" "$aggregated"
exit 0
