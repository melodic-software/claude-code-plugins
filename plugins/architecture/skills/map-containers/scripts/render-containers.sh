#!/usr/bin/env bash
# Render containers.json as a C4 container diagram.
#
# WHY. The record is the fact. This script draws only what the record says,
# and it refuses a record that is not in the one-object-per-line layout
# collect-containers.sh writes.
#
# Usage:
#   render-containers.sh --record <file> --out <dir> [--dialect likec4|c4-plantuml|none]
#   render-containers.sh --help
#
# --dialect is the resolved authoring-formats diagram_dialect.system. It has no
# default: none, the value when the key is unset, draws no diagram. Mermaid is
# refused, as the convention refuses it for that key.
#
# containers.md carries one fenced likec4 or plantuml block (none when the
# dialect is none), then the uses, shared-infrastructure, findings, and evidence
# tables. A store shared by three owners is one shared-infrastructure row per
# owner pair. Contained modules are named on their deployable. They are not
# containers. The findings array is optional: a record without it renders.
#
# Prints:
#   containers: focal=<name> deployables=<n> stores=<n> modules=<n> edges=<n> shared=<n> unknown_technology=<n> thin=<yes|no> dialect=<d> excluded_tests=<n> dirty_tracked_files=<n>
#
# Exit: 0 written; 1 unreadable, not schema_version 1, or wrong layout
# (nothing written); 2 usage.
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
dialect="none"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h) usage; exit 0 ;;
  --record) [[ $# -ge 2 ]] || die "--record needs a path" 2; record="$2"; shift 2 ;;
  --record=*) record="${1#--record=}"; shift ;;
  --out) [[ $# -ge 2 ]] || die "--out needs a directory" 2; outdir="$2"; shift 2 ;;
  --out=*) outdir="${1#--out=}"; shift ;;
  --dialect) [[ $# -ge 2 ]] || die "--dialect needs likec4, c4-plantuml, or none" 2; dialect="$2"; shift 2 ;;
  --dialect=*) dialect="${1#--dialect=}"; shift ;;
  *) die "unknown argument: $1" 2 ;;
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

layout_problem="$(awk '
  function open_array(key,   rest) {
    if (!match($0, "\"" key "\"[[:space:]]*:[[:space:]]*\\[")) return
    rest = substr($0, RSTART + RLENGTH)
    if (rest ~ /^[[:space:]]*\]/) { seen[key] = 1; return }
    if (substr($0, 1, RSTART - 1) ~ /^[[:space:]]*$/ && rest ~ /^[[:space:]]*$/) { open = key; return }
    problem = "the " key " array does not start on a line of its own"
  }
  BEGIN {
    shape["containers"] = "^[[:space:]]*[{]\"id\":"
    shape["modules"] = "^[[:space:]]*[{]\"container\":"
    shape["edges"] = "^[[:space:]]*[{]\"from\":"
    shape["findings"] = "^[[:space:]]*[{]\"kind\":"
  }
  open != "" {
    if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) { seen[open] = 1; open = ""; next }
    if ($0 !~ shape[open]) { problem = "line " NR " is not one " open " object"; exit }
    next
  }
  {
    open_array("containers")
    if (problem == "" && open == "") open_array("modules")
    if (problem == "" && open == "") open_array("edges")
    if (problem == "" && open == "") open_array("findings")
    if (problem != "") exit
  }
  END {
    if (problem == "" && open != "") problem = "the " open " array never closes"
    if (problem == "" && !("containers" in seen)) problem = "no containers array was found"
    if (problem == "" && !("modules" in seen)) problem = "no modules array was found"
    if (problem == "" && !("edges" in seen)) problem = "no edges array was found"
    print problem
  }
' "$record")"
[[ -z "$layout_problem" ]] ||
  die "record is not in the one-object-per-line layout collect-containers.sh writes ($layout_problem); regenerate it: $record" 1

target="$outdir/containers.md"

OUT_FILE="$target" DIALECT="$dialect" awk '
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
function element(kind, store_kind) {
  if (kind == "store" && (store_kind == "sql" || store_kind == "storage" || store_kind == "search")) return "ContainerDb"
  if (kind == "store" && store_kind == "broker") return "ContainerQueue"
  return "Container"
}
BEGIN { focal = "" }
/"focal"[[:space:]]*:/ {
  if (focal == "") focal = jstr($0, "focal")
}
/^[[:space:]]*\{"id":/ {
  cn++
  cid[cn] = jstr($0, "id")
  cname[cn] = jstr($0, "name")
  ckind[cn] = jstr($0, "kind")
  ctech[cn] = jstr($0, "technology")
  cstore[cn] = jstr($0, "store_kind")
  csum[cn] = jstr($0, "summary")
  cev[cn] = jstr($0, "evidence")
  if (ckind[cn] == "store") stores++
  else deployables++
  if (ctech[cn] == "unknown") unknown++
}
/^[[:space:]]*\{"container":/ { modules++ }
/^[[:space:]]*\{"from":/ {
  en++
  efrom[en] = jstr($0, "from")
  edge_to[en] = jstr($0, "to")
  ekind[en] = jstr($0, "kind")
  evia[en] = jstr($0, "via")
  eev[en] = jstr($0, "evidence")
  if (ekind[en] == "shared-infrastructure") shared++
  if (ekind[en] == "uses") uses++
}
/^[[:space:]]*\{"kind":/ {
  fn++
  fkind[fn] = jstr($0, "kind")
  fev[fn] = jstr($0, "evidence")
  fcount[fn] = 0
  if (match($0, /"count":[0-9]+/)) fcount[fn] = substr($0, RSTART + 8, RLENGTH - 8) + 0
  if (fkind[fn] == "excluded-test-projects") excluded += fcount[fn]
  if (fkind[fn] == "dirty-tracked-files") dirty += fcount[fn]
}
END {
  if (focal == "") focal = "system"
  thin = (deployables == 0 ? "yes" : "no")
  out = ENVIRON["OUT_FILE"]
  dialect = ENVIRON["DIALECT"]
  for (i = 1; i <= cn; i++) calias[i] = uniq(alias(cname[i]))
  for (i = 1; i <= cn; i++) idalias[cid[i]] = calias[i]
  {
    print "# Containers" > out
    print "" > out
    print "C4 container diagram for " safe(focal) ". Dialect: diagram_dialect.system=" dialect ". Modules named on a deployable are contained in it. They are not separate containers. A shared-infrastructure row is one pair of owners of a store and cites the config keys of both. `unknown` is the technology when the manifest named no runtime." > out
    print "" > out
    if (dialect == "none") {
      print "No C4 view is drawn: diagram_dialect.system is unset (no C4 view emitted). The tables below come from the record." > out
    } else if (dialect == "c4-plantuml") {
      print "```plantuml" > out
      print "@startuml" > out
      print "!include <C4/C4_Container>" > out
      print "title Container diagram for " safe(focal) > out
      print "System_Boundary(e_sys, \"" safe(focal) "\") {" > out
      for (i = 1; i <= cn; i++) {
        desc = csum[i]
        if (desc == "") desc = ckind[i]
        el = element(ckind[i], cstore[i])
        print "  " el "(" calias[i] ", \"" safe(cname[i]) "\", \"" safe(ctech[i]) "\", \"" safe(desc) "\")" > out
      }
      print "}" > out
      for (i = 1; i <= en; i++) {
        if (ekind[i] == "shared-infrastructure") continue
        fa = idalias[efrom[i]]
        ta = idalias[edge_to[i]]
        if (fa == "" || ta == "") continue
        print "Rel(" fa ", " ta ", \"" "Uses" "\", \"" safe(eev[i]) "\")" > out
      }
      print "@enduml" > out
    } else {
      print "```likec4" > out
      print "specification {" > out
      print "  element softwareSystem" > out
      print "  element container" > out
      print "  element store {" > out
      print "    style {" > out
      print "      shape storage" > out
      print "    }" > out
      print "  }" > out
      print "  element queue {" > out
      print "    style {" > out
      print "      shape queue" > out
      print "    }" > out
      print "  }" > out
      print "}" > out
      print "model {" > out
      print "  e_sys = softwareSystem \"" safe(focal) "\" {" > out
      for (i = 1; i <= cn; i++) {
        desc = csum[i]
        if (desc == "") desc = ckind[i]
        el = element(ckind[i], cstore[i])
        lk = (el == "ContainerDb" ? "store" : (el == "ContainerQueue" ? "queue" : "container"))
        print "    " calias[i] " = " lk " \"" safe(cname[i]) "\" {" > out
        print "      technology \"" safe(ctech[i]) "\"" > out
        print "      description \"" safe(desc) "\"" > out
        print "    }" > out
      }
      print "  }" > out
      for (i = 1; i <= en; i++) {
        if (ekind[i] == "shared-infrastructure") continue
        fa = idalias[efrom[i]]
        ta = idalias[edge_to[i]]
        if (fa == "" || ta == "") continue
        print "  e_sys." fa " -> e_sys." ta " \"" "Uses" "\"" > out
      }
      print "}" > out
      print "views {" > out
      print "  view containers of e_sys {" > out
      print "    title \"Container diagram for " safe(focal) "\"" > out
      print "    include *" > out
      print "  }" > out
      print "}" > out
    }
    if (dialect != "none") print "```" > out
    print "" > out
    print "## Uses" > out
    print "" > out
    print "| from | to | evidence |" > out
    print "| --- | --- | --- |" > out
    if (uses == 0) print "| none | none | none |" > out
    for (i = 1; i <= en; i++) {
      if (ekind[i] != "uses") continue
      print "| " safe(efrom[i]) " | " safe(edge_to[i]) " | " safe(eev[i]) " |" > out
    }
    print "" > out
    print "## Shared infrastructure" > out
    print "" > out
    print "| from | to | store | evidence |" > out
    print "| --- | --- | --- | --- |" > out
    if (shared == 0) print "| none | none | none | none |" > out
    for (i = 1; i <= en; i++) {
      if (ekind[i] != "shared-infrastructure") continue
      print "| " safe(efrom[i]) " | " safe(edge_to[i]) " | " safe(evia[i]) " | " safe(eev[i]) " |" > out
    }
    print "" > out
    print "## Findings" > out
    print "" > out
    print "| kind | count | evidence |" > out
    print "| --- | --- | --- |" > out
    if (fn == 0) print "| none | none | none |" > out
    for (i = 1; i <= fn; i++) {
      print "| " safe(fkind[i]) " | " fcount[i] " | " safe(fev[i]) " |" > out
    }
    print "" > out
    print "## Evidence" > out
    print "" > out
    print "| id | kind | technology | summary | evidence |" > out
    print "| --- | --- | --- | --- | --- |" > out
    for (i = 1; i <= cn; i++) {
      print "| " safe(cid[i]) " | " safe(ckind[i]) " | " safe(ctech[i]) " | " safe(csum[i]) " | " safe(cev[i]) " |" > out
    }
    close(out)
  }
  printf "containers: focal=%s deployables=%d stores=%d modules=%d edges=%d shared=%d unknown_technology=%d thin=%s dialect=%s excluded_tests=%d dirty_tracked_files=%d\n", focal, deployables + 0, stores + 0, modules + 0, en + 0, shared + 0, unknown + 0, thin, dialect, excluded + 0, dirty + 0
}
' "$record"
