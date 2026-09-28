#!/usr/bin/env bash
# Chart async message topology from committed C# call sites and registrations.
#
# WHY. A publisher and its consumer share no build reference. The edge exists
# only when both cite a resolved contract type. A publish that cannot be
# resolved is listed, never dropped, or an orphan-consumer finding would be wrong.
#
# Usage:
#   collect-events.sh --repo <path> --out <file> [--generated-on <date>]
#   collect-events.sh --help
#
# The shipped adapter is C# in the MassTransit shape: Publish<T> or
# Publish(new T(..)) (broadcast), Send<T> or Send(new T(..)) (point-to-point),
# IConsumer<T> (consumer of T). AddConsumer<C> and ConfigureConsumer<C> register
# consumer class C; inside ReceiveEndpoint("q", ..) they give C's edges queue q.
# A message is a type some publish, send, or consume names. Other types are not.
# A publish or send whose type does not resolve is an unresolved edge and finding.
# Identity is the namespace-qualified type. A short name resolves through the
# file's namespace and using directives, then through a unique repo match.
# fanout_threshold is 3, a limit of this plugin, not of the broker.
#
# schema_version 1. Message lines start with {"id":. Edge lines start with
# {"from":. Finding lines start with {"kind":.
#
# Portability: bash plus POSIX awk. No jq, no python.
# Exit: 0 written; 1 no commit or unreadable path; 2 usage.
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'collect-events.sh: %s\n' "$1" >&2
  exit "$2"
}

JSON_ESC=""
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  JSON_ESC="$s"
}

github_repo_name() {
  local url="$1" scheme=0 host rest host_l repo
  [[ -n "$url" && "$url" != "unknown" ]] || return 1
  url="${url%/}"
  url="${url%.git}"
  [[ "$url" == *://* ]] && scheme=1 && url="${url#*://}"
  [[ "${url%%/*}" == *@* ]] && url="${url#*@}"
  host="${url%%[:/]*}"
  rest="${url#"$host"}"
  if [[ $scheme -eq 1 ]]; then
    [[ "$rest" =~ ^:[0-9]*/ ]] && rest="${rest#:*/}"
    if [[ "$rest" == :* ]]; then
      return 1
    fi
    rest="${rest#/}"
  else
    [[ "$rest" == :* ]] || return 1
    rest="${rest#:}"
    rest="${rest#/}"
  fi
  [[ -n "$rest" ]] || return 1
  host_l="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  [[ "$host_l" == "github.com" || "$host_l" == "www.github.com" ]] || return 1
  repo="${rest#*/}"
  repo="${repo%%/*}"
  [[ -n "$repo" && "$repo" != "$rest" ]] || return 1
  printf '%s' "$repo"
}

repo=""
out_file=""
generated_on=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h) usage; exit 0 ;;
  --repo) [[ $# -ge 2 ]] || die "--repo needs a path" 2; repo="$2"; shift 2 ;;
  --repo=*) repo="${1#--repo=}"; shift ;;
  --out) [[ $# -ge 2 ]] || die "--out needs a path" 2; out_file="$2"; shift 2 ;;
  --out=*) out_file="${1#--out=}"; shift ;;
  --generated-on) [[ $# -ge 2 ]] || die "--generated-on needs a date" 2; generated_on="$2"; shift 2 ;;
  --generated-on=*) generated_on="${1#--generated-on=}"; shift ;;
  *) die "unknown argument: $1" 2 ;;
  esac
done

[[ -n "$repo" && -n "$out_file" ]] || die "--repo and --out are required" 2
[[ -d "$repo" ]] || die "not a directory: $repo" 1
root="$(cd -P "$repo" 2>/dev/null && pwd)" || die "unreadable: $repo" 1
git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1 || die "no commit to read: $root" 1
[[ -n "$generated_on" ]] || generated_on="$(git -C "$root" log -1 --format=%cs 2>/dev/null || true)"
[[ -n "$generated_on" ]] || generated_on="unknown"

subject="$(basename "$root")"
origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
if [[ -n "$origin" ]]; then
  if resolved="$(github_repo_name "$origin")"; then
    subject="$resolved"
  fi
fi

raw="$(mktemp)"
types="$(mktemp)"
edges_tsv="$(mktemp)"
msg_body="$(mktemp)"
edge_body="$(mktemp)"
find_body="$(mktemp)"
trap 'rm -f "$raw" "$types" "$edges_tsv" "$msg_body" "$edge_body" "$find_body"' EXIT

while IFS= read -r rel || [[ -n "$rel" ]]; do
  case "$rel" in
  *$'\t'*) continue ;;
  *.cs) ;;
  *) continue ;;
  esac
  [[ -f "$root/$rel" ]] || continue
  awk -v rel="$rel" '
    function strip(s) { if (match(s, /\/\//)) s = substr(s, 1, RSTART - 1); return s }
    function typearg(s, keyword,    i, rest, depth, out, c) {
      i = index(s, keyword "<")
      if (i == 0) return ""
      rest = substr(s, i + length(keyword) + 1)
      depth = 1
      out = ""
      for (i = 1; i <= length(rest); i++) {
        c = substr(rest, i, 1)
        if (c == "<") depth++
        else if (c == ">") {
          depth--
          if (depth == 0) return out
        }
        out = out c
      }
      return ""
    }
    # Names a short type name can bind to here: the namespace, its parents, and usings.
    function scope(    s, n) {
      s = ","
      for (n = ns; n != ""; ) { s = s n ","; if (!sub(/\.[^.]*$/, "", n)) n = "" }
      return s usings
    }
    BEGIN { ns = ""; queue = "-"; cls = "-"; usings = "" }
    {
      line = strip($0)
      sub(/\r$/, "", line)
      gsub(/\t/, " ", line)
      if (line ~ /^[[:space:]]*(global[[:space:]]+)?using[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*;/) {
        u = line
        sub(/^[[:space:]]*(global[[:space:]]+)?using[[:space:]]+/, "", u)
        sub(/[[:space:]]*;.*$/, "", u)
        usings = usings u ","
      }
      if (line ~ /^[[:space:]]*namespace[[:space:]]+/) {
        ns = line
        sub(/^[[:space:]]*namespace[[:space:]]+/, "", ns)
        sub(/[[:space:]]*[;{].*$/, "", ns)
        gsub(/[[:space:]]/, "", ns)
      }
      if (line ~ /(class|record|interface|struct)[[:space:]]+[A-Za-z_]/) {
        name = line
        sub(/^.*(class|record|struct|interface)[[:space:]]+/, "", name)
        sub(/[^A-Za-z0-9_].*$/, "", name)
        if (name != "") {
          cls = (ns == "" ? name : ns "." name)
          printf "T\t%s\t%s\t%s\t%s\t%d\n", cls, name, ns, rel, FNR
        }
      }
      if (match(line, /ReceiveEndpoint[[:space:]]*\([[:space:]]*"/)) {
        rest = substr(line, RSTART + RLENGTH)
        if (match(rest, /[^"]*/)) queue = substr(rest, RSTART, RLENGTH)
      }
      n = split("IConsumer,Publish,Send,AddConsumer,ConfigureConsumer", keys, ",")
      for (k = 1; k <= n; k++) {
        s = line
        while ((i = index(s, keys[k] "<")) > 0) {
          arg = typearg(substr(s, i), keys[k])
          s = substr(s, i + length(keys[k]) + 1)
          if (arg == "") break
          if (k > 3) {
            printf "R\t%s\t%s\t%s\t%d\t%s\n", arg, scope(), rel, FNR, queue
            continue
          }
          kind = (k == 1 ? "consume" : tolower(keys[k]))
          printf "E\t%s\t%s\t%s\t%s\t%d\t%s\tstatic\t%s\n", kind, arg, scope(), rel, FNR, queue, cls
        }
      }
      s = line
      while (match(s, /\.(Publish|Send)[[:space:]]*\(/)) {
        kind = (substr(s, RSTART + 1, 4) == "Send" ? "send" : "publish")
        s = substr(s, RSTART + RLENGTH)
        arg = "-"
        if (match(s, /^[[:space:]]*new[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*/)) {
          arg = substr(s, RSTART, RLENGTH)
          sub(/^[[:space:]]*new[[:space:]]+/, "", arg)
        }
        printf "E\t%s\t%s\t%s\t%s\t%d\t%s\t%s\t%s\n", kind, arg, scope(), rel, FNR, queue, (arg == "-" ? "unresolved" : "static"), cls
      }
    }
  ' "$root/$rel"
done < <(git -C "$root" ls-tree -r --name-only -z HEAD | tr '\0' '\n') >"$raw"

awk -F'\t' '$1 == "T" { print }' "$raw" >"$types"

# Resolve short type names. A qualified name is itself. A short name binds to the
# one match in scope (namespace, parents, usings; the global namespace always),
# else to the one match in the repo. Anything else stays unresolved.
# Pass 1 reads types, pass 2 registrations, pass 3 edges.
awk -F'\t' '
  function qualify(arg, sc,    n, i, c, pick, inscope) {
    if (arg == "" || arg == "-") return "-"
    if (index(arg, ".") > 0) return arg
    n = split(byname[arg], c, SUBSEP)
    inscope = 0
    for (i = 2; i <= n; i++) if (nsof[c[i]] == "" || index(sc, "," nsof[c[i]] ",")) { inscope++; pick = c[i] }
    if (inscope == 1) return pick
    if (inscope == 0 && n == 2) return c[2]
    return "-"
  }
  pass == 1 { if (!($2 in nsof)) byname[$3] = byname[$3] SUBSEP $2; nsof[$2] = $4; next }
  pass == 2 && $1 == "R" { cid = qualify($2, $3); if (cid != "-" && $6 != "-") regq[cid] = $6; next }
  pass == 3 && $1 == "E" {
    resolved = qualify($3, $4)
    res = (resolved == "-" ? "unresolved" : $8)
    q = $7
    if ($2 == "consume" && q == "-" && ($9 in regq)) q = regq[$9]
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $2, resolved, $5, $6, q, res, $3
  }
' pass=1 "$types" pass=2 "$raw" pass=3 "$raw" >"$edges_tsv"

# A message is a declared type some edge names, cited at its first declaration.
awk -F'\t' '
  FILENAME == ARGV[1] { if ($2 != "-") used[$2] = 1; next }
  ($2 in used) && !($2 in seen) { seen[$2] = 1; printf "%s\t%s\t%s\t%s\n", $2, $3, $5, $6 }
' "$edges_tsv" "$types" | LC_ALL=C sort | while IFS=$'\t' read -r id name file line; do
  json_escape "$id"
  obj="{\"id\":\"$JSON_ESC\""
  json_escape "$name"
  obj="$obj,\"name\":\"$JSON_ESC\""
  json_escape "$file"
  obj="$obj,\"file\":\"$JSON_ESC\",\"line\":$line}"
  printf '%s\n' "$obj"
done >"$msg_body"

while IFS=$'\t' read -r kind contract file line queue resolution rawarg; do
  json_escape "$file"
  obj="{\"from\":\"$JSON_ESC\""
  json_escape "$contract"
  obj="$obj,\"to\":\"$JSON_ESC\""
  json_escape "$kind"
  obj="$obj,\"kind\":\"$JSON_ESC\""
  json_escape "$resolution"
  obj="$obj,\"resolution\":\"$JSON_ESC\""
  json_escape "$file"
  obj="$obj,\"file\":\"$JSON_ESC\",\"line\":$line"
  json_escape "$queue"
  obj="$obj,\"queue\":\"$JSON_ESC\""
  json_escape "$rawarg"
  obj="$obj,\"raw\":\"$JSON_ESC\"}"
  printf '%s\n' "$obj"
done <"$edges_tsv" >"$edge_body"

# Findings. Orphans compare resolved contracts only. An unresolved edge is its
# own finding and satisfies nothing.
awk -F'\t' '
  $6 == "unresolved" { print "unresolved\t-\tunresolved " $1 " " $7 " " $3 ":" $4; next }
  $1 == "publish" || $1 == "send" { pub[$2] = 1 }
  $1 == "consume" { con[$2]++; if ($5 != "-" && $5 != "") q[$2 SUBSEP $5]++ }
  END {
    for (c in pub) if (!(c in con)) print "orphan-publisher\t" c "\tno registered consumer"
    for (c in con) if (!(c in pub)) print "orphan-consumer\t" c "\tno publisher"
    for (c in con) if (con[c] > 3) print "fanout\t" c "\t" con[c] " consumers"
    for (k in q) if (q[k] > 1) { split(k, p, SUBSEP); print "competing\t" p[1] "\t" q[k] " consumers on queue " p[2] }
  }
' "$edges_tsv" | LC_ALL=C sort | while IFS=$'\t' read -r kind contract detail; do
  json_escape "$kind"
  obj="{\"kind\":\"$JSON_ESC\""
  json_escape "$contract"
  obj="$obj,\"contract\":\"$JSON_ESC\""
  json_escape "$detail"
  obj="$obj,\"detail\":\"$JSON_ESC\"}"
  printf '%s\n' "$obj"
done >"$find_body"

emit_lines() {
  local key="$1" file="$2" comma="$3"
  if [[ ! -s "$file" ]]; then
    printf '  "%s": []%s\n' "$key" "$comma"
    return
  fi
  printf '  "%s": [\n' "$key"
  awk 'NF { lines[++n] = $0 } END { for (i = 1; i <= n; i++) printf "    %s%s\n", lines[i], (i < n ? "," : "") }' "$file"
  printf '  ]%s\n' "$comma"
}

{
  json_escape "$generated_on"
  printf '{\n  "schema_version": 1,\n  "generated_on": "%s",\n' "$JSON_ESC"
  json_escape "$subject"
  printf '  "subject": "%s",\n  "fanout_threshold": 3,\n' "$JSON_ESC"
  emit_lines messages "$msg_body" ","
  emit_lines edges "$edge_body" ","
  emit_lines findings "$find_body" ""
  printf '}\n'
} >"$out_file"
exit 0
