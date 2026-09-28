#!/usr/bin/env bash
# Render flow.json as a C4 dynamic diagram.
#
# WHY. The record is the fact. This script only draws hops the collector
# cited. A reformatted record must not render as an empty sequence with exit 0.
#
# Usage:
#   render-flow.sh --record <file> --out <dir> [--dialect mermaid|structurizr]
#   render-flow.sh --help
#
# --dialect defaults to mermaid, the landscape_dialect default. map-flow reads
# that same key. A separate flow dialect is not introduced here.
#
# Writes, into <dir>:
#   flow.md    mermaid sequenceDiagram. Asynchronous hops use -->> .
#              Synchronous hops use ->> . A handoff names map-events.
#   flow.dsl   structurizr dynamic view. One dialect file is written.
#
# Consecutive hops with the same from-role, to-role, sync, resolution, and
# handoff collapse to one arrow. The artifact says how many were collapsed.
#
# Prints one summary line on stdout:
#   flow: entry=<name> hops=<n> truncated=<yes|no> unresolved=<n> handoffs=<n>
#
# Exit: 0 = written; 1 = unreadable, not schema_version 1, or not the
# one-object-per-line layout (nothing is written); 2 = usage.
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'render-flow.sh: %s\n' "$1" >&2
  exit "$2"
}

record=""
outdir=""
dialect="mermaid"

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
    [[ $# -ge 2 ]] || die "--dialect needs mermaid or structurizr" 2
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
mermaid | structurizr) ;;
*) die "--dialect must be mermaid or structurizr, got: $dialect" 2 ;;
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
/"entry"[[:space:]]*:[[:space:]]*\{"name":/ { saw_entry = 1 }
/"truncated"[[:space:]]*:/ { saw_trunc = 1 }
open != "" {
  if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) { seen[open] = 1; open = ""; next }
  if ($0 !~ /^[[:space:]]*[{]"from_role":/) { problem = "line " NR " is not one hops object"; exit }
  next
}
{
  open_array("hops")
  if (problem != "") exit
}
END {
  if (problem == "" && open != "") problem = "the hops array never closes"
  if (problem == "" && !("hops" in seen)) problem = "no hops array was found"
  if (problem == "" && !saw_entry) problem = "no entry object was found"
  if (problem == "" && !saw_trunc) problem = "no truncated field was found"
  print problem
}
' "$record")"
[[ -z "$layout_problem" ]] ||
  die "record is not in the one-object-per-line layout collect-flow.sh writes ($layout_problem); regenerate it: $record" 1

if [[ "$dialect" == "mermaid" ]]; then
  target="$outdir/flow.md"
  rm -f "$outdir/flow.dsl"
else
  target="$outdir/flow.dsl"
  rm -f "$outdir/flow.md"
fi

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
      c = substr(rest, i + 1, 1)
      if (c == "") break
      out = out c
      i += 2
      continue
    }
    if (c == "\"") break
    out = out c
    i++
  }
  return out
}
function q(s) {
  gsub(/\\/, "/", s)
  gsub(/"/, "'", s)
  return s
}
function emit(s) { print s > out }
BEGIN { out = ENVIRON["OUT_FILE"]; dialect = ENVIRON["DIALECT"] }
/"entry"[[:space:]]*:[[:space:]]*\{"name":/ {
  entry = jstr($0, "name")
  entry_file = jstr($0, "file")
  entry_line = jstr($0, "line")
}
/"truncated"[[:space:]]*:[[:space:]]*"/ {
  truncated = jstr($0, "truncated")
}
/"depth"[[:space:]]*:/ {
  if (match($0, /"depth"[[:space:]]*:[[:space:]]*[0-9]+/)) {
    s = substr($0, RSTART, RLENGTH)
    sub(/.*:[[:space:]]*/, "", s)
    depth = s
  }
}
/^[[:space:]]*[{]"from_role":/ {
  n++
  from[n] = jstr($0, "from_role")
  to[n] = jstr($0, "to_role")
  call[n] = jstr($0, "call")
  file[n] = jstr($0, "file")
  line[n] = jstr($0, "line")
  sync[n] = jstr($0, "sync")
  res[n] = jstr($0, "resolution")
  mech[n] = jstr($0, "mechanism")
  hand[n] = jstr($0, "handoff")
  if (res[n] == "unresolved") unresolved++
  if (hand[n] == "yes") handoffs++
}
END {
  # Collapse consecutive identical role pairs.
  m = 0
  i = 1
  while (i <= n) {
    j = i
    while (j < n && from[j + 1] == from[i] && to[j + 1] == to[i] && sync[j + 1] == sync[i] && res[j + 1] == res[i] && hand[j + 1] == hand[i])
      j++
    m++
    c_from[m] = from[i]
    c_to[m] = to[i]
    c_sync[m] = sync[i]
    c_res[m] = res[i]
    c_hand[m] = hand[i]
    c_call[m] = call[i]
    c_file[m] = file[i]
    c_line[m] = line[i]
    c_mech[m] = mech[i]
    c_count[m] = j - i + 1
    i = j + 1
  }
  if (dialect == "mermaid") {
    emit("# Flow")
    emit("")
    emit("Dialect: landscape_dialect=mermaid. C4 dynamic diagram, drawn as a sequence of architectural roles.")
    emit("")
    emit("Entry: `" entry "` at " entry_file ":" entry_line ".")
    emit("")
    if (truncated == "yes")
      emit("Depth truncated at " depth ". The trace stopped before entering further callees. This sequence is not the whole path.")
    else
      emit("Depth " depth " covered every followed callee. truncated=no.")
    emit("")
    emit("```mermaid")
    emit("sequenceDiagram")
    for (i = 1; i <= m; i++) {
      role_seen[c_from[i]] = 1
      role_seen[c_to[i]] = 1
    }
    # Stable participant order: first appearance.
    pn = 0
    for (i = 1; i <= m; i++) {
      if (!(c_from[i] in printed)) { printed[c_from[i]] = 1; pn++; order[pn] = c_from[i] }
      if (!(c_to[i] in printed)) { printed[c_to[i]] = 1; pn++; order[pn] = c_to[i] }
    }
    for (i = 1; i <= pn; i++)
      emit("  participant " order[i] " as " order[i])
    for (i = 1; i <= m; i++) {
      arrow = (c_sync[i] == "asynchronous" ? "-->>" : "->>")
      label = c_call[i] " " c_file[i] ":" c_line[i] " " c_res[i]
      if (c_mech[i] != "") label = label " " c_mech[i]
      if (c_hand[i] == "yes") label = label " handoff /architecture:map-events"
      if (c_count[i] > 1) label = label " (" c_count[i] " hops collapsed)"
      emit("  " c_from[i] arrow c_to[i] ": " q(label))
    }
    emit("```")
    emit("")
    emit("## Hops")
    emit("")
    emit("| from | to | call | cite | sync | resolution | mechanism | handoff |")
    emit("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for (i = 1; i <= n; i++)
      emit("| " from[i] " | " to[i] " | " call[i] " | " file[i] ":" line[i] " | " sync[i] " | " res[i] " | " mech[i] " | " hand[i] " |")
    emit("")
    collapsed = 0
    for (i = 1; i <= m; i++) if (c_count[i] > 1) collapsed += c_count[i]
    if (collapsed > 0)
      emit("Collapsed " collapsed " hops that shared a role pair, sync, resolution, and handoff. The table above keeps every cited call.")
    else
      emit("No consecutive hops were collapsed.")
  } else {
    emit("workspace {")
    emit("  model {")
    emit("    sys = softwareSystem \"" q(entry) "\" {")
    for (i = 1; i <= m; i++) {
      role_seen[c_from[i]] = 1
      role_seen[c_to[i]] = 1
    }
    for (r in role_seen)
      emit("      " r " = container \"" r "\" \"architectural role\" \"\"")
    for (i = 1; i <= m; i++) {
      label = c_call[i]
      if (c_hand[i] == "yes") label = label " handoff map-events"
      if (c_sync[i] == "asynchronous") label = label " async"
      else label = label " sync"
      if (c_count[i] > 1) label = label " collapsed " c_count[i]
      emit("      " c_from[i] " -> " c_to[i] " \"" q(label) "\" \"" c_res[i] "\"")
    }
    emit("    }")
    emit("  }")
    emit("  views {")
    emit("    dynamic sys \"flow\" {")
    emit("      include *")
    emit("      autoLayout")
    emit("    }")
    emit("  }")
    emit("}")
  }
  printf "flow: entry=%s hops=%d truncated=%s unresolved=%d handoffs=%d\n", entry, n + 0, (truncated == "" ? "no" : truncated), unresolved + 0, handoffs + 0
}
AWK
