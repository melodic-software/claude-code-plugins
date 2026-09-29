#!/usr/bin/env bash
# Collect a state diagram from an explicit transition table.
#
# WHY. A plausible state diagram that is subtly wrong is worse than none.
# This script reads an XState createMachine block or a Stateless Configure/Permit
# table. Ad hoc status assignments are a refusal. schema_version 1.
#
# Usage:
#   collect-states.sh [--repo <path>] [--out <file>] [--generated-on <date>]
#   collect-states.sh --help
#
# Output: states.json, schema_version 1, one object per line.
# confidence is high when every transition came from a table, medium when a table
# is drawn and ad hoc status assignments elsewhere in the source bypass it, and
# refused when nothing is drawn. A refusal still writes the record and draws no
# transitions.
#
# Exit: 0 = a record was written, including a refusal; 1 = bad path; 2 = usage.
set -uo pipefail

# shellcheck source=../../../lib/github-remote.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/github-remote.sh"

usage() { sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'collect-states.sh: %s\n' "$1" >&2; exit "$2"; }
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"; s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}
repo="."
out_file=""
generated_on=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --help|-h) usage; exit 0 ;;
  --repo) [[ $# -ge 2 ]] || die "--repo needs a path" 2; repo="$2"; shift 2 ;;
  --out) [[ $# -ge 2 ]] || die "--out needs a path" 2; out_file="$2"; shift 2 ;;
  --generated-on) [[ $# -ge 2 ]] || die "--generated-on needs a value" 2; generated_on="$2"; shift 2 ;;
  *) die "unknown argument: $1" 2 ;;
  esac
done
[[ -d "$repo" ]] || die "not a directory: $repo" 1
repo="$(cd "$repo" && pwd)"
if [[ -z "$generated_on" ]]; then
  generated_on="$(git -C "$repo" log -1 --format=%cs 2>/dev/null || true)"
  [[ -n "$generated_on" ]] || generated_on="unknown"
fi
subject="$(basename "$repo")"
remote="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
if name="$(github_repo_name "$remote")"; then subject="$name"; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ENTS="$TMP/e.jsonl"; STATES="$TMP/s.jsonl"; TRANS="$TMP/t.jsonl"; FINDS="$TMP/f.jsonl"
: >"$ENTS"; : >"$STATES"; : >"$TRANS"; : >"$FINDS"

emit_array() {
  local key="$1" file="$2" line first=1
  if [[ ! -s "$file" ]]; then printf '  "%s": []' "$key"; return; fi
  printf '  "%s": [\n' "$key"
  sort "$file" | while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    [[ $first -eq 1 ]] && first=0 || printf ',\n'
    printf '    %s' "$line"
  done
  printf '\n  ]'
}
write_record() {
  local status="$1" reason="$2" confidence="$3"
  local body
  body="$(
    {
      printf '{\n'
      printf '  "schema_version": 1,\n'
      printf '  "generated_on": "%s",\n' "$(json_escape "$generated_on")"
      printf '  "subject": "%s",\n' "$(json_escape "$subject")"
      printf '  "status": "%s",\n' "$(json_escape "$status")"
      printf '  "reason": "%s",\n' "$(json_escape "$reason")"
      printf '  "confidence": "%s",\n' "$(json_escape "$confidence")"
      emit_array entities "$ENTS"; printf ',\n'
      emit_array states "$STATES"; printf ',\n'
      emit_array transitions "$TRANS"; printf ',\n'
      emit_array findings "$FINDS"; printf '\n}\n'
    }
  )"
  if [[ -n "$out_file" ]]; then mkdir -p "$(dirname "$out_file")"; printf '%s' "$body" >"$out_file"; else printf '%s' "$body"; fi
}
refuse() { : >"$ENTS"; : >"$STATES"; : >"$TRANS"; : >"$FINDS"; write_record refused "$1" refused; exit 0; }

if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  refuse "not-a-git-repository"
fi

: >"$TMP/list"
while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -n "$rel" && -f "$repo/$rel" && ! -L "$repo/$rel" ]] || continue
  case "$rel" in
  states.json|states.md|*/states.json|*/states.md) continue ;;
  *.js|*.mjs|*.cjs|*.ts|*.tsx|*.cs) printf '%s\n' "$rel" ;;
  *) ;;
  esac
done < <(git -C "$repo" ls-files) >"$TMP/list"

[[ -s "$TMP/list" ]] || refuse "no-state-machine"

awk -v root="$repo" -v list="$TMP/list" -v ents="$ENTS" -v states="$STATES" -v trans="$TRANS" -v finds="$FINDS" -v flag="$TMP/flag" -v adhocf="$TMP/adhoc" '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
function unquote(s) { gsub(/^[\047"]|[\047"]$/, "", s); return s }
function fail(msg) { printf "%s\n", msg > flag; failed = 1 }
function add_state(ent, name) { if (ent != "" && name != "") declared[ent SUBSEP name] = 1 }
function add_trans(ent, from, to, trigger, guard) {
  ntr++; tr_e[ntr]=ent; tr_f[ntr]=from; tr_t[ntr]=to; tr_g[ntr]=trigger; tr_u[ntr]=guard
}
function finish_entity(ent, initial, library, evidence,    i, k, q, qh, qt, cur, outn, tgt) {
  if (failed) return
  if (ent == "" || initial == "") { fail("unsupported-syntax"); return }
  if (ent in done) { fail("duplicate-entity"); return }
  done[ent] = 1
  if (!((ent SUBSEP initial) in declared)) { fail("undeclared-target"); return }
  for (i = 1; i <= ntr; i++) if (tr_e[i] == ent) {
    if (!((ent SUBSEP tr_f[i]) in declared) || !((ent SUBSEP tr_t[i]) in declared)) { fail("undeclared-target"); return }
  }
  wrote = 1
  printf "{\"id\":\"%s\",\"initial\":\"%s\",\"library\":\"%s\",\"evidence\":\"%s\"}\n", jesc(ent), jesc(initial), library, jesc(evidence) >> ents
  for (k in declared) {
    split(k, p, SUBSEP)
    if (p[1] != ent) continue
    printf "{\"state\":\"%s\",\"entity\":\"%s\",\"name\":\"%s\",\"final\":\"%s\"}\n", jesc(p[2]), jesc(ent), jesc(p[2]), (final[k] ? "yes" : "no") >> states
  }
  delete outn
  delete tgt
  for (i = 1; i <= ntr; i++) if (tr_e[i] == ent) {
    tgt[tr_t[i]] = 1
    printf "{\"from\":\"%s\",\"entity\":\"%s\",\"to\":\"%s\",\"trigger\":\"%s\",\"guard\":\"%s\"}\n", jesc(tr_f[i]), jesc(ent), jesc(tr_t[i]), jesc(tr_g[i]), jesc(tr_u[i]) >> trans
    outn[tr_f[i]]++
    if (tr_u[i] == "true")
      printf "{\"kind\":\"missing_guard\",\"entity\":\"%s\",\"state\":\"%s\",\"detail\":\"%s\"}\n", jesc(ent), jesc(tr_f[i]), jesc(tr_g[i] " guard is true") >> finds
  }
  qh = 1; qt = 1; q[1] = initial; reach[initial] = 1
  while (qh <= qt) {
    cur = q[qh]; qh++
    for (i = 1; i <= ntr; i++) if (tr_e[i] == ent && tr_f[i] == cur && !(tr_t[i] in reach)) {
      reach[tr_t[i]] = 1; q[++qt] = tr_t[i]
    }
  }
  for (k in declared) {
    split(k, p, SUBSEP)
    if (p[1] != ent) continue
    if (!(p[2] in reach))
      printf "{\"kind\":\"unreachable\",\"entity\":\"%s\",\"state\":\"%s\",\"detail\":\"%s\"}\n", jesc(ent), jesc(p[2]), jesc("not reachable from " initial) >> finds
    else if (!final[k] && (outn[p[2]] + 0) == 0 && library == "stateless" && (p[2] in tgt))
      printf "{\"kind\":\"terminal_inferred\",\"entity\":\"%s\",\"state\":\"%s\",\"detail\":\"%s\"}\n", jesc(ent), jesc(p[2]), jesc("targeted, no outgoing permit; Stateless declares no final state") >> finds
    else if (!final[k] && (outn[p[2]] + 0) == 0)
      printf "{\"kind\":\"dead_end\",\"entity\":\"%s\",\"state\":\"%s\",\"detail\":\"%s\"}\n", jesc(ent), jesc(p[2]), jesc("reachable, not final, no outgoing transition") >> finds
  }
  delete reach
}
function parse_xstate(path, evidence,    raw, t, ent, initial, state, mode, trig, target, guard, n, i) {
  ent = ""; initial = ""; state = ""; mode = "out"; n = 0
  while ((getline raw < path) > 0) { n++; hold[n] = raw }
  close(path)
  for (i = 1; i <= n; i++) {
    raw = hold[i]; sub(/\r$/, "", raw); sub(/\/\/.*/, "", raw); t = trim(raw)
    if (t == "") continue
    if (mode == "out") {
      if (t ~ /createMachine[[:space:]]*\(/) mode = "root"
      continue
    }
    if (t ~ /invoke:|always:|after:|entry:|exit:|context:|meta:|tags:/) { fail("unsupported-syntax"); return }
    if (t ~ /^id:/) { ent = unquote(trim(substr(t, index(t, ":") + 1))); sub(/,.*/, "", ent); ent = unquote(trim(ent)); continue }
    if (t ~ /^initial:/) { initial = unquote(trim(substr(t, index(t, ":") + 1))); sub(/,.*/, "", initial); initial = unquote(trim(initial)); continue }
    if (t ~ /^states:/) { mode = "states"; continue }
    if (mode == "states" && t ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
      state = t; sub(/:.*/, "", state); add_state(ent, state); mode = "state"
      sub(/^[^:]+:/, "", t); t = trim(t)
      if (t ~ /^\{[[:space:]]*type:[[:space:]]*[\047"]final[\047"][[:space:]]*\},?$/) {
        final[ent SUBSEP state] = 1
        mode = "states"
        continue
      }
      if (t == "" || t == "{" || t ~ /^\{\},?$/) {
        if (t ~ /^\{\}/) mode = "states"
        continue
      }
    }
    if (mode == "state" && t ~ /^on:/) { mode = "on"; sub(/^on:[[:space:]]*/, "", t); t = trim(t); if (t == "" || t == "{") continue }
    if (mode == "state" && t ~ /^type:/ && index(t, "final") > 0) { final[ent SUBSEP state] = 1; continue }
    if (mode == "on" && t ~ /^[A-Za-z_][A-Za-z0-9_]*:/ && index(t, "target") == 0) {
      trig = t; sub(/:.*/, "", trig)
      target = trim(substr(t, index(t, ":") + 1)); sub(/,.*/, "", target); target = unquote(trim(target))
      add_trans(ent, state, target, trig, ""); continue
    }
    if (mode == "on" && t ~ /^[A-Za-z_][A-Za-z0-9_]*:/ && index(t, "target") > 0) {
      trig = t; sub(/:.*/, "", trig)
      target = substr(t, index(t, "target"))
      sub(/^target:[[:space:]]*/, "", target); sub(/[,}].*/, "", target); target = unquote(trim(target))
      guard = ""
      if (index(t, "guard") > 0) {
        guard = substr(t, index(t, "guard"))
        sub(/^guard:[[:space:]]*/, "", guard); sub(/[,}].*/, "", guard); guard = unquote(trim(guard))
      }
      add_trans(ent, state, target, trig, guard); continue
    }
    if (t ~ /^[{}),; \t]+$/) {
      closes = gsub(/}/, "", t)
      while (closes > 0) {
        if (mode == "on") mode = "state"
        else if (mode == "state") mode = "states"
        else if (mode == "states") mode = "root"
        else if (mode == "root") { finish_entity(ent, initial, "xstate", evidence); mode = "out"; ent = ""; initial = "" }
        closes--
      }
      if (index(t, ")") > 0 && mode == "root") { finish_entity(ent, initial, "xstate", evidence); mode = "out" }
      continue
    }
    if (mode != "out") { fail("unsupported-syntax"); return }
  }
  if (mode != "out") fail("unsupported-syntax")
}
function last_ident(s) { return match(s, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/) ? trim(substr(s, RSTART)) : "" }
function parse_stateless(path, evidence,    raw, buf, n, i, stmt, v, e, initial, cur, rest, seg, trig, dest, guard, nm, k, ment, minit, kind) {
  buf = ""
  while ((getline raw < path) > 0) { sub(/\r$/, "", raw); sub(/\/\/.*/, "", raw); buf = buf " " raw }
  close(path)
  if (match(buf, /\.(PermitDynamic[A-Za-z]*|PermitReentryIf|SubstateOf|InternalTransition[A-Za-z]*|Ignore(If)?|OnEntry[A-Za-z]*|OnExit[A-Za-z]*|OnActivate|OnDeactivate|InitialTransition)[[:space:]]*[(<]/)) {
    v = substr(buf, RSTART, RLENGTH); gsub(/[^A-Za-z.]/, "", v)
    fail("unsupported-syntax: " v); return
  }
  delete vent
  nm = 0
  n = split(buf, parts, ";")
  for (i = 1; i <= n; i++) {
    stmt = parts[i]
    if (stmt ~ /new[[:space:]]+StateMachine</) {
      e = stmt; sub(/.*StateMachine</, "", e); sub(/,.*/, "", e); e = trim(e)
      initial = stmt; sub(/.*\(/, "", initial); sub(/\).*/, "", initial); sub(/.*\./, "", initial); initial = trim(initial)
      if (e !~ /^[A-Za-z0-9_.]+$/ || initial !~ /^[A-Za-z0-9_]+$/) { fail("unsupported-syntax"); return }
      v = stmt; sub(/=[[:space:]]*new[[:space:]]+StateMachine<.*/, "", v)
      nm++; ment[nm] = e; minit[nm] = initial; vent[last_ident(v)] = e
      add_state(e, initial)
      continue
    }
    if (index(stmt, ".Configure(") == 0) continue
    v = stmt; sub(/\.Configure\(.*/, "", v); v = last_ident(v)
    if (v in vent) e = vent[v]
    else if (nm == 1) e = ment[1]
    else { fail("unsupported-syntax"); return }
    cur = stmt; sub(/.*Configure\(/, "", cur); sub(/\).*/, "", cur); sub(/.*\./, "", cur)
    add_state(e, cur)
    rest = stmt
    while (match(rest, /\.Permit(If|Reentry)?\(/)) {
      kind = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      seg = rest
      if (match(seg, /\)\.[A-Za-z]/)) seg = substr(seg, 1, RSTART)
      trig = rest; sub(/^[A-Za-z0-9_]*\./, "", trig); sub(/[^A-Za-z0-9_].*/, "", trig)
      if (index(kind, "Reentry") > 0) {
        add_trans(e, cur, cur, trig, "")
      } else {
        dest = rest; sub(/^[^,]*,[[:space:]]*/, "", dest); sub(/^[A-Za-z0-9_]*\./, "", dest); sub(/[^A-Za-z0-9_].*/, "", dest)
        guard = ""
        if (index(kind, "If") > 0) guard = (index(seg, "=> true") > 0 || index(seg, "=>true") > 0) ? "true" : "declared"
        add_state(e, dest)
        add_trans(e, cur, dest, trig, guard)
      }
      if (match(rest, /\)/)) rest = substr(rest, RSTART + 1)
      else break
    }
  }
  for (k = 1; k <= nm; k++) finish_entity(ment[k], minit[k], "stateless", evidence)
}
BEGIN {
  while ((getline rel < list) > 0) {
    path = root "/" rel
    seen = 0; ad = 0
    while ((getline raw < path) > 0) {
      if (raw ~ /createMachine[[:space:]]*\(/) seen = 1
      if (index(raw, "StateMachine<") > 0) seen = 2
      if (raw ~ /\.status[[:space:]]*=[^=]/ || raw ~ /\.Status[[:space:]]*=[^=]/ || raw ~ /status[[:space:]]*=[[:space:]]*[\047"]/ || raw ~ /Status[[:space:]]*=[[:space:]]*[\047"]/) adhoc = 1
    }
    close(path)
    if (seen == 1) { parse_xstate(path, rel); if (failed) exit }
    else if (seen == 2) { parse_stateless(path, rel); if (failed) exit }
  }
  if (!wrote && adhoc) printf "ad-hoc\n" > flag
  else if (!wrote) printf "no-state-machine\n" > flag
  else if (adhoc) printf "1\n" > adhocf
}
'
if [[ -s "$TMP/flag" ]]; then refuse "$(head -n 1 "$TMP/flag")"; fi
[[ -s "$ENTS" ]] || refuse "no-state-machine"
sort -u -o "$ENTS" "$ENTS"; sort -u -o "$STATES" "$STATES"; sort -u -o "$TRANS" "$TRANS"; sort -u -o "$FINDS" "$FINDS"
if [[ -s "$TMP/adhoc" ]]; then
  write_record drawn "ad-hoc-status-assignments-beside-table" medium
else
  write_record drawn "" high
fi
exit 0
