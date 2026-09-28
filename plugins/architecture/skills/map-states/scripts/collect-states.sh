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
# confidence is high only when every transition in a shipped library was read.
# A refusal still writes the record and draws no transitions.
#
# Exit: 0 = a record was written, including a refusal; 1 = bad path; 2 = usage.
set -uo pipefail

usage() { sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'collect-states.sh: %s\n' "$1" >&2; exit "$2"; }
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"; s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}
github_repo_name() {
  local url="$1" scheme=0 host rest host_l repo
  [[ -n "$url" && "$url" != "unknown" ]] || return 1
  url="${url%/}"; url="${url%.git}"
  [[ "$url" == *://* ]] && scheme=1 && url="${url#*://}"
  [[ "${url%%/*}" == *@* ]] && url="${url#*@}"
  host="${url%%[:/]*}"
  rest="${url#"$host"}"
  if [[ $scheme -eq 1 ]]; then
    [[ "$rest" =~ ^:[0-9]*/ ]] && rest="${rest#:*/}"
    [[ "$rest" == :* ]] && return 1
    rest="${rest#/}"
  else
    [[ "$rest" == :* ]] || return 1
    rest="${rest#:}"; rest="${rest#/}"
  fi
  [[ -n "$rest" ]] || return 1
  host_l="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  [[ "$host_l" == "github.com" || "$host_l" == "www.github.com" ]] || return 1
  repo="${rest#*/}"; repo="${repo%%/*}"
  [[ -n "$repo" && "$repo" != "$rest" ]] || return 1
  printf '%s' "$repo"
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
  [[ -n "$rel" && -f "$repo/$rel" ]] || continue
  case "$rel" in
  states.json|states.md|*/states.json|*/states.md) continue ;;
  *.js|*.mjs|*.cjs|*.ts|*.tsx|*.cs) printf '%s\n' "$rel" ;;
  *) ;;
  esac
done < <(git -C "$repo" ls-files) >"$TMP/list"

[[ -s "$TMP/list" ]] || refuse "no-state-machine"

awk -v root="$repo" -v list="$TMP/list" -v ents="$ENTS" -v states="$STATES" -v trans="$TRANS" -v finds="$FINDS" -v flag="$TMP/flag" '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
function unquote(s) { gsub(/^[\047"]|[\047"]$/, "", s); return s }
function fail(msg) { printf "%s\n", msg > flag; failed = 1 }
function add_state(ent, name) { if (ent != "" && name != "") declared[ent SUBSEP name] = 1 }
function add_trans(ent, from, to, trigger, guard) {
  ntr++; tr_e[ntr]=ent; tr_f[ntr]=from; tr_t[ntr]=to; tr_g[ntr]=trigger; tr_u[ntr]=guard
}
function finish_entity(ent, initial, library, evidence,    i, k, q, qh, qt, cur, outn) {
  if (failed) return
  if (ent == "" || initial == "") { fail("unsupported-syntax"); return }
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
  for (i = 1; i <= ntr; i++) if (tr_e[i] == ent) {
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
      state = t; sub(/:.*/, "", state); add_state(ent, state); mode = "state"; continue
    }
    if (mode == "state" && t ~ /^on:/) { mode = "on"; continue }
    if (mode == "state" && t ~ /^type:/ && index(t, "final") > 0) { final[ent SUBSEP state] = 1; continue }
    if (mode == "on" && t ~ /^[A-Za-z_][A-Za-z0-9_]*:/ && index(t, "target") == 0) {
      trig = t; sub(/:.*/, "", trig)
      target = trim(substr(t, index(t, ":") + 1)); sub(/,.*/, "", target); target = unquote(trim(target))
      add_state(ent, target); add_trans(ent, state, target, trig, ""); continue
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
      add_state(ent, target); add_trans(ent, state, target, trig, guard); continue
    }
    if (t ~ /^}/) {
      if (mode == "on") mode = "state"
      else if (mode == "state") mode = "states"
      else if (mode == "states") mode = "root"
      else if (mode == "root") { finish_entity(ent, initial, "xstate", evidence); mode = "out"; ent = ""; initial = "" }
      continue
    }
    if (t ~ /^\)/ ) { if (mode == "root") finish_entity(ent, initial, "xstate", evidence); mode = "out"; continue }
    if (mode != "out") { fail("unsupported-syntax"); return }
  }
  if (mode != "out") fail("unsupported-syntax")
}
function parse_stateless(path, evidence,    raw, buf, n, i, stmt, ent, initial, cur, rest, trig, dest, guard) {
  buf = ""
  while ((getline raw < path) > 0) { sub(/\r$/, "", raw); sub(/\/\/.*/, "", raw); buf = buf " " raw }
  close(path)
  n = split(buf, parts, ";")
  for (i = 1; i <= n; i++) {
    stmt = parts[i]
    if (index(stmt, "new StateMachine<") > 0 || stmt ~ /new[[:space:]]+StateMachine</) {
      ent = stmt; sub(/.*StateMachine</, "", ent); sub(/,.*/, "", ent)
      initial = stmt; sub(/.*\(/, "", initial); sub(/\).*/, "", initial); sub(/.*\./, "", initial)
      if (ent == "" || initial == "") { fail("unsupported-syntax"); return }
      add_state(ent, initial)
      continue
    }
    if (index(stmt, ".Configure(") == 0) continue
    cur = stmt; sub(/.*Configure\(/, "", cur); sub(/\).*/, "", cur); sub(/.*\./, "", cur)
    add_state(ent, cur)
    rest = stmt
    while (match(rest, /\.Permit(If|Reentry)?\(/)) {
      kind = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      if (index(kind, "Reentry") > 0) {
        trig = rest; sub(/^[A-Za-z0-9_]*\./, "", trig); sub(/[^A-Za-z0-9_].*/, "", trig)
        add_trans(ent, cur, cur, trig, "")
      } else {
        trig = rest; sub(/^[A-Za-z0-9_]*\./, "", trig); sub(/[^A-Za-z0-9_].*/, "", trig)
        dest = rest; sub(/^[^,]*,[[:space:]]*/, "", dest); sub(/^[A-Za-z0-9_]*\./, "", dest); sub(/[^A-Za-z0-9_].*/, "", dest)
        guard = ""
        if (index(kind, "If") > 0) guard = (index(rest, "=> true") > 0 || index(rest, "=>true") > 0) ? "true" : "declared"
        add_state(ent, dest)
        add_trans(ent, cur, dest, trig, guard)
      }
      if (match(rest, /\)/)) rest = substr(rest, RSTART + 1)
      else break
    }
  }
  if (ent != "") finish_entity(ent, initial, "stateless", evidence)
}
BEGIN {
  while ((getline rel < list) > 0) {
    path = root "/" rel
    seen = 0; ad = 0
    while ((getline raw < path) > 0) {
      if (raw ~ /createMachine[[:space:]]*\(/) seen = 1
      if (index(raw, "StateMachine<") > 0) seen = 2
      if (raw ~ /\.status[[:space:]]*=/ || raw ~ /\.Status[[:space:]]*=/ || raw ~ /[Ss]tatus[[:space:]]*=[[:space:]]*[\047"]/) adhoc = 1
    }
    close(path)
    if (seen == 1) { parse_xstate(path, rel); if (failed) exit }
    else if (seen == 2) { parse_stateless(path, rel); if (failed) exit }
  }
  if (!wrote && adhoc) printf "ad-hoc\n" > flag
  else if (!wrote) printf "no-state-machine\n" > flag
}
'
if [[ -s "$TMP/flag" ]]; then refuse "$(head -n 1 "$TMP/flag")"; fi
[[ -s "$ENTS" ]] || refuse "no-state-machine"
sort -u -o "$ENTS" "$ENTS"; sort -u -o "$STATES" "$STATES"; sort -u -o "$TRANS" "$TRANS"; sort -u -o "$FINDS" "$FINDS"
write_record drawn "" high
exit 0
