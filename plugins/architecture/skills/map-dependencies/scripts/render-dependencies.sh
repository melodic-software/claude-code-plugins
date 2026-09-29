#!/usr/bin/env bash
# Render dependency-graph.json as a mermaid flowchart of internal edges.
#
# WHY. The JSON document is the model. This script is the human view, and it
# is the reader that refuses a document it cannot match line by line. A
# reformatted but valid JSON file exits 1 with a message and writes nothing.
# An empty diagram is not what an unrecognized ecosystem looks like: result
# "unknown" is prose, with no flowchart.
#
# Usage:
#   render-dependencies.sh --record <dependency-graph.json> --out <dir>
#       [--include-external | --external-only] [--cycles-only]
#   render-dependencies.sh --help
#
# Writes <dir>/dependency-graph.md. Prints one summary line on stdout:
#
#   dependencies: result=<ok|unknown> ecosystem=<name> nodes=<n>
#   internal_edges=<i> external_edges=<e> unresolved=<u> membership=<m>
#   unread_files=<f> cycles=<c> aggregated=<yes|no> drawn_edges=<d>
#
# membership counts unresolved solution members. unread_files counts files
# with reference tags the collector did not turn into an edge.
#
# The flowchart is mermaid `flowchart` in both landscape_dialect settings.
# This script does not read the dialect. External package nodes are collapsed
# unless --include-external (internal and external) or --external-only.
# --cycles-only draws only internal edges that sit on a reported cycle.
# Above the record's node_threshold, the flowchart aggregates to directories
# and says so. The JSON stays at project resolution.
#
# Portability: bash plus POSIX awk. No jq, no `grep -P`, no python.
#
# Exit: 0 = written, or result unknown written as prose; 1 = unreadable
# record, not schema_version 1, or not the one-object-per-line layout
# dependency-graph.sh writes (nothing is written); 2 = usage.
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'render-dependencies.sh: %s\n' "$1" >&2
  exit "$2"
}

record=""
outdir=""
include_external=0
external_only=0
cycles_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --record)
    [[ $# -ge 2 ]] || die "--record needs a file" 2
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
  --include-external)
    include_external=1
    shift
    ;;
  --external-only)
    external_only=1
    shift
    ;;
  --cycles-only)
    cycles_only=1
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
if [[ "$include_external" -eq 1 && "$external_only" -eq 1 ]]; then
  die "--include-external and --external-only are mutually exclusive" 2
fi
[[ -r "$record" ]] || die "cannot read record: $record" 1
[[ -d "$outdir" ]] || die "not a directory: $outdir" 1
grep -Eq '"schema_version"[[:space:]]*:[[:space:]]*1[[:space:]]*([,}]|$)' "$record" ||
  die "not a schema_version 1 record: $record" 1

# Readers match objects by line. A valid JSON document in another layout
# (compacted, or one key per line) would match nothing. Each array is either
# empty on its key's line, or opens alone on that line and holds one object
# per line until its closing bracket.
read -r -d '' LAYOUT_AWK <<'AWK' || true
BEGIN {
  shape["nodes"] = "^[[:space:]]*[{]\"id\":"
  shape["edges"] = "^[[:space:]]*[{]\"from\":"
  shape["cycles"] = "^[[:space:]]*[{]\"id\":"
  shape["findings"] = "^[[:space:]]*[{]\"kind\":"
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
  if (problem == "" && open == "") open_array("cycles")
  if (problem == "" && open == "") open_array("findings")
  if (problem != "") exit
}
END {
  if (problem == "" && open != "") problem = "the " open " array never closes"
  if (problem == "" && !("nodes" in seen)) problem = "no nodes array was found"
  if (problem == "" && !("edges" in seen)) problem = "no edges array was found"
  if (problem == "" && !("cycles" in seen)) problem = "no cycles array was found"
  if (problem == "" && !("findings" in seen)) problem = "no findings array was found"
  print problem
}
AWK
layout_problem="$(awk "$LAYOUT_AWK" "$record")"
[[ -z "$layout_problem" ]] ||
  die "record is not in the one-object-per-line layout dependency-graph.sh writes ($layout_problem); regenerate it: $record" 1

outfile="$outdir/dependency-graph.md"
errfile="$(mktemp)"
trap 'rm -f "$errfile"' EXIT

summary="$(
  awk -v outfile="$outfile" \
    -v include_external="$include_external" \
    -v external_only="$external_only" \
    -v cycles_only="$cycles_only" '
function json_string_after_key(line, key,    p, i, c, esc, val) {
  p = index(line, "\"" key "\"")
  if (p == 0) return ""
  i = p + length(key) + 2
  while (i <= length(line) && substr(line, i, 1) ~ /[[:space:]]/) i++
  if (substr(line, i, 1) != ":") return ""
  i++
  while (i <= length(line) && substr(line, i, 1) ~ /[[:space:]]/) i++
  if (substr(line, i, 1) != "\"") return ""
  i++
  val = ""
  esc = 0
  while (i <= length(line)) {
    c = substr(line, i, 1)
    if (esc) {
      if (c == "n") val = val "\n"
      else if (c == "t") val = val "\t"
      else if (c == "r") val = val "\r"
      else val = val c
      esc = 0
    } else if (c == "\\") esc = 1
    else if (c == "\"") return val
    else val = val c
    i++
  }
  return val
}
function parent_dir(path,    slash) {
  slash = match(path, /\/[^\/]*$/)
  if (slash == 0) return "."
  return substr(path, 1, RSTART - 1)
}
function edge_on_cycle(from, to,    i, needle) {
  needle = " -> " from " -> " to " -> "
  for (i = 1; i <= cn; i++) if (index(" -> " cycle_id[i] " -> ", needle) > 0) return 1
  return 0
}
function mermaid_label(s) {
  gsub(/"/, "'\''", s)
  gsub(/]/, ")", s)
  gsub(/\r/, "", s)
  gsub(/\n/, " ", s)
  return s
}
function want_vertex(key, label) {
  if (key == "" || key in vseen) return
  vseen[key] = 1
  vn++
  vorder[vn] = key
  vlabel[key] = label
}
function want_draw(src, dst) {
  if (src == "" || dst == "" || src == dst) {
    if (src != "" && src == dst) intra++
    return
  }
  k = src "\t" dst
  if (k in dseen) return
  dseen[k] = 1
  dn++
  dsrc[dn] = src
  ddst[dn] = dst
  want_vertex(src, src_label(src))
  want_vertex(dst, dst_label(dst))
}
function src_label(key) {
  if (key in pkg_label) return pkg_label[key]
  return key
}
function dst_label(key) {
  if (key in pkg_label) return pkg_label[key]
  return key
}
function sort_at(arr, n,    i, j, tmp) {
  for (i = 2; i <= n; i++) {
    tmp = arr[i]
    j = i - 1
    while (j >= 1 && arr[j] > tmp) {
      arr[j + 1] = arr[j]
      j--
    }
    arr[j + 1] = tmp
  }
}
function add_line(s) { md = md s "\n" }
/^[[:space:]]*"result"[[:space:]]*:/ { result = json_string_after_key($0, "result"); next }
/^[[:space:]]*"message"[[:space:]]*:/ { message = json_string_after_key($0, "message"); next }
/^[[:space:]]*"ecosystem"[[:space:]]*:/ { ecosystem = json_string_after_key($0, "ecosystem"); next }
/^[[:space:]]*"node_threshold"[[:space:]]*:/ {
  if (match($0, /[0-9]+/)) threshold = substr($0, RSTART, RLENGTH) + 0
  next
}
/^[[:space:]]*"cycles_truncated"[[:space:]]*:/ {
  if ($0 ~ /true/) truncated = 1
  next
}
/^[[:space:]]*\{"id":/ {
  id = json_string_after_key($0, "id")
  if ($0 ~ /"kind":/) {
    nn++
    node_id[nn] = id
    node_name[nn] = json_string_after_key($0, "name")
    node_path[nn] = json_string_after_key($0, "path")
    node_kind[nn] = json_string_after_key($0, "kind")
    if (node_kind[nn] == "package") pkg_label[id] = node_name[nn]
  } else {
    cn++
    cycle_id[cn] = id
  }
  next
}
/^[[:space:]]*\{"from":/ {
  en++
  edge_from[en] = json_string_after_key($0, "from")
  edge_to[en] = json_string_after_key($0, "to")
  edge_kind[en] = json_string_after_key($0, "kind")
  edge_status[en] = json_string_after_key($0, "status")
  edge_evidence[en] = json_string_after_key($0, "evidence")
  next
}
/^[[:space:]]*\{"kind":/ {
  fn++
  finding_kind[fn] = json_string_after_key($0, "kind")
  finding_evidence[fn] = json_string_after_key($0, "evidence")
  if (finding_kind[fn] == "unread-reference-tags") unread_n++
  else membership_n++
  next
}
END {
  if (result != "ok" && result != "unknown") {
    print "record has no result of ok or unknown" > "/dev/stderr"
    exit 1
  }
  if (threshold == 0) threshold = 40
  project_n = 0
  internal_n = 0
  external_n = 0
  external_edges = 0
  unresolved_n = 0
  for (i = 1; i <= nn; i++) if (node_kind[i] == "project") project_n++
  for (i = 1; i <= nn; i++) if (node_kind[i] == "package") external_n++
  for (i = 1; i <= en; i++) {
    if (edge_kind[i] == "project" && edge_status[i] == "resolved") internal_n++
    if (edge_kind[i] == "package" && edge_status[i] == "resolved") external_edges++
    if (edge_kind[i] == "project" && edge_status[i] == "unresolved") unresolved_n++
  }
  aggregated = (result == "ok" && project_n > threshold) ? 1 : 0
  draw_project = (external_only == 0)
  draw_package = (include_external == 1 || external_only == 1)
  if (cycles_only == 1) draw_package = 0

  intra = 0
  vn = 0
  dn = 0
  if (result == "ok") {
    for (i = 1; i <= en; i++) {
      if (edge_kind[i] == "project" && edge_status[i] == "resolved" && draw_project) {
        if (cycles_only == 1 && !edge_on_cycle(edge_from[i], edge_to[i])) continue
        src = aggregated ? parent_dir(edge_from[i]) : edge_from[i]
        dst = aggregated ? parent_dir(edge_to[i]) : edge_to[i]
        want_draw(src, dst)
      } else if (edge_kind[i] == "package" && edge_status[i] == "resolved" && draw_package) {
        src = aggregated ? parent_dir(edge_from[i]) : edge_from[i]
        dst = edge_to[i]
        want_draw(src, dst)
      }
    }
    if (draw_project && cycles_only == 0) {
      for (i = 1; i <= nn; i++) {
        if (node_kind[i] != "project") continue
        key = aggregated ? parent_dir(node_id[i]) : node_id[i]
        want_vertex(key, key)
      }
    }
  }

  sort_at(vorder, vn)
  for (i = 1; i <= vn; i++) vid[vorder[i]] = "n" i

  md = ""
  add_line("# Dependency graph")
  add_line("")
  if (result == "unknown") {
    add_line("- Result: unknown")
    add_line("- Ecosystem: " ecosystem)
    add_line("")
    if (message != "") add_line(message)
    add_line("")
    add_line("No diagram. An unrecognized ecosystem is not an empty graph.")
    add_line("")
  } else {
    add_line("## Cycles")
    add_line("")
    if (cn == 0) add_line("None.")
    else for (i = 1; i <= cn; i++) add_line("- `" cycle_id[i] "`")
    if (truncated) add_line("")
    if (truncated) add_line("Cycle search stopped early.")
    add_line("")
    add_line("- Result: ok")
    add_line("- Ecosystem: " ecosystem)
    add_line("- Node threshold: " threshold)
    if (message != "") {
      add_line("")
      add_line(message)
    }
    add_line("")
    add_line("## Unresolved")
    add_line("")
    unresolved_lines = 0
    for (i = 1; i <= en; i++) {
      if (edge_status[i] == "unresolved") {
        ev = edge_evidence[i]
        gsub(/`/, "'\''", ev)
        add_line("- `" ev "`")
        unresolved_lines++
      }
    }
    for (i = 1; i <= fn; i++) {
      ev = finding_evidence[i]
      gsub(/`/, "'\''", ev)
      add_line("- `" ev "`")
      unresolved_lines++
    }
    if (unresolved_lines == 0) add_line("None.")
    add_line("")
    add_line("## External packages")
    add_line("")
    if (draw_package) add_line("External packages drawn: " external_n ".")
    else add_line("External packages collapsed: " external_n ". Pass --include-external to draw them.")
    add_line("")
    add_line("## Diagram")
    add_line("")
    if (aggregated) {
      add_line("Aggregated to directory level: " project_n " internal project nodes exceeded the documented node threshold of " threshold ". dependency-graph.json stays at project resolution.")
      add_line("")
    }
    if (aggregated && intra > 0) {
      add_line("Intra-directory project edges omitted by aggregation: " intra ".")
      add_line("")
    }
    if (dn == 0 && vn == 0) {
      if (cycles_only == 1) add_line("No cycle edges to draw.")
      else if (external_only == 1) add_line("No external package edges to draw.")
      else add_line("No internal nodes to draw.")
      add_line("")
    } else {
      add_line("```mermaid")
      add_line("flowchart LR")
      for (i = 1; i <= vn; i++) {
        key = vorder[i]
        add_line("  " vid[key] "[\"" mermaid_label(vlabel[key]) "\"]")
      }
      for (i = 1; i <= dn; i++) {
        add_line("  " vid[dsrc[i]] " --> " vid[ddst[i]])
      }
      add_line("```")
      add_line("")
    }
  }
  print md > outfile
  close(outfile)
  printf "dependencies: result=%s ecosystem=%s nodes=%d internal_edges=%d external_edges=%d unresolved=%d membership=%d unread_files=%d cycles=%d aggregated=%s drawn_edges=%d\n",
    result, ecosystem, nn, internal_n, external_edges, unresolved_n, membership_n, unread_n, cn, (aggregated ? "yes" : "no"), dn
}
' "$record" 2>"$errfile"
)"
rc=$?
if [[ "$rc" -ne 0 ]]; then
  rm -f "$outfile"
  errtext="$(cat "$errfile")"
  [[ -n "$errtext" ]] || errtext="renderer failed"
  die "$errtext" 1
fi
printf '%s\n' "$summary"
exit 0
