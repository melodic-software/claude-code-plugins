#!/usr/bin/env bash
# Render containers.json as a C4 container diagram.
#
# WHY. The record is the fact. This script draws only what the record says,
# and it refuses a record that is not in the one-object-per-line layout
# collect-containers.sh writes.
#
# Usage:
#   render-containers.sh --record <file> --out <dir> [--dialect mermaid|structurizr]
#   render-containers.sh --help
#
# --dialect defaults to mermaid, the landscape_dialect default. map-containers
# reads that same key. It does not read diagram_dialect.system.
#
# mermaid writes containers.md with a C4Container diagram.
# structurizr writes containers.dsl with a container view.
# Contained modules are named on their deployable. They are not containers.
#
# Prints:
#   containers: focal=<name> deployables=<n> stores=<n> modules=<n> edges=<n> shared=<n> unknown_technology=<n> thin=<yes|no>
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
dialect="mermaid"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h) usage; exit 0 ;;
  --record) [[ $# -ge 2 ]] || die "--record needs a path" 2; record="$2"; shift 2 ;;
  --record=*) record="${1#--record=}"; shift ;;
  --out) [[ $# -ge 2 ]] || die "--out needs a directory" 2; outdir="$2"; shift 2 ;;
  --out=*) outdir="${1#--out=}"; shift ;;
  --dialect) [[ $# -ge 2 ]] || die "--dialect needs mermaid or structurizr" 2; dialect="$2"; shift 2 ;;
  --dialect=*) dialect="${1#--dialect=}"; shift ;;
  *) die "unknown argument: $1" 2 ;;
  esac
done

[[ -n "$record" && -n "$outdir" ]] || {
  usage >&2
  exit 2
}
case "$dialect" in
mermaid | structurizr) ;;
*) die "--dialect must be mermaid or structurizr (landscape_dialect), got: $dialect" 2 ;;
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

if [[ "$dialect" == "mermaid" ]]; then
  target="$outdir/containers.md"
else
  target="$outdir/containers.dsl"
fi

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
  gsub(/\t/, " ", s)
  gsub(/\r/, "", s)
  gsub(/\n/, " ", s)
  return s
}
function alias(s,    a) {
  a = s
  gsub(/[^A-Za-z0-9]/, "_", a)
  if (a == "" || a ~ /^[0-9]/) a = "n_" a
  return a
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
  if (kind == "store" && (store_kind == "sql" || store_kind == "storage")) return "ContainerDb"
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
}
END {
  if (focal == "") focal = "system"
  thin = (deployables == 0 ? "yes" : "no")
  out = ENVIRON["OUT_FILE"]
  dialect = ENVIRON["DIALECT"]
  for (i = 1; i <= cn; i++) calias[i] = uniq(alias(cname[i]))
  for (i = 1; i <= cn; i++) idalias[cid[i]] = calias[i]
  if (dialect == "mermaid") {
    print "# Containers" > out
    print "" > out
    print "C4 container diagram for " safe(focal) ". Modules named on a deployable are contained in it. They are not separate containers. A shared-infrastructure row cites every config key for that store. `unknown` is the technology when the manifest named no runtime." > out
    print "" > out
    print "```mermaid" > out
    print "C4Container" > out
    print "title Container diagram for " safe(focal) > out
    print "System_Boundary(sys, \"" safe(focal) "\") {" > out
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
      label = "Uses"
      if (ekind[i] == "calls") label = "Calls"
      print "Rel(" fa ", " ta ", \"" label "\", \"" safe(eev[i]) "\")" > out
    }
    print "```" > out
    print "" > out
    print "## Shared infrastructure" > out
    print "" > out
    print "| from | to | evidence |" > out
    print "| --- | --- | --- |" > out
    if (shared == 0) print "| none | none | none |" > out
    for (i = 1; i <= en; i++) {
      if (ekind[i] != "shared-infrastructure") continue
      print "| " safe(efrom[i]) " | " safe(edge_to[i]) " | " safe(eev[i]) " |" > out
    }
    print "" > out
    print "## Evidence" > out
    print "" > out
    print "| id | kind | technology | summary | evidence |" > out
    print "| --- | --- | --- | --- | --- |" > out
    for (i = 1; i <= cn; i++) {
      print "| " safe(cid[i]) " | " safe(ckind[i]) " | " safe(ctech[i]) " | " safe(csum[i]) " | " safe(cev[i]) " |" > out
    }
  } else {
    print "workspace \"" safe(focal) "\" \"containers\" {" > out
    print "  model {" > out
    print "    sys = softwareSystem \"" safe(focal) "\" {" > out
    for (i = 1; i <= cn; i++) {
      desc = csum[i]
      if (desc == "") desc = ckind[i]
      print "      " calias[i] " = container \"" safe(cname[i]) "\" \"" safe(desc) "\" \"" safe(ctech[i]) "\"" > out
    }
    for (i = 1; i <= en; i++) {
      if (ekind[i] == "shared-infrastructure") continue
      fa = idalias[efrom[i]]
      ta = idalias[edge_to[i]]
      if (fa == "" || ta == "") continue
      label = "Uses"
      if (ekind[i] == "calls") label = "Calls"
      print "      " fa " -> " ta " \"" label "\" \"" safe(eev[i]) "\"" > out
    }
    print "    }" > out
    print "  }" > out
    print "  views {" > out
    print "    container sys \"Containers\" {" > out
    print "      include *" > out
    print "      autoLayout lr" > out
    print "    }" > out
    print "  }" > out
    print "}" > out
    print "" > out
    print "/*" > out
    print "Shared infrastructure. Each row cites every config key for that store." > out
    if (shared == 0) print "none" > out
    for (i = 1; i <= en; i++) {
      if (ekind[i] != "shared-infrastructure") continue
      print safe(efrom[i]) " -> " safe(edge_to[i]) " " safe(eev[i]) > out
    }
    for (i = 1; i <= cn; i++) {
      if (csum[i] != "") print safe(cname[i]) " " safe(csum[i]) > out
    }
    print "*/" > out
  }
  close(out)
  printf "containers: focal=%s deployables=%d stores=%d modules=%d edges=%d shared=%d unknown_technology=%d thin=%s\n", focal, deployables + 0, stores + 0, modules + 0, en + 0, shared + 0, unknown + 0, thin
}
' "$record"
