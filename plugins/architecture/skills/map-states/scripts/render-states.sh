#!/usr/bin/env bash
# Render states.json as one mermaid stateDiagram-v2.
#
# status other than drawn exits 3, writes nothing, and prints the reason.
# Two entities without --entity exit 3 and name the ids. A compacted record
# exits 1. The picture is a state diagram. C4 has no state-diagram type, so
# this script does not take --dialect and does not read landscape_dialect.
#
# Summary: states: entity=<id> states=<n> transitions=<n> findings=<n> confidence=<c>
# Exit: 0 written; 1 bad record; 2 usage; 3 refused or needs --entity.
set -uo pipefail

usage() { sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'render-states.sh: %s\n' "$1" >&2; exit "$2"; }

record=""
outdir=""
entity=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h) usage; exit 0 ;;
  --record) [[ $# -ge 2 ]] || die "--record needs a path" 2; record="$2"; shift 2 ;;
  --record=*) record="${1#--record=}"; shift ;;
  --out) [[ $# -ge 2 ]] || die "--out needs a directory" 2; outdir="$2"; shift 2 ;;
  --out=*) outdir="${1#--out=}"; shift ;;
  --entity) [[ $# -ge 2 ]] || die "--entity needs a name" 2; entity="$2"; shift 2 ;;
  --entity=*) entity="${1#--entity=}"; shift ;;
  *) die "unknown argument: $1" 2 ;;
  esac
done
[[ -n "$record" && -n "$outdir" ]] || { usage >&2; exit 2; }
[[ -r "$record" ]] || die "cannot read record: $record" 1
[[ -d "$outdir" ]] || die "not a directory: $outdir" 1
grep -q '"schema_version"[[:space:]]*:[[:space:]]*1' "$record" || die "not a schema_version 1 record: $record" 1

layout="$(awk '
function open_array(key, shape,    rest) {
  if (!match($0, "\"" key "\"[[:space:]]*:[[:space:]]*\\[")) return
  rest = substr($0, RSTART + RLENGTH)
  if (rest ~ /^[[:space:]]*\]/) { seen[key] = 1; return }
  if (substr($0, 1, RSTART - 1) ~ /^[[:space:]]*$/ && rest ~ /^[[:space:]]*$/) { open = key; want = shape; return }
  problem = "the " key " array does not start on a line of its own"
}
open != "" {
  if ($0 ~ /^[[:space:]]*\][[:space:]]*,?[[:space:]]*$/) { seen[open] = 1; open = ""; next }
  if ($0 !~ want) { problem = "line " NR " is not one " open " object"; exit }
  next
}
{
  open_array("entities", "^[[:space:]]*[{]\"id\":")
  if (open == "" && problem == "") open_array("states", "^[[:space:]]*[{]\"state\":")
  if (open == "" && problem == "") open_array("transitions", "^[[:space:]]*[{]\"from\":")
  if (open == "" && problem == "") open_array("findings", "^[[:space:]]*[{]\"kind\":")
  if (problem != "") exit
}
END {
  if (problem == "" && open != "") problem = "an array never closes"
  if (problem == "" && !("entities" in seen)) problem = "no entities array"
  if (problem == "" && !("states" in seen)) problem = "no states array"
  if (problem == "" && !("transitions" in seen)) problem = "no transitions array"
  if (problem == "" && !("findings" in seen)) problem = "no findings array"
  print problem
}
' "$record")"
[[ -z "$layout" ]] || die "record is not in the one-object-per-line layout collect-states.sh writes ($layout); regenerate it: $record" 1

status="$(awk -F'"' '/"status"[[:space:]]*:/ { print $4; exit }' "$record")"
reason="$(awk -F'"' '/"reason"[[:space:]]*:/ { print $4; exit }' "$record")"
if [[ "$status" != "drawn" ]]; then
  die "refused: ${reason:-no explicit transition table}. Nothing was drawn." 3
fi

ids="$(awk -F'"' '/^[[:space:]]*\{"id":/ { print $4 }' "$record")"
count="$(printf '%s\n' "$ids" | awk 'NF{n++} END{print n+0}')"
if [[ -z "$entity" && "$count" -gt 1 ]]; then
  die "refused: ${count} state machines; pass --entity. $(printf '%s' "$ids" | tr '\n' ' ')" 3
fi
if [[ -z "$entity" ]]; then
  entity="$(printf '%s\n' "$ids" | awk 'NF{print; exit}')"
fi
printf '%s\n' "$ids" | grep -F -x -q -- "$entity" || die "refused: entity not in the record: $entity" 3

OUT="$outdir/states.md" ENTITY="$entity" awk -f - "$record" <<'AWK'
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
    if (c == "\\") { c = substr(rest, i + 1, 1); if (c == "") break; out = out c; i += 2; continue }
    if (c == "\"") break
    out = out c
    i++
  }
  return out
}
function emit(s) { print s > out }
BEGIN { out = ENVIRON["OUT"]; entity = ENVIRON["ENTITY"] }
/"confidence"[[:space:]]*:/ { conf = jstr($0, "confidence") }
/^[[:space:]]*\{"id":/ { if (jstr($0, "id") == entity) { initial = jstr($0, "initial"); library = jstr($0, "library"); evidence = jstr($0, "evidence") } }
/^[[:space:]]*\{"state":/ { if (jstr($0, "entity") == entity) { ns++; sname[ns] = jstr($0, "name"); sfinal[ns] = jstr($0, "final") } }
/^[[:space:]]*\{"from":/ { if (jstr($0, "entity") == entity) { nt++; tfrom[nt] = jstr($0, "from"); tto[nt] = jstr($0, "to"); ttrig[nt] = jstr($0, "trigger"); tguard[nt] = jstr($0, "guard") } }
/^[[:space:]]*\{"kind":/ { if (jstr($0, "entity") == entity) { nf++; fkind[nf] = jstr($0, "kind"); fstate[nf] = jstr($0, "state"); fdet[nf] = jstr($0, "detail") } }
END {
  emit("# States")
  emit("")
  emit("Entity: " entity ". Library: " library ". Confidence: " conf ".")
  emit("Evidence: " evidence ".")
  emit("Picture: mermaid stateDiagram-v2. A state diagram is not a C4 diagram type (system context, container, component, code, system landscape, dynamic, deployment), so landscape_dialect is not read and no dialect key is added.")
  emit("")
  emit("```mermaid")
  emit("stateDiagram-v2")
  if (initial != "") emit("  [*] --> " initial)
  for (i = 1; i <= nt; i++) {
    label = ttrig[i]
    if (tguard[i] != "") label = label " [" tguard[i] "]"
    emit("  " tfrom[i] " --> " tto[i] ": " label)
  }
  for (i = 1; i <= ns; i++) if (sfinal[i] == "yes") emit("  " sname[i] " --> [*]")
  emit("```")
  emit("")
  emit("## Findings")
  emit("")
  if (nf == 0) emit("No findings.")
  for (i = 1; i <= nf; i++) emit("- " fkind[i] ": " fstate[i] " (" fdet[i] ")")
  unr = 0
  dead = 0
  for (i = 1; i <= nf; i++) {
    if (fkind[i] == "unreachable") unr++
    if (fkind[i] == "dead_end") dead++
  }
  printf "states: status=drawn reason=none confidence=%s entity=%s states=%d transitions=%d unreachable=%d dead_ends=%d\n", conf, entity, ns + 0, nt + 0, unr, dead
}
AWK
