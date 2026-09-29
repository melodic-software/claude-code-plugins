#!/usr/bin/env bash
# Render events.json. Findings are always written. --unrouted-only draws only
# orphan and unresolved edges. Broadcast is a dotted arrow. Point-to-point is solid.
#
# Usage:
#   render-events.sh --record <file> --out <dir> [--unrouted-only]
#   render-events.sh --help
#
# Writes events.md, a mermaid flowchart. It reads no dialect key: a message
# topology is neither a data diagram nor a C4 system view.
#
# Prints:
#   events: messages=<n> publishers=<n> consumers=<n> unresolved=<n> orphans=<n> unrouted_only=<yes|no>
#
# Exit: 0 written; 1 bad record (nothing written); 2 usage.
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'render-events.sh: %s\n' "$1" >&2
  exit "$2"
}

record=""
outdir=""
unrouted="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h) usage; exit 0 ;;
  --record) [[ $# -ge 2 ]] || die "--record needs a path" 2; record="$2"; shift 2 ;;
  --record=*) record="${1#--record=}"; shift ;;
  --out) [[ $# -ge 2 ]] || die "--out needs a directory" 2; outdir="$2"; shift 2 ;;
  --out=*) outdir="${1#--out=}"; shift ;;
  --unrouted-only) unrouted="yes"; shift ;;
  *) die "unknown argument: $1" 2 ;;
  esac
done

[[ -n "$record" && -n "$outdir" ]] || { usage >&2; exit 2; }
[[ -r "$record" ]] || die "cannot read record: $record" 1
[[ -d "$outdir" ]] || die "not a directory: $outdir" 1
grep -q '"schema_version"[[:space:]]*:[[:space:]]*1' "$record" || die "not a schema_version 1 record: $record" 1

layout_problem="$(awk '
  function open_array(key,   rest) {
    if (!match($0, "\"" key "\"[[:space:]]*:[[:space:]]*\\[")) return
    rest = substr($0, RSTART + RLENGTH)
    if (rest ~ /^[[:space:]]*\]/) { seen[key] = 1; return }
    if (substr($0, 1, RSTART - 1) ~ /^[[:space:]]*$/ && rest ~ /^[[:space:]]*$/) { open = key; return }
    problem = "the " key " array does not start on a line of its own"
  }
  BEGIN {
    shape["messages"] = "^[[:space:]]*[{]\"id\":\""
    shape["edges"] = "^[[:space:]]*[{]\"from\":\""
    shape["findings"] = "^[[:space:]]*[{]\"kind\":\""
  }
  open != "" {
    if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) { seen[open] = 1; open = ""; next }
    if ($0 !~ shape[open]) { problem = "line " NR " is not one " open " object"; exit }
    next
  }
  {
    open_array("messages")
    if (problem == "" && open == "") open_array("edges")
    if (problem == "" && open == "") open_array("findings")
    if (problem != "") exit
  }
  END {
    if (problem == "" && open != "") problem = "the " open " array never closes"
    if (problem == "" && !("messages" in seen)) problem = "no messages array was found"
    if (problem == "" && !("edges" in seen)) problem = "no edges array was found"
    if (problem == "" && !("findings" in seen)) problem = "no findings array was found"
    print problem
  }
' "$record")"
[[ -z "$layout_problem" ]] ||
  die "record is not in the one-object-per-line layout collect-events.sh writes ($layout_problem); regenerate it: $record" 1

OUT_FILE="$outdir/events.md" UNROUTED="$unrouted" awk '
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
    if (c == "\\") { i++; out = out substr(rest, i, 1); i++; continue }
    if (c == "\"") return out
    out = out c
    i++
  }
  return out
}
function jnum(line, key,    pat, i, rest, s) {
  pat = "\"" key "\""
  i = index(line, pat)
  if (i == 0) return "0"
  rest = substr(line, i + length(pat))
  if (match(rest, /^[[:space:]]*:[[:space:]]*[0-9]+/)) {
    s = substr(rest, RSTART, RLENGTH)
    sub(/^[^0-9]*/, "", s)
    return s
  }
  return "0"
}
function safe(s) {
  gsub(/"/, "\047", s)
  gsub(/\n/, " ", s)
  return s
}
function alias(s,    a) {
  a = s
  gsub(/[^A-Za-z0-9]/, "_", a)
  if (a == "" || a ~ /^[0-9]/) a = "n_" a
  return a
}
/^[[:space:]]*\{"id":/ { messages++ }
/^[[:space:]]*\{"from":/ {
  en++
  ekind[en] = jstr($0, "kind")
  edge_to[en] = jstr($0, "to")
  eres[en] = jstr($0, "resolution")
  efile[en] = jstr($0, "file")
  eline[en] = jnum($0, "line")
  if (ekind[en] == "publish" || ekind[en] == "send") publishers++
  if (ekind[en] == "consume") consumers++
  if (eres[en] == "unresolved") unresolved++
}
/^[[:space:]]*\{"kind":/ {
  fn++
  fkind[fn] = jstr($0, "kind")
  fcon[fn] = jstr($0, "contract")
  fdet[fn] = jstr($0, "detail")
  if (fkind[fn] == "orphan-publisher" || fkind[fn] == "orphan-consumer") orphans++
}
END {
  out = ENVIRON["OUT_FILE"]
  unrouted = ENVIRON["UNROUTED"]
  print "# Events" > out
  print "" > out
  print "Async topology. A dotted arrow is broadcast (publish). A solid arrow is point-to-point (send). Identity is the resolved type. Findings are listed even when the diagram is filtered." > out
  print "" > out
  print "```mermaid" > out
  print "flowchart LR" > out
  for (i = 1; i <= en; i++) {
    if (unrouted == "yes" && eres[i] != "unresolved") {
      orphan = 0
      for (j = 1; j <= fn; j++) if ((fkind[j] == "orphan-publisher" || fkind[j] == "orphan-consumer") && fcon[j] == edge_to[i]) orphan = 1
      if (!orphan) continue
    }
    a = alias(ekind[i] "_" efile[i] "_" eline[i])
    b = alias(edge_to[i] == "" ? "unresolved" : edge_to[i])
    arrow = "-->"
    if (ekind[i] == "publish") arrow = "-.->"
    label = ekind[i] " " efile[i] ":" eline[i]
    print "  " a "[\"" safe(ekind[i]) "\"] " arrow "|\"" safe(label) "\"| " b "[\"" safe(edge_to[i]) "\"]" > out
  }
  print "```" > out
  print "" > out
  print "## Findings" > out
  print "" > out
  if (fn == 0) print "none" > out
  for (i = 1; i <= fn; i++) print "- " fkind[i] " " safe(fcon[i]) " " safe(fdet[i]) > out
  print "" > out
  print "## Handoff" > out
  print "" > out
  for (i = 1; i <= en; i++) {
    if (ekind[i] != "publish" && ekind[i] != "send") continue
    print "handoff: map-events contract=" safe(edge_to[i]) " direction=" ekind[i] " file=" efile[i] " line=" eline[i] > out
  }
  close(out)
  printf "events: messages=%d publishers=%d consumers=%d unresolved=%d orphans=%d unrouted_only=%s\n", messages + 0, publishers + 0, consumers + 0, unresolved + 0, orphans + 0, unrouted
}
' "$record"
