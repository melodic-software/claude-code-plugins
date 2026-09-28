#!/usr/bin/env bash
# Render a C4 component view of one deployable from dependency-graph.json.
#
# WHY. Grouping, arrow direction, layer-violation marking, and aggregation are
# mechanical. Two runs on the same graph and flags produce byte-identical
# files. The script does not weigh what the graph should look like.
#
# Usage:
#   render-components.sh --graph <dependency-graph.json> --out <dir> [options]
#   render-components.sh --help
#
# Options:
#   --graph <file>         schema_version 1 record. Required.
#   --out <dir>            Directory the artifacts are written into. Required.
#   --container <name>     Deployable to chart: a node id, path, or unique name.
#                          With one indegree-zero deployable whose closure covers
#                          every project, that deployable is the default. Several
#                          deployables exit 3 and name the choices. Nothing is
#                          written in that case.
#   --group-by <strategy>  directory (default), namespace, or layer.
#                          layer requires --layers.
#   --layers <a,b,c>       Layering convention, outside to inside. An edge from
#                          a later layer to an earlier one is marked as a
#                          violation. The mark is informational: the exit code
#                          stays 0.
#   --dialect <name>       mermaid (default) or structurizr. Mermaid writes
#                          components.md with a C4Component diagram. Structurizr
#                          writes components.dsl (a component view) and a
#                          components.md that carries the tables.
#   --source <text>        Provenance line. Default: dependency-graph.json.
#   --node-threshold <N>   Component count above which the view aggregates to
#                          coarser groups and says so. Default: the record's
#                          node_threshold, else 24. Aggregation never drops a
#                          component or an evidence row.
#   --notes <file>         Appended verbatim to components.md.
#
# The record's physical shape is one object per line, the same contract as
# landscape.json. A node line's first key is "id". An edge line's first key is
# "from". Any other layout exits 1 and writes nothing.
#
# Edge kind "project" (or ProjectReference) is an internal component edge.
# Kind "package" (or PackageReference) is collapsed, not drawn. Kind
# "unresolved", or a project edge whose target is not a charted project, is
# listed and never matched to a similarly named project.
#
# A single project with no internal edges is a thin result: components.md says
# so and names the neighboring rungs, and no one-box diagram is written.
# ecosystem "unknown" writes that reason and no diagram.
#
# Prints one summary line on stdout:
#
#   components: container="<name>" components=<n> edges=<n> drawn_edges=<n>
#   violations=<n> aggregated=<yes|no> thin=<yes|no> external_collapsed=<n>
#   unresolved=<n>
#
# Determinism is the contract: the same graph and flags produce byte-identical
# files.
#
# Portability: bash plus POSIX awk/grep/sed. No jq, no grep -P, no python.
#
# Exit: 0 = written (including thin and unknown); 1 = unreadable graph, wrong
# schema, wrong layout, unknown container, or missing output directory;
# 2 = usage; 3 = a container must be chosen (nothing written).
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'render-components.sh: %s\n' "$1" >&2
  exit "$2"
}

graph=""
outdir=""
container=""
groupby="directory"
layers=""
dialect="mermaid"
source_name="dependency-graph.json"
threshold=""
notes=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --graph)
    [[ $# -ge 2 ]] || die "--graph needs a path" 2
    graph="$2"
    shift 2
    ;;
  --graph=*)
    graph="${1#--graph=}"
    shift
    ;;
  --out)
    [[ $# -ge 2 ]] || die "--out needs a path" 2
    outdir="$2"
    shift 2
    ;;
  --out=*)
    outdir="${1#--out=}"
    shift
    ;;
  --container)
    [[ $# -ge 2 ]] || die "--container needs a value" 2
    container="$2"
    shift 2
    ;;
  --container=*)
    container="${1#--container=}"
    shift
    ;;
  --group-by)
    [[ $# -ge 2 ]] || die "--group-by needs a value" 2
    groupby="$2"
    shift 2
    ;;
  --group-by=*)
    groupby="${1#--group-by=}"
    shift
    ;;
  --layers)
    [[ $# -ge 2 ]] || die "--layers needs a value" 2
    layers="$2"
    shift 2
    ;;
  --layers=*)
    layers="${1#--layers=}"
    shift
    ;;
  --dialect)
    [[ $# -ge 2 ]] || die "--dialect needs a value" 2
    dialect="$2"
    shift 2
    ;;
  --dialect=*)
    dialect="${1#--dialect=}"
    shift
    ;;
  --source)
    [[ $# -ge 2 ]] || die "--source needs a value" 2
    source_name="$2"
    shift 2
    ;;
  --source=*)
    source_name="${1#--source=}"
    shift
    ;;
  --node-threshold)
    [[ $# -ge 2 ]] || die "--node-threshold needs a number" 2
    threshold="$2"
    shift 2
    ;;
  --node-threshold=*)
    threshold="${1#--node-threshold=}"
    shift
    ;;
  --notes)
    [[ $# -ge 2 ]] || die "--notes needs a path" 2
    notes="$2"
    shift 2
    ;;
  --notes=*)
    notes="${1#--notes=}"
    shift
    ;;
  *)
    die "unknown argument: $1" 2
    ;;
  esac
done

[[ -n "$graph" && -n "$outdir" ]] || {
  usage >&2
  exit 2
}
case "$dialect" in
mermaid | structurizr) ;;
*) die "unknown dialect: $dialect (mermaid or structurizr)" 2 ;;
esac
case "$groupby" in
directory | namespace | layer) ;;
*) die "unknown --group-by: $groupby (directory, namespace, or layer)" 2 ;;
esac
if [[ "$groupby" == "layer" && -z "$layers" ]]; then
  die "--group-by layer needs --layers (a declared layering convention)" 2
fi
if [[ -n "$threshold" ]]; then
  case "$threshold" in
  '' | *[!0-9]*) die "--node-threshold needs a whole number, got: $threshold" 2 ;;
  *) ;;
  esac
fi
[[ -r "$graph" ]] || die "cannot read graph: $graph" 1
[[ -d "$outdir" ]] || die "not a directory: $outdir" 1
[[ -z "$notes" || -r "$notes" ]] || die "cannot read notes: $notes" 1
grep -q '"schema_version"[[:space:]]*:[[:space:]]*1' "$graph" ||
  die "not a schema_version 1 record: $graph" 1

read -r -d '' LAYOUT_AWK <<'AWK' || true
BEGIN {
  shape["nodes"] = "^[[:space:]]*[{]\"id\":"
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
  if (problem == "" && open == "") open_array("edges")
  if (problem != "") exit
}
END {
  if (problem == "" && open != "") problem = "the " open " array never closes"
  if (problem == "" && !("nodes" in seen)) problem = "no nodes array was found"
  if (problem == "" && !("edges" in seen)) problem = "no edges array was found"
  print problem
}
AWK
layout_problem="$(awk "$LAYOUT_AWK" "$graph")"
[[ -z "$layout_problem" ]] ||
  die "record is not in the one-object-per-line layout ($layout_problem); regenerate it: $graph" 1

if [[ -z "$threshold" ]]; then
  threshold="$(sed -n 's/^[[:space:]]*"node_threshold"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$graph" | head -n 1)"
  [[ -n "$threshold" ]] || threshold=24
fi

ecosystem="$(sed -n 's/^[[:space:]]*"ecosystem"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$graph" | head -n 1)"
unknown_reason="$(sed -n 's/^[[:space:]]*"unknown_reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$graph" | head -n 1)"
generated_on="$(sed -n 's/^[[:space:]]*"generated_on"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$graph" | head -n 1)"
[[ -n "$generated_on" ]] || generated_on="unknown"
[[ -n "$ecosystem" ]] || ecosystem="unknown"

write_summary() {
  printf 'components: container="%s" components=%s edges=%s drawn_edges=%s violations=%s aggregated=%s thin=%s external_collapsed=%s unresolved=%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
}

if [[ "$ecosystem" == "unknown" ]]; then
  [[ -n "$unknown_reason" ]] || unknown_reason="The dependency graph reports ecosystem unknown."
  {
    printf '# Component view\n\n'
    printf 'Generated on %s from %s.\n\n' "$generated_on" "$source_name"
    printf 'Unknown: the dependency graph reports ecosystem `unknown`. %s\n\n' "$unknown_reason"
    printf 'No diagram is drawn. An unrecognized ecosystem is not an empty architecture.\n'
    if [[ -n "$notes" ]]; then
      printf '\n'
      cat "$notes"
    fi
  } >"$outdir/components.md"
  rm -f "$outdir/components.dsl"
  write_summary "none" 0 0 0 0 no yes 0 0
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

awk -v container="$container" -v groupby="$groupby" -v layers="$layers" \
  -v threshold="$threshold" -f /dev/stdin "$graph" >"$tmp" <<'AWK'
function split_object(line, keys, vals,   i, n, c, k, v, depth, instr, start) {
  n = 0
  i = index(line, "{")
  if (i == 0) return 0
  i++
  while (i <= length(line)) {
    c = substr(line, i, 1)
    if (c == " " || c == ",") { i++; continue }
    if (c == "}") break
    if (c != "\"") return n
    i++
    start = i
    while (i <= length(line)) {
      c = substr(line, i, 1)
      if (c == "\\") { i += 2; continue }
      if (c == "\"") break
      i++
    }
    k = substr(line, start, i - start)
    i++
    while (substr(line, i, 1) == " " || substr(line, i, 1) == ":") i++
    start = i
    c = substr(line, i, 1)
    if (c == "\"") {
      i++
      while (i <= length(line)) {
        c = substr(line, i, 1)
        if (c == "\\") { i += 2; continue }
        if (c == "\"") break
        i++
      }
      i++
    } else if (c == "[" || c == "{") {
      depth = 0
      instr = 0
      while (i <= length(line)) {
        c = substr(line, i, 1)
        if (instr) {
          if (c == "\\") { i += 2; continue }
          if (c == "\"") instr = 0
        } else if (c == "\"") {
          instr = 1
        } else if (c == "[" || c == "{") {
          depth++
        } else if (c == "]" || c == "}") {
          depth--
          if (depth == 0) { i++; break }
        }
        i++
      }
    } else {
      while (i <= length(line) && substr(line, i, 1) != "," && substr(line, i, 1) != "}") i++
    }
    v = substr(line, start, i - start)
    n++
    keys[n] = k
    vals[n] = v
  }
  return n
}
function field(line, want,   keys, vals, n, i) {
  n = split_object(line, keys, vals)
  for (i = 1; i <= n; i++) if (keys[i] == want) return vals[i]
  return ""
}
function unquote(v,   out, i, c, last) {
  if (substr(v, 1, 1) != "\"") return v
  v = substr(v, 2, length(v) - 2)
  if (index(v, "\\") == 0) return v
  out = ""
  last = length(v)
  for (i = 1; i <= last; i++) {
    c = substr(v, i, 1)
    if (c == "\\" && i < last) { i++; c = substr(v, i, 1) }
    out = out c
  }
  return out
}
function safe(s) {
  gsub(/\\/, "/", s)
  gsub(/"/, "'", s)
  gsub(/\t/, " ", s)
  gsub(/\r/, " ", s)
  gsub(/\n/, " ", s)
  return s
}
function md(v,   n, parts, i, out) {
  n = split(v, parts, "|")
  out = parts[1]
  for (i = 2; i <= n; i++) out = out "\\|" parts[i]
  return out
}
function norm_edge(k) {
  if (k == "project" || k == "ProjectReference" || k == "module" || k == "workspace") return "project"
  if (k == "package" || k == "PackageReference" || k == "nuget" || k == "npm") return "package"
  if (k == "unresolved") return "unresolved"
  return "other"
}
function is_proj_kind(k) {
  return k == "project" || k == "module"
}
function trim(s) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
  return s
}
function directory_of(path,   n, segs, i, out) {
  if (path == "") return "."
  n = split(path, segs, "/")
  if (n <= 1) return "."
  out = segs[1]
  for (i = 2; i < n; i++) out = out "/" segs[i]
  return out
}
function namespace_of(id) {
  if (ns[id] != "") return ns[id]
  return name[id]
}
function consider_segment(seg,   low, L) {
  low = tolower(seg)
  if (!(low in layer_by_lower)) return
  L = layer_by_lower[low]
  if (length(L) > bestlen) { best = L; bestlen = length(L) }
}
function segments_of(text, sep,   n, parts, i) {
  if (text == "") return
  n = split(text, parts, sep)
  for (i = 1; i <= n; i++) consider_segment(parts[i])
}
function layer_of(id,   explicit, n, parts, i) {
  best = ""
  bestlen = -1
  explicit = layer_field[id]
  if (explicit != "" && (explicit in layer_index)) return explicit
  segments_of(path[id], "/")
  segments_of(name[id], ".")
  segments_of(ns[id], ".")
  if (best != "") return best
  return "undeclared"
}
function parent_group(g,   n, segs, i, out) {
  if (groupby == "layer") return g
  if (groupby == "namespace") {
    n = split(g, segs, ".")
    if (n <= 1) return g
    out = segs[1]
    for (i = 2; i < n; i++) out = out "." segs[i]
    return out
  }
  if (g == ".") return "."
  n = split(g, segs, "/")
  if (n <= 1) return "."
  out = segs[1]
  for (i = 2; i < n; i++) out = out "/" segs[i]
  return out
}
function alias_of(s,   a) {
  a = s
  gsub(/[^A-Za-z0-9]/, "_", a)
  if (a == "") a = "x"
  return "cmp_" a
}
function uniq(a,   c, cand) {
  cand = a
  c = 1
  while (cand in taken) { c++; cand = a "_" c }
  taken[cand] = 1
  return cand
}
function edge_label(kind, evidence) {
  if (evidence ~ /ProjectReference/) return "ProjectReference"
  if (kind == "project") return "project"
  return kind
}
function sort_ids(arr, n,   i, j, t) {
  for (i = 1; i <= n; i++)
    for (j = i + 1; j <= n; j++)
      if (name[arr[j]] < name[arr[i]] || (name[arr[j]] == name[arr[i]] && arr[j] < arr[i])) {
        t = arr[i]; arr[i] = arr[j]; arr[j] = t
      }
}
function bfs(start,   q, qh, qt, cur, i) {
  if (!(start in is_project)) return
  qh = 1
  qt = 1
  q[1] = start
  reached[start] = 1
  while (qh <= qt) {
    cur = q[qh]
    qh++
    for (i = 1; i <= ne; i++) {
      if (eclass[i] != "project") continue
      if (efrom[i] != cur) continue
      if (eto[i] in reached) continue
      if (!(eto[i] in is_project)) continue
      reached[eto[i]] = 1
      qt++
      q[qt] = eto[i]
    }
  }
}
BEGIN {
  nlayers = 0
  rawn = split(layers, rawlayers, ",")
  for (i = 1; i <= rawn; i++) {
    rawlayers[i] = trim(rawlayers[i])
    if (rawlayers[i] == "") continue
    nlayers++
    layer_list[nlayers] = rawlayers[i]
    layer_index[rawlayers[i]] = nlayers
    layer_by_lower[tolower(rawlayers[i])] = rawlayers[i]
  }
  nn = 0
  ne = 0
}
/^[[:space:]]*\{"id":/ {
  id = unquote(field($0, "id"))
  if (id == "") next
  nn++
  nid[nn] = id
  name[id] = unquote(field($0, "name"))
  if (name[id] == "") name[id] = id
  path[id] = unquote(field($0, "path"))
  eco[id] = unquote(field($0, "ecosystem"))
  if (eco[id] == "") eco[id] = "unknown"
  nkind[id] = unquote(field($0, "kind"))
  ns[id] = unquote(field($0, "namespace"))
  layer_field[id] = unquote(field($0, "layer"))
  if (is_proj_kind(nkind[id])) is_project[id] = 1
  next
}
/^[[:space:]]*\{"from":/ {
  ne++
  efrom[ne] = unquote(field($0, "from"))
  eto[ne] = unquote(field($0, "to"))
  ekind[ne] = unquote(field($0, "kind"))
  eevidence[ne] = unquote(field($0, "evidence"))
  next
}
END {
  for (i = 1; i <= ne; i++) {
    ek = norm_edge(ekind[i])
    if (ek == "project" && (efrom[i] in is_project) && (eto[i] in is_project)) eclass[i] = "project"
    else if (ek == "package") eclass[i] = "package"
    else if (ek == "unresolved" || ek == "project") eclass[i] = "unresolved"
    else eclass[i] = "other"
    if (eclass[i] == "project") indegree[eto[i]]++
  }

  nproj = 0
  for (i = 1; i <= nn; i++) if (nid[i] in is_project) nproj++
  if (nproj == 0 && container == "") {
    printf "status\tempty\n"
    exit
  }

  nr = 0
  for (i = 1; i <= nn; i++) {
    id = nid[i]
    if (!(id in is_project)) continue
    if (indegree[id] + 0 == 0) roots[++nr] = id
  }

  delete reached
  for (i = 1; i <= nr; i++) bfs(roots[i])
  nu_un = 0
  for (i = 1; i <= nn; i++) {
    id = nid[i]
    if (!(id in is_project)) continue
    if (!(id in reached)) unreached[++nu_un] = id
  }

  if (container != "") {
    chosen = ""
    if (container in is_project) chosen = container
    else {
      hits = 0
      for (i = 1; i <= nn; i++) {
        id = nid[i]
        if (!(id in is_project)) continue
        if (path[id] == container) { chosen = id; hits = 1; break }
      }
      if (chosen == "") {
        for (i = 1; i <= nn; i++) {
          id = nid[i]
          if (!(id in is_project)) continue
          if (name[id] == container) { hits++; hit[hits] = id }
        }
        if (hits == 1) chosen = hit[1]
        else if (hits == 0) {
          printf "status\terror\tcontainer not found: %s\n", safe(container)
          exit
        } else {
          printf "status\terror\tcontainer name is ambiguous: %s\n", safe(container)
          sort_ids(hit, hits)
          for (i = 1; i <= hits; i++) printf "choice\t%s\t%s\n", safe(name[hit[i]]), safe(hit[i])
          exit
        }
      }
    }
  } else {
    ncand = 0
    for (i = 1; i <= nr; i++) cands[++ncand] = roots[i]
    for (i = 1; i <= nu_un; i++) cands[++ncand] = unreached[i]
    if (ncand == 1 && nr == 1 && nu_un == 0) {
      chosen = roots[1]
    } else {
      if (nr == 0)
        printf "status\tchoice\tno indegree-zero deployable; pass --container. Charting every deployable is map-containers.\n"
      else
        printf "status\tchoice\tseveral deployables; pass --container. Charting every deployable is map-containers.\n"
      sort_ids(cands, ncand)
      for (i = 1; i <= ncand; i++) printf "choice\t%s\t%s\n", safe(name[cands[i]]), safe(cands[i])
      exit
    }
  }

  delete reached
  bfs(chosen)
  ncomp = 0
  for (i = 1; i <= nn; i++) {
    id = nid[i]
    if ((id in is_project) && (id in reached)) comps[++ncomp] = id
  }
  sort_ids(comps, ncomp)

  noutside = 0
  for (i = 1; i <= nn; i++) {
    id = nid[i]
    if ((id in is_project) && !(id in reached)) noutside++
  }

  ninternal = 0
  nexternal = 0
  nunresolved = 0
  nother = 0
  nviol = 0
  for (i = 1; i <= ne; i++) {
    if (!(efrom[i] in reached)) continue
    if (eclass[i] == "project" && (eto[i] in reached)) {
      ninternal++
      if (is_violation(efrom[i], eto[i])) nviol++
    } else if (eclass[i] == "package") nexternal++
    else if (eclass[i] == "unresolved") nunresolved++
    else nother++
  }

  thin = (ncomp <= 1 || ninternal == 0) ? "yes" : "no"

  for (i = 1; i <= ncomp; i++) {
    id = comps[i]
    if (groupby == "namespace") gcur[id] = namespace_of(id)
    else if (groupby == "layer") gcur[id] = layer_of(id)
    else gcur[id] = directory_of(path[id] != "" ? path[id] : id)
  }

  aggregated = "no"
  note = "Aggregated: no."
  if (thin == "no" && ncomp > threshold + 0) {
    reduced = 0
    delete ug
    nu = 0
    for (i = 1; i <= ncomp; i++) {
      id = comps[i]
      if (!(gcur[id] in ug)) { ug[gcur[id]] = 1; nu++ }
    }
    # The current groups are already under the threshold, but the components
    # are not. Collapse to one node per group. That is the aggregation.
    if (nu < ncomp && nu <= threshold + 0) reduced = 1
    for (round = 0; round < 32 && nu > threshold + 0; round++) {
      moved = 0
      for (i = 1; i <= ncomp; i++) {
        if (parent_group(gcur[comps[i]]) != gcur[comps[i]]) moved = 1
      }
      if (!moved) break
      for (i = 1; i <= ncomp; i++) gcur[comps[i]] = parent_group(gcur[comps[i]])
      reduced = 1
      delete ug
      nu = 0
      for (i = 1; i <= ncomp; i++) {
        if (!(gcur[comps[i]] in ug)) { ug[gcur[comps[i]]] = 1; nu++ }
      }
    }
    if (reduced && nu < ncomp) {
      aggregated = "yes"
      extra = ""
      if (nu > threshold + 0) extra = " The coarser groups are still above the threshold."
      note = sprintf("Aggregated: yes. %d components exceeded the node threshold of %d, so this view draws %d %s groups.%s No component was dropped. Every declared reference is in the evidence table.", ncomp, threshold + 0, nu, groupby, extra)
    } else {
      note = sprintf("Over the node threshold of %d (%d components). No coarser grouping reduced the view, so every component is drawn. No component was dropped.", threshold + 0, ncomp)
    }
  }

  printf "status\tok\n"
  printf "meta\tcontainer_name\t%s\n", safe(name[chosen])
  printf "meta\tcontainer_id\t%s\n", safe(chosen)
  printf "meta\tgrouping\t%s\n", groupby
  printf "meta\taggregated\t%s\n", aggregated
  printf "meta\taggregate_note\t%s\n", note
  printf "meta\tthin\t%s\n", thin
  printf "meta\tcomponents\t%d\n", ncomp
  printf "meta\tedges\t%d\n", ninternal
  printf "meta\texternal\t%d\n", nexternal
  printf "meta\tunresolved\t%d\n", nunresolved
  printf "meta\toutside\t%d\n", noutside
  printf "meta\tviolations\t%d\n", nviol
  printf "meta\tlayers_declared\t%s\n", (nlayers > 0 ? "yes" : "no")
  printf "meta\tthreshold\t%d\n", threshold + 0

  if (thin == "yes") {
    printf "meta\tdrawn_edges\t0\n"
  } else if (aggregated == "yes") {
    emit_aggregated()
  } else {
    emit_components()
  }

  # Evidence for every edge that leaves a component in this container.
  er = 0
  for (i = 1; i <= ne; i++) {
    if (!(efrom[i] in reached)) continue
    er++
    eorder[er] = i
  }
  for (i = 1; i <= er; i++)
    for (j = i + 1; j <= er; j++) {
      a = eorder[i]
      b = eorder[j]
      as = name[efrom[a]] "\t" (efrom[a] in name ? "" : "") name_of_to(a) "\t" ekind[a] "\t" eevidence[a]
      bs = name[efrom[b]] "\t" name_of_to(b) "\t" ekind[b] "\t" eevidence[b]
      if (bs < as) { t = eorder[i]; eorder[i] = eorder[j]; eorder[j] = t }
    }
  for (i = 1; i <= er; i++) {
    a = eorder[i]
    printf "row\t| %s | %s | %s | %s |\n", md(safe(name[efrom[a]])), md(safe(name_of_to(a))), md(safe(ekind[a])), md(safe(eevidence[a]))
    if (eclass[a] == "project" && (eto[a] in reached) && is_violation(efrom[a], eto[a]))
      printf "vio\t| %s | %s | %s |\n", md(safe(name[efrom[a]])), md(safe(name[eto[a]])), md(safe(eevidence[a]))
    if (eclass[a] == "unresolved")
      printf "unr\t| %s | %s | %s |\n", md(safe(name[efrom[a]])), md(safe(eto[a])), md(safe(eevidence[a]))
  }
}

function name_of_to(i) {
  if (eto[i] in name) return name[eto[i]]
  return eto[i]
}
function is_violation(from, to,   lf, lt) {
  if (nlayers == 0) return 0
  lf = layer_of(from)
  lt = layer_of(to)
  if (!(lf in layer_index) || !(lt in layer_index)) return 0
  return layer_index[lf] > layer_index[lt]
}
function group_key(g) {
  if (groupby == "layer") {
    if (g in layer_index) return sprintf("0%04d", layer_index[g])
    return "1" g
  }
  return g
}
function collect_groups(   i, g) {
  ng = 0
  delete gseen
  for (i = 1; i <= ncomp; i++) {
    g = gcur[comps[i]]
    if (g in gseen) continue
    gseen[g] = 1
    groups[++ng] = g
  }
  for (i = 1; i <= ng; i++)
    for (j = i + 1; j <= ng; j++)
      if (group_key(groups[j]) < group_key(groups[i])) {
        t = groups[i]; groups[i] = groups[j]; groups[j] = t
      }
}
function emit_components(   i, id, g, gi, members, nm, label, vio, drawn) {
  collect_groups()
  drawn = 0
  printf "mmd\t  title Components of %s\n", safe(name[chosen])
  printf "mmd\t  Container_Boundary(c4box, \"%s\", \"deployable\") {\n", safe(name[chosen])
  printf "dsl\tworkspace {\n"
  printf "dsl\t  model {\n"
  printf "dsl\t    c4system = softwareSystem \"%s\" {\n", safe(name[chosen])
  printf "dsl\t      c4container = container \"%s\" \"deployable\" {\n", safe(name[chosen])
  for (gi = 1; gi <= ng; gi++) {
    g = groups[gi]
    printf "mmd\t    Boundary(grp_%d, \"%s\", \"%s\") {\n", gi - 1, safe(g), groupby
    printf "dsl\t        group \"%s\" {\n", safe(g)
    nm = 0
    for (i = 1; i <= ncomp; i++) {
      id = comps[i]
      if (gcur[id] != g) continue
      members[++nm] = id
    }
    sort_ids(members, nm)
    for (i = 1; i <= nm; i++) {
      id = members[i]
      alias[id] = uniq(alias_of(id))
      printf "mmd\t      Component(%s, \"%s\", \"%s\", \"%s\")\n", alias[id], safe(name[id]), safe(eco[id]), safe(path[id] != "" ? path[id] : id)
      printf "dsl\t          %s = component \"%s\" \"%s\" \"%s\"\n", alias[id], safe(name[id]), safe(path[id] != "" ? path[id] : id), safe(eco[id])
    }
    printf "mmd\t    }\n"
    printf "dsl\t        }\n"
  }
  printf "mmd\t  }\n"
  for (i = 1; i <= ne; i++) {
    if (eclass[i] != "project") continue
    if (!(efrom[i] in reached) || !(eto[i] in reached)) continue
    label = edge_label(ekind[i], eevidence[i])
    vio = is_violation(efrom[i], eto[i])
    if (vio) label = label ", layer violation"
    printf "mmd\t  Rel(%s, %s, \"%s\")\n", alias[efrom[i]], alias[eto[i]], label
    if (vio) printf "mmd\t  UpdateRelStyle(%s, %s, \"#b00020\", \"#b00020\", 0, 0)\n", alias[efrom[i]], alias[eto[i]]
    if (vio) {
      printf "dsl\t      %s -> %s \"%s\" {\n", alias[efrom[i]], alias[eto[i]], label
      printf "dsl\t        tags \"LayerViolation\"\n"
      printf "dsl\t      }\n"
    } else {
      printf "dsl\t      %s -> %s \"%s\"\n", alias[efrom[i]], alias[eto[i]], label
    }
    drawn++
  }
  printf "dsl\t      }\n"
  printf "dsl\t    }\n"
  printf "dsl\t  }\n"
  printf "dsl\t  views {\n"
  printf "dsl\t    component c4container \"Components\" {\n"
  printf "dsl\t      include *\n"
  printf "dsl\t      autoLayout lr\n"
  printf "dsl\t    }\n"
  if (nviol > 0) {
    printf "dsl\t    styles {\n"
    printf "dsl\t      relationship \"LayerViolation\" {\n"
    printf "dsl\t        color #b00020\n"
    printf "dsl\t      }\n"
    printf "dsl\t    }\n"
  }
  printf "dsl\t  }\n"
  printf "dsl\t}\n"
  printf "meta\tdrawn_edges\t%d\n", drawn
}
function emit_aggregated(   i, g, gi, id, label, vio, drawn, key, fc, tc, members, nm, rep) {
  collect_groups()
  drawn = 0
  printf "mmd\t  title Components of %s\n", safe(name[chosen])
  printf "mmd\t  Container_Boundary(c4box, \"%s\", \"deployable\") {\n", safe(name[chosen])
  printf "dsl\tworkspace {\n"
  printf "dsl\t  model {\n"
  printf "dsl\t    c4system = softwareSystem \"%s\" {\n", safe(name[chosen])
  printf "dsl\t      c4container = container \"%s\" \"deployable\" {\n", safe(name[chosen])
  for (gi = 1; gi <= ng; gi++) {
    g = groups[gi]
    nm = 0
    for (i = 1; i <= ncomp; i++) if (gcur[comps[i]] == g) nm++
    galias[g] = uniq(alias_of(g))
    printf "mmd\t    Boundary(grp_%d, \"%s\", \"%s\") {\n", gi - 1, safe(g), groupby
    printf "mmd\t      Component(%s, \"%s\", \"aggregate\", \"%d components\")\n", galias[g], safe(g), nm
    printf "mmd\t    }\n"
    printf "dsl\t        group \"%s\" {\n", safe(g)
    printf "dsl\t          %s = component \"%s\" \"%d components\" \"aggregate\"\n", galias[g], safe(g), nm
    printf "dsl\t        }\n"
  }
  printf "mmd\t  }\n"
  delete pair_count
  delete pair_vio
  delete pair_label
  np = 0
  for (i = 1; i <= ne; i++) {
    if (eclass[i] != "project") continue
    if (!(efrom[i] in reached) || !(eto[i] in reached)) continue
    fc = gcur[efrom[i]]
    tc = gcur[eto[i]]
    if (fc == tc) continue
    key = fc "\t" tc
    if (!(key in pair_count)) {
      pair_count[key] = 0
      pair_order[++np] = key
      pair_from[key] = fc
      pair_to[key] = tc
      pair_label[key] = edge_label(ekind[i], eevidence[i])
      pair_vio[key] = 0
    }
    pair_count[key]++
    if (is_violation(efrom[i], eto[i])) pair_vio[key] = 1
  }
  for (i = 1; i <= np; i++)
    for (j = i + 1; j <= np; j++)
      if (pair_order[j] < pair_order[i]) {
        t = pair_order[i]; pair_order[i] = pair_order[j]; pair_order[j] = t
      }
  for (i = 1; i <= np; i++) {
    key = pair_order[i]
    label = pair_label[key]
    if (pair_count[key] > 1) label = label " (" pair_count[key] ")"
    if (pair_vio[key]) label = label ", layer violation"
    printf "mmd\t  Rel(%s, %s, \"%s\")\n", galias[pair_from[key]], galias[pair_to[key]], label
    if (pair_vio[key]) printf "mmd\t  UpdateRelStyle(%s, %s, \"#b00020\", \"#b00020\", 0, 0)\n", galias[pair_from[key]], galias[pair_to[key]]
    if (pair_vio[key]) {
      printf "dsl\t      %s -> %s \"%s\" {\n", galias[pair_from[key]], galias[pair_to[key]], label
      printf "dsl\t        tags \"LayerViolation\"\n"
      printf "dsl\t      }\n"
    } else {
      printf "dsl\t      %s -> %s \"%s\"\n", galias[pair_from[key]], galias[pair_to[key]], label
    }
    drawn++
  }
  printf "dsl\t      }\n"
  printf "dsl\t    }\n"
  printf "dsl\t  }\n"
  printf "dsl\t  views {\n"
  printf "dsl\t    component c4container \"Components\" {\n"
  printf "dsl\t      include *\n"
  printf "dsl\t      autoLayout lr\n"
  printf "dsl\t    }\n"
  if (nviol > 0) {
    printf "dsl\t    styles {\n"
    printf "dsl\t      relationship \"LayerViolation\" {\n"
    printf "dsl\t        color #b00020\n"
    printf "dsl\t      }\n"
    printf "dsl\t    }\n"
  }
  printf "dsl\t  }\n"
  printf "dsl\t}\n"
  printf "meta\tdrawn_edges\t%d\n", drawn
}
AWK

awk_rc=$?
[[ "$awk_rc" -eq 0 ]] || die "could not read the graph" 1

mmd="$tmp.mmd"
dslf="$tmp.dsl"
rows="$tmp.rows"
vios="$tmp.vios"
unrs="$tmp.unrs"
trap 'rm -f "$tmp" "$mmd" "$dslf" "$rows" "$vios" "$unrs"' EXIT
: >"$mmd"
: >"$dslf"
: >"$rows"
: >"$vios"
: >"$unrs"

status=""
status_msg=""
declare -A META=()
choices=()
while IFS=$'\t' read -r kind payload || [[ -n "${kind:-}" ]]; do
  [[ -n "${kind:-}" ]] || continue
  case "$kind" in
  status)
    status="${payload%%$'\t'*}"
    if [[ "$payload" == *$'\t'* ]]; then
      status_msg="${payload#*$'\t'}"
    else
      status_msg=""
    fi
    ;;
  choice) choices+=("$payload") ;;
  meta)
    META["${payload%%$'\t'*}"]="${payload#*$'\t'}"
    ;;
  mmd) printf '%s\n' "$payload" >>"$mmd" ;;
  dsl) printf '%s\n' "$payload" >>"$dslf" ;;
  row) printf '%s\n' "$payload" >>"$rows" ;;
  vio) printf '%s\n' "$payload" >>"$vios" ;;
  unr) printf '%s\n' "$payload" >>"$unrs" ;;
  *) ;;
  esac
done <"$tmp"

meta_get() {
  printf '%s' "${META[$1]:-}"
}

if [[ "$status" == "choice" ]]; then
  printf 'render-components.sh: %s\n' "$status_msg" >&2
  for c in "${choices[@]+"${choices[@]}"}"; do
    printf '  %s\n' "$c" >&2
  done
  exit 3
fi
if [[ "$status" == "error" ]]; then
  printf 'render-components.sh: %s\n' "$status_msg" >&2
  for c in "${choices[@]+"${choices[@]}"}"; do
    printf '  %s\n' "$c" >&2
  done
  exit 1
fi
if [[ "$status" == "empty" ]]; then
  {
    printf '# Component view\n\n'
    printf 'Generated on %s from %s.\n\n' "$generated_on" "$source_name"
    printf 'Thin result: yes. The graph has no internal modules. A one-box diagram is not the answer.\n\n'
    printf 'Neighboring rungs:\n\n'
    printf '%s\n' '- `/architecture:map-landscape` charts the repositories this one sits among.'
    printf '%s\n' '- `/architecture:map-containers` charts the deployables. This view is one of them.'
    printf '%s\n' '- `/architecture:improve` looks for module-design friction inside a module.'
    if [[ -n "$notes" ]]; then
      printf '\n'
      cat "$notes"
    fi
  } >"$outdir/components.md"
  rm -f "$outdir/components.dsl"
  write_summary "none" 0 0 0 0 no yes 0 0
  exit 0
fi
[[ "$status" == "ok" ]] || die "the graph produced no component view" 1

cname="$(meta_get container_name)"
cid="$(meta_get container_id)"
grouping="$(meta_get grouping)"
agg="$(meta_get aggregated)"
note="$(meta_get aggregate_note)"
thin="$(meta_get thin)"
ncomp="$(meta_get components)"
nedges="$(meta_get edges)"
ndrawn="$(meta_get drawn_edges)"
[[ -n "$ndrawn" ]] || ndrawn=0
nviol="$(meta_get violations)"
next="$(meta_get external)"
nunr="$(meta_get unresolved)"
noutside="$(meta_get outside)"
layers_declared="$(meta_get layers_declared)"

{
  printf '# Component view\n\n'
  printf 'Generated on %s from %s.\n\n' "$generated_on" "$source_name"
  printf 'Container: %s (`%s`).\n' "$cname" "$cid"
  printf 'Grouping: %s.\n' "$grouping"
  if [[ "$thin" == "yes" ]]; then
    printf 'Dialect: %s. No diagram is drawn for a thin result.\n\n' "$dialect"
  elif [[ "$dialect" == "mermaid" ]]; then
    printf 'Dialect: mermaid, a C4Component diagram of this one container.\n\n'
  else
    printf 'Dialect: structurizr, a component view of this one container.\n\n'
  fi
  if [[ "$thin" == "yes" ]]; then
    printf 'Thin result: yes. Container `%s` is a single module with no internal component edges. A one-box diagram is not the answer.\n\n' "$cname"
    printf 'Neighboring rungs:\n\n'
    printf '%s\n' '- `/architecture:map-landscape` charts the repositories this one sits among.'
    printf '%s\n' '- `/architecture:map-containers` charts the deployables. This view is one of them.'
    printf '%s\n' '- `/architecture:improve` looks for module-design friction inside the single module.'
    printf '\n'
  elif [[ "$dialect" == "mermaid" ]]; then
    printf '```mermaid\nC4Component\n'
    cat "$mmd"
    printf '```\n\n'
  else
    printf 'Diagram: `components.dsl`.\n\n'
  fi
  printf '%s\n\n' "$note"
  printf 'External packages collapsed: %s. Their declarations are in the evidence table.\n' "$next"
  printf 'Unresolved references: %s.\n' "$nunr"
  if [[ "${noutside:-0}" -gt 0 ]]; then
    printf 'Modules outside this container: %s. They belong to other deployables and are not drawn here.\n' "$noutside"
  fi
  printf '\n## Edges\n\n'
  printf 'Every edge below is directed. The evidence cell is the file and the matched declaration.\n\n'
  printf '| From | To | Kind | Evidence |\n|---|---|---|---|\n'
  if [[ -s "$rows" ]]; then
    cat "$rows"
  fi
  printf '\n## Layer violations\n\n'
  if [[ "$layers_declared" == "yes" ]]; then
    printf 'Layer violations are informational. This run does not fail because of them. Enforcement belongs to the consumer'\''s architecture tests.\n\n'
    if [[ -s "$vios" ]]; then
      printf '| From | To | Evidence |\n|---|---|---|\n'
      cat "$vios"
    else
      printf 'None.\n'
    fi
  else
    printf 'No layering convention was declared, so no edge is marked as a violation.\n'
  fi
  printf '\n## Unresolved\n\n'
  if [[ -s "$unrs" ]]; then
    printf '| From | Reference | Evidence |\n|---|---|---|\n'
    cat "$unrs"
  else
    printf 'None.\n'
  fi
  if [[ -n "$notes" ]]; then
    printf '\n'
    cat "$notes"
  fi
} >"$outdir/components.md"

if [[ "$dialect" == "structurizr" && "$thin" != "yes" ]]; then
  cat "$dslf" >"$outdir/components.dsl"
else
  rm -f "$outdir/components.dsl"
fi

summary_name="$cname"
[[ -n "$summary_name" ]] || summary_name="none"
write_summary "$summary_name" "$ncomp" "$nedges" "$ndrawn" "$nviol" "$agg" "$thin" "$next" "$nunr"
exit 0
