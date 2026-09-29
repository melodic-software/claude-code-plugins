#!/usr/bin/env bash
# Render context.json as a C4 system context diagram.
#
# WHY. The record is the fact. This script only draws what the record says,
# and it refuses a record whose JSON is valid but not in the one-object-per-line
# layout collect-context.sh writes. A reformatted record must not render as an
# empty diagram with exit 0.
#
# Usage:
#   render-context.sh --record <file> --out <dir> [--dialect likec4|c4-plantuml|none]
#   render-context.sh --help
#
# --dialect is the resolved authoring-formats diagram_dialect.system. It has no
# default: none, the value when the key is unset, draws no diagram. Mermaid is
# refused, as the convention refuses it for that key.
#
# Writes, into <dir>:
#   context.md    prose, one fenced likec4 or plantuml block with a focal
#                 system, a person for each operator-stated actor, and an
#                 external system for each derived host (no block when the
#                 dialect is none), then the node and evidence tables
#
# Prints one summary line on stdout:
#   context: focal=<name> externals=<n> actors=<n> thin=<yes|no> dialect=<d>
# thin is yes when the record has no external systems.
#
# Exit: 0 = written; 1 = unreadable, not schema_version 1, or not the
# one-object-per-line layout (nothing is written); 2 = usage.
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'render-context.sh: %s\n' "$1" >&2
  exit "$2"
}

record=""
outdir=""
dialect="none"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --record)
    [[ $# -ge 2 ]] || die "--record needs a path" 2
    record="$2"
    shift 2
    ;;
  --record=*)
    record="${1#--record=}"
    shift
    ;;
  --out)
    [[ $# -ge 2 ]] || die "--out needs a directory" 2
    outdir="$2"
    shift 2
    ;;
  --out=*)
    outdir="${1#--out=}"
    shift
    ;;
  --dialect)
    [[ $# -ge 2 ]] || die "--dialect needs likec4, c4-plantuml, or none" 2
    dialect="$2"
    shift 2
    ;;
  --dialect=*)
    dialect="${1#--dialect=}"
    shift
    ;;
  *)
    die "unknown argument: $1" 2
    ;;
  esac
done

[[ -n "$record" && -n "$outdir" ]] || {
  usage >&2
  exit 2
}
case "$dialect" in
likec4 | c4-plantuml | none) ;;
*) die "--dialect must be likec4, c4-plantuml, or none (diagram_dialect.system), got: $dialect" 2 ;;
esac
[[ -r "$record" ]] || die "cannot read record: $record" 1
[[ -d "$outdir" ]] || die "not a directory: $outdir" 1
grep -q '"schema_version"[[:space:]]*:[[:space:]]*1' "$record" ||
  die "not a schema_version 1 record: $record" 1

read -r -d '' LAYOUT_AWK <<'AWK' || true
BEGIN {
  shape["actors"] = "^[[:space:]]*[{]\"name\":"
  shape["externals"] = "^[[:space:]]*[{]\"host\":"
}
function open_array(key,   rest) {
  if (!match($0, "\"" key "\"[[:space:]]*:[[:space:]]*\\[")) return
  rest = substr($0, RSTART + RLENGTH)
  if (rest ~ /^[[:space:]]*\]/) { seen[key] = 1; return }
  if (substr($0, 1, RSTART - 1) ~ /^[[:space:]]*$/ && rest ~ /^[[:space:]]*$/) { open = key; return }
  problem = "the " key " array does not start on a line of its own"
}
/"focal"[[:space:]]*:[[:space:]]*\{"name":/ { saw_focal = 1 }
open != "" {
  if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) { seen[open] = 1; open = ""; next }
  if ($0 !~ shape[open]) { problem = "line " NR " is not one " open " object"; exit }
  next
}
{
  open_array("actors")
  if (problem == "" && open == "") open_array("externals")
  if (problem != "") exit
}
END {
  if (problem == "" && open != "") problem = "the " open " array never closes"
  if (problem == "" && !("actors" in seen)) problem = "no actors array was found"
  if (problem == "" && !("externals" in seen)) problem = "no externals array was found"
  if (problem == "" && !saw_focal) problem = "no focal object was found"
  print problem
}
AWK
layout_problem="$(awk "$LAYOUT_AWK" "$record")"
[[ -z "$layout_problem" ]] ||
  die "record is not in the one-object-per-line layout collect-context.sh writes ($layout_problem); regenerate it: $record" 1

target="$outdir/context.md"

OUT_FILE="$target" DIALECT="$dialect" awk -f - "$record" <<'AWK'
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
function rank(k) {
  if (k == "authority") return 7
  if (k == "storage") return 6
  if (k == "broker") return 5
  if (k == "sql") return 4
  if (k == "cache") return 3
  if (k == "mail") return 2
  return 1
}
function rel_label(k) {
  if (k == "sql") return "Reads and writes"
  if (k == "storage") return "Stores objects"
  if (k == "broker") return "Publishes and consumes"
  if (k == "authority") return "Authenticates with"
  if (k == "cache") return "Caches with"
  if (k == "mail") return "Sends mail"
  return "Calls"
}
function safe(s) {
  gsub(/\\/, "/", s)
  gsub(/"/, "\047", s)
  gsub(/`/, "\047", s)
  gsub(/[|]/, "/", s)
  gsub(/\t/, " ", s)
  gsub(/\r/, "", s)
  gsub(/\n/, " ", s)
  return s
}
function alias(s,    a) {
  a = s
  gsub(/[^A-Za-z0-9]/, "_", a)
  return "e_" a
}
function uniq(a,    c, cand) {
  cand = a
  c = 1
  while (cand in taken) {
    c++
    cand = a "_" c
  }
  taken[cand] = 1
  return cand
}
function kind_desc(host,    d) {
  d = hkind[host]
  if (hport[host] != "") d = d ", port " hport[host]
  return d
}
function emit(line) {
  print line >> out
}
BEGIN {
  out = ENVIRON["OUT_FILE"]
  dialect = ENVIRON["DIALECT"]
  printf "" > out
}
/"generated_on"/ && generated == "" { generated = jstr($0, "generated_on") }
/"focal"/ && focal == "" { focal = jstr($0, "name"); if (focal == "") focal = jstr($0, "focal") }
/^[[:space:]]*\{"name":/ {
  an = an + 1
  aname[an] = jstr($0, "name")
  adesc[an] = jstr($0, "description")
}
/^[[:space:]]*\{"host":/ {
  host = jstr($0, "host")
  kind = jstr($0, "kind")
  port = jstr($0, "port")
  file = jstr($0, "file")
  key = jstr($0, "key")
  if (!(host in seen_host)) {
    seen_host[host] = 1
    nh++
    hosts[nh] = host
    hkind[host] = kind
    hport[host] = port
  } else if (rank(kind) > rank(hkind[host])) {
    hkind[host] = kind
    if (port != "") hport[host] = port
  }
  ne++
  evid[ne] = host "\034" file "\034" key
}
END {
  if (generated == "") generated = "unknown"
  if (focal == "") focal = "unknown"
  # Stable order: actors by name, hosts by host, evidence by host then file then key.
  for (i = 1; i <= an; i++)
    for (j = i + 1; j <= an; j++)
      if (aname[j] < aname[i]) {
        t = aname[i]; aname[i] = aname[j]; aname[j] = t
        t = adesc[i]; adesc[i] = adesc[j]; adesc[j] = t
      }
  for (i = 1; i <= nh; i++)
    for (j = i + 1; j <= nh; j++)
      if (hosts[j] < hosts[i]) {
        t = hosts[i]; hosts[i] = hosts[j]; hosts[j] = t
      }
  for (i = 1; i <= ne; i++)
    for (j = i + 1; j <= ne; j++)
      if (evid[j] < evid[i]) {
        t = evid[i]; evid[i] = evid[j]; evid[j] = t
      }
  focal_alias = uniq(alias(focal))
  for (i = 1; i <= an; i++) aalias[i] = uniq(alias(aname[i]))
  for (i = 1; i <= nh; i++) halias[hosts[i]] = uniq(alias(hosts[i]))

  {
    emit("# System Context")
    emit("")
    emit("Generated on " safe(generated) ". Dialect: diagram_dialect.system=" dialect ".")
    emit("")
    emit("Operator-stated actors are drawn as people. External systems derived from configuration are drawn as external software systems. The focal system is drawn as the software system in scope.")
    emit("")
    if (nh == 0) {
      emit("No external systems were found in committed configuration.")
      emit("Neighboring rungs: system landscape (/architecture:map-landscape), containers (the deployables inside this system).")
      emit("")
    }
    if (dialect == "none") {
      emit("No C4 view is drawn: diagram_dialect.system is unset (no C4 view emitted). The tables below come from the record.")
    } else if (dialect == "c4-plantuml") {
      emit("```plantuml")
      emit("@startuml")
      emit("!include <C4/C4_Context>")
      emit("title System Context for " safe(focal))
      for (i = 1; i <= an; i++) {
        desc = adesc[i]
        if (desc == "") desc = "Operator-stated actor"
        emit("Person(" aalias[i] ", \"" safe(aname[i]) "\", \"" safe(desc) "\")")
      }
      emit("System(" focal_alias ", \"" safe(focal) "\", \"The software system in scope\")")
      for (i = 1; i <= nh; i++) {
        h = hosts[i]
        emit("System_Ext(" halias[h] ", \"" safe(h) "\", \"" safe(kind_desc(h)) "\")")
      }
      for (i = 1; i <= an; i++)
        emit("Rel(" aalias[i] ", " focal_alias ", \"Uses\")")
      for (i = 1; i <= nh; i++) {
        h = hosts[i]
        emit("Rel(" focal_alias ", " halias[h] ", \"" rel_label(hkind[h]) "\")")
      }
      emit("@enduml")
    } else {
      emit("```likec4")
      emit("specification {")
      emit("  element person {")
      emit("    style {")
      emit("      shape person")
      emit("    }")
      emit("  }")
      emit("  element softwareSystem")
      emit("  element externalSystem {")
      emit("    style {")
      emit("      color muted")
      emit("    }")
      emit("  }")
      emit("}")
      emit("model {")
      for (i = 1; i <= an; i++) {
        desc = adesc[i]
        if (desc == "") desc = "Operator-stated actor"
        emit("  " aalias[i] " = person \"" safe(aname[i]) "\" \"" safe(desc) "\"")
      }
      emit("  " focal_alias " = softwareSystem \"" safe(focal) "\" \"The software system in scope\"")
      for (i = 1; i <= nh; i++) {
        h = hosts[i]
        emit("  " halias[h] " = externalSystem \"" safe(h) "\" \"" safe(kind_desc(h)) "\"")
      }
      for (i = 1; i <= an; i++)
        emit("  " aalias[i] " -> " focal_alias " \"Uses\"")
      for (i = 1; i <= nh; i++) {
        h = hosts[i]
        emit("  " focal_alias " -> " halias[h] " \"" rel_label(hkind[h]) "\"")
      }
      emit("}")
      emit("views {")
      emit("  view context {")
      emit("    title \"System Context for " safe(focal) "\"")
      emit("    include *")
      emit("  }")
      emit("}")
    }
    if (dialect != "none") emit("```")
    emit("")
    emit("## Nodes")
    emit("")
    emit("| Name | Element | Origin |")
    emit("|---|---|---|")
    for (i = 1; i <= an; i++)
      emit("| " safe(aname[i]) " | person | operator-stated |")
    emit("| " safe(focal) " | software system | focal |")
    for (i = 1; i <= nh; i++)
      emit("| " safe(hosts[i]) " | external software system | derived |")
    emit("")
    emit("## Evidence")
    emit("")
    if (ne == 0) {
      emit("No external system was derived from committed configuration.")
    } else {
      emit("| External system | File | Config key |")
      emit("|---|---|---|")
      for (i = 1; i <= ne; i++) {
        split(evid[i], p, "\034")
        emit("| " safe(p[1]) " | " safe(p[2]) " | " safe(p[3]) " |")
      }
    }
    emit("")
  }
  printf "context: focal=%s externals=%d actors=%d thin=%s dialect=%s\n", focal, nh, an, (nh == 0 ? "yes" : "no"), dialect
}
AWK

exit 0
