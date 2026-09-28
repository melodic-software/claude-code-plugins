#!/usr/bin/env bash
# Collect a per-environment deployment record from committed IaC.
#
# WHY. A deployment diagram is a fact only when every node is a declaration in
# a named file. This script reads Docker Compose and Kubernetes manifests. It
# does not call a cloud API, even when --live is passed.
#
# Usage:
#   collect-deployment.sh [--repo <path>] [--out <file>] [--generated-on <date>]
#       [--live] [--containers <file>]
#   collect-deployment.sh --help
#
# Tracked files only (`git ls-files`). Shipped readers: Compose and Kubernetes
# manifests. Terraform, Pulumi, Bicep, CloudFormation, Helm, and Kustomize are
# recognized and then the record is refused, including when a shipped reader
# also matches, so the diagram is never a partial read.
#
# Output: deployment.json, schema_version 1, one object per line.
#
# Exit: 0 = a record was written (including a refusal); 1 = bad path; 2 = usage.
set -uo pipefail

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'collect-deployment.sh: %s\n' "$1" >&2
  exit "$2"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
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

repo="."
out_file=""
generated_on=""
live=0
containers_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --repo)
    [[ $# -ge 2 ]] || die "--repo needs a path" 2
    repo="$2"
    shift 2
    ;;
  --out)
    [[ $# -ge 2 ]] || die "--out needs a path" 2
    out_file="$2"
    shift 2
    ;;
  --generated-on)
    [[ $# -ge 2 ]] || die "--generated-on needs a value" 2
    generated_on="$2"
    shift 2
    ;;
  --live)
    live=1
    shift
    ;;
  --containers)
    [[ $# -ge 2 ]] || die "--containers needs a path" 2
    containers_file="$2"
    shift 2
    ;;
  *)
    die "unknown argument: $1" 2
    ;;
  esac
done

[[ -d "$repo" ]] || die "not a directory: $repo" 1
repo="$(cd "$repo" && pwd)" || die "unreadable: $repo" 1

if [[ -z "$generated_on" ]]; then
  generated_on="$(git -C "$repo" log -1 --format=%cs 2>/dev/null || true)"
  [[ -n "$generated_on" ]] || generated_on="unknown"
fi

subject="$(basename "$repo")"
remote="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
if name="$(github_repo_name "$remote")"; then
  subject="$name"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TOOLS="$TMP/tools.jsonl"
ENVS="$TMP/envs.jsonl"
NODES="$TMP/nodes.jsonl"
PLACES="$TMP/places.jsonl"
PARAMS="$TMP/params.jsonl"
DIFFS="$TMP/diffs.jsonl"
CATALOG="$TMP/catalog.jsonl"
: >"$TOOLS"
: >"$ENVS"
: >"$NODES"
: >"$PLACES"
: >"$PARAMS"
: >"$DIFFS"
: >"$CATALOG"

emit_array() {
  local key="$1" file="$2" line first=1
  if [[ ! -s "$file" ]]; then
    printf '  "%s": []' "$key"
    return
  fi
  printf '  "%s": [\n' "$key"
  sort "$file" | while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    if [[ $first -eq 1 ]]; then
      first=0
    else
      printf ',\n'
    fi
    printf '    %s' "$line"
  done
  printf '\n  ]'
}

write_record() {
  local status="$1" reason="$2" body
  body="$(
    {
      printf '{\n'
      printf '  "schema_version": 1,\n'
      printf '  "generated_on": "%s",\n' "$(json_escape "$generated_on")"
      printf '  "subject": "%s",\n' "$(json_escape "$subject")"
      printf '  "status": "%s",\n' "$(json_escape "$status")"
      printf '  "reason": "%s",\n' "$(json_escape "$reason")"
      emit_array tools "$TOOLS"
      printf ',\n'
      emit_array environments "$ENVS"
      printf ',\n'
      emit_array nodes "$NODES"
      printf ',\n'
      emit_array placements "$PLACES"
      printf ',\n'
      emit_array parameters "$PARAMS"
      printf ',\n'
      emit_array diffs "$DIFFS"
      printf ',\n'
      emit_array catalog "$CATALOG"
      printf '\n}\n'
    }
  )"
  if [[ -n "$out_file" ]]; then
    mkdir -p "$(dirname "$out_file")"
    printf '%s' "$body" >"$out_file"
  else
    printf '%s' "$body"
  fi
}

refuse() {
  : >"$ENVS"
  : >"$NODES"
  : >"$PLACES"
  : >"$PARAMS"
  : >"$DIFFS"
  : >"$CATALOG"
  write_record refused "$1"
  exit 0
}

add_tool() {
  local name="$1" shipped="$2" evidence="$3"
  local line
  line="$(printf '{"name":"%s","shipped":"%s","evidence":"%s"}' \
    "$(json_escape "$name")" "$(json_escape "$shipped")" "$(json_escape "$evidence")")"
  if ! grep -F -q "\"name\":\"$(json_escape "$name")\"" "$TOOLS" 2>/dev/null; then
    printf '%s\n' "$line" >>"$TOOLS"
  fi
}

if [[ "$live" -eq 1 ]]; then
  add_tool live no "--live"
  refuse "live-state-requested"
fi

if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  refuse "not-a-git-repository"
fi

if [[ -n "$containers_file" ]]; then
  if [[ ! -f "$containers_file" ]] || ! grep -q '"schema_version": 1' "$containers_file"; then
    add_tool containers no "$containers_file"
    refuse "containers-unreadable"
  fi
fi

: >"$TMP/compose.txt"
: >"$TMP/k8s.txt"
shipped=0
unshipped=0

is_compose() {
  local base
  base="$(basename "$1")"
  case "$base" in
  compose.yml | compose.yaml | docker-compose.yml | docker-compose.yaml) return 0 ;;
  compose.*.yml | compose.*.yaml | docker-compose.*.yml | docker-compose.*.yaml) return 0 ;;
  *) return 1 ;;
  esac
}

while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -n "$rel" ]] || continue
  [[ -f "$repo/$rel" ]] || continue
  base="$(basename "$rel")"
  case "$base" in
  deployment.json | deployment.md | deployment.dsl) continue ;;
  *) ;;
  esac
  if is_compose "$rel"; then
    printf '%s\n' "$rel" >>"$TMP/compose.txt"
    add_tool compose yes "$rel"
    shipped=1
    continue
  fi
  case "$base" in
  Chart.yaml | Chart.yml)
    add_tool helm no "$rel"
    unshipped=1
    continue
    ;;
  Pulumi.yaml | Pulumi.yml)
    add_tool pulumi no "$rel"
    unshipped=1
    continue
    ;;
  kustomization.yaml | kustomization.yml)
    add_tool kustomize no "$rel"
    unshipped=1
    continue
    ;;
  *.bicep)
    add_tool bicep no "$rel"
    unshipped=1
    continue
    ;;
  *.tf)
    if grep -q 'resource "' "$repo/$rel"; then
      add_tool terraform no "$rel"
      unshipped=1
    fi
    continue
    ;;
  *) ;;
  esac
  if grep -q 'AWSTemplateFormatVersion' "$repo/$rel"; then
    add_tool cloudformation no "$rel"
    unshipped=1
    continue
  fi
  case "$rel" in
  *.yml | *.yaml)
    if grep -q '{{' "$repo/$rel"; then
      add_tool helm no "$rel"
      unshipped=1
      continue
    fi
    if grep -E -q '^kind:[[:space:]]*(Deployment|StatefulSet|DaemonSet|Service|Ingress)[[:space:]]*$' "$repo/$rel" &&
      grep -q '^apiVersion:' "$repo/$rel"; then
      printf '%s\n' "$rel" >>"$TMP/k8s.txt"
      add_tool kubernetes yes "$rel"
      shipped=1
    fi
    ;;
  *) ;;
  esac
done < <(git -C "$repo" ls-files)

if [[ "$unshipped" -eq 1 ]]; then
  if [[ "$shipped" -eq 1 ]]; then
    refuse "partial-read"
  fi
  refuse "adapter-not-shipped"
fi
if [[ "$shipped" -eq 0 ]]; then
  refuse "no-declared-iac"
fi

env_of_compose() {
  local rel="$1" base dir
  base="$(basename "$rel")"
  base="${base%.yml}"
  base="${base%.yaml}"
  case "$base" in
  docker-compose.* | compose.*)
    printf '%s' "${base#*.}"
    ;;
  *)
    dir="$(dirname "$rel")"
    if [[ "$dir" == "." ]]; then
      printf 'default'
    else
      basename "$dir"
    fi
    ;;
  esac
}

if [[ -s "$TMP/compose.txt" ]]; then
  : >"$TMP/compose-replay.txt"
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    [[ -n "$rel" ]] || continue
    env_name="$(env_of_compose "$rel")"
    {
      printf '%s\n' "-- MAPDEP FILE $rel $env_name"
      cat "$repo/$rel"
      printf '\n'
    } >>"$TMP/compose-replay.txt"
  done <"$TMP/compose.txt"
  if ! awk -v places="$PLACES" -v params="$PARAMS" -v nodes="$NODES" -v envs="$ENVS" -v diffs="$DIFFS" -v flag="$TMP/compose-flag" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function ind(s,    i) { i = 1; while (substr(s, i, 1) == " ") i++; return i - 1 }
    function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function secret_key(k,    n) {
      n = tolower(k)
      gsub(/[^a-z0-9]/, "", n)
      return (n ~ /password/ || n ~ /passwd/ || n ~ /secret/ || n ~ /token/ || n ~ /apikey/ || n ~ /accountkey/ || n ~ /privatekey/)
    }
    function secret_value(v) {
      return (v ~ /[Pp]assword=/ || v ~ /AccountKey=/ || v ~ /:\/\/[^:]+:[^@]+@/)
    }
    function remember_env(e) { if (!(e in seen_env)) { seen_env[e] = 1; env_list[++env_n] = e } }
    function emit_place(env, svc,    nets, img, reps, ports) {
      nets = netjoin[env SUBSEP svc]
      if (nets == "") nets = "default"
      img = image[env SUBSEP svc]
      reps = replicas[env SUBSEP svc]
      if (reps == "") reps = "undeclared"
      ports = portjoin[env SUBSEP svc]
      printf "{\"container\":\"%s\",\"env\":\"%s\",\"tool\":\"compose\",\"node\":\"%s\",\"image\":\"%s\",\"replicas\":\"%s\",\"ports\":\"%s\",\"networks\":\"%s\",\"evidence\":\"%s\"}\n", \
        jesc(svc), jesc(env), jesc(nets), jesc(img), jesc(reps), jesc(ports), jesc(nets), jesc(evidence[env]) >> places
      printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"compose\",\"kind\":\"compute\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
        jesc(env "/" svc), jesc(env), jesc(svc), jesc(img), jesc(evidence[env]) >> nodes
    }
    BEGIN { env = ""; path = ""; bad = 0 }
    {
      raw = $0
      sub(/\r$/, "", raw)
      if (raw ~ /^-- MAPDEP FILE /) {
        if (svc != "" && env != "") emit_place(env, svc)
        split(substr(raw, 15), bits, " ")
        path = bits[1]
        env = bits[2]
        remember_env(env)
        evidence[env] = path
        section = ""
        svc = ""
        key = ""
        next
      }
      if (raw ~ /\t/ || index(raw, "{{") > 0) { bad = 1; next }
      if (raw ~ /^[ ]*#/) next
      line = raw
      sub(/[ ]+#.*$/, "", line)
      content = trim(line)
      if (content == "") next
      nind = ind(line)
      if (nind == 0) {
        if (svc != "" && env != "") emit_place(env, svc)
        svc = ""
        if (content == "services:") { section = "services"; key = "" }
        else if (content == "networks:") { section = "networks"; key = "" }
        else { section = ""; key = "" }
        next
      }
      if (section == "services" && nind == 2 && content ~ /:$/ && content !~ /^-/) {
        if (svc != "") emit_place(env, svc)
        svc = content
        sub(/:$/, "", svc)
        key = ""
        next
      }
      if (section == "services" && svc != "" && nind == 4 && content !~ /^-/) {
        if (content ~ /^image:/) {
          v = content
          sub(/^image:[[:space:]]*/, "", v)
          gsub(/^["'\'']|["'\'']$/, "", v)
          image[env SUBSEP svc] = v
          key = ""
        } else if (content ~ /^ports:/) key = "ports"
        else if (content ~ /^networks:/) key = "networks"
        else if (content ~ /^environment:/) key = "environment"
        else if (content ~ /^deploy:/) key = "deploy"
        else key = ""
        next
      }
      if (section == "services" && key == "ports" && content ~ /^-/) {
        v = content
        sub(/^-[[:space:]]*/, "", v)
        gsub(/^["'\'']|["'\'']$/, "", v)
        portjoin[env SUBSEP svc] = (portjoin[env SUBSEP svc] == "" ? v : portjoin[env SUBSEP svc] "," v)
        next
      }
      if (section == "services" && key == "networks" && content ~ /^-/) {
        v = content
        sub(/^-[[:space:]]*/, "", v)
        gsub(/^["'\'']|["'\'']$/, "", v)
        netjoin[env SUBSEP svc] = (netjoin[env SUBSEP svc] == "" ? v : netjoin[env SUBSEP svc] "," v)
        net_decl[env SUBSEP v] = 1
        next
      }
      if (section == "services" && key == "environment") {
        k = ""
        val = ""
        if (content ~ /^-/) {
          v = content
          sub(/^-[[:space:]]*/, "", v)
          gsub(/^["'\'']|["'\'']$/, "", v)
          split(v, kv, "=")
          k = kv[1]
          val = substr(v, length(k) + 2)
        } else if (content ~ /:/) {
          k = content
          sub(/:.*/, "", k)
          val = content
          sub(/^[^:]+:[[:space:]]*/, "", val)
          gsub(/^["'\'']|["'\'']$/, "", val)
        }
        if (k != "") {
          red = (secret_key(k) || secret_value(val)) ? "yes" : "no"
          shown = (red == "yes") ? "" : val
          printf "{\"parameter\":\"%s\",\"env\":\"%s\",\"tool\":\"compose\",\"container\":\"%s\",\"value\":\"%s\",\"redacted\":\"%s\",\"evidence\":\"%s\"}\n", \
            jesc(k), jesc(env), jesc(svc), jesc(shown), red, jesc(path) >> params
          if (red == "yes") secret_val[env SUBSEP svc SUBSEP k] = val
          else plain_val[env SUBSEP svc SUBSEP k] = val
          param_name[svc SUBSEP k] = 1
        }
        next
      }
      if (section == "services" && key == "deploy" && content ~ /^replicas:/) {
        v = content
        sub(/^replicas:[[:space:]]*/, "", v)
        replicas[env SUBSEP svc] = v
        next
      }
      if (section == "networks" && nind == 2 && content ~ /:$/) {
        net = content
        sub(/:$/, "", net)
        net_decl[env SUBSEP net] = 1
        net_exp[env SUBSEP net] = "published"
        next
      }
      if (section == "networks" && content ~ /^internal:[[:space:]]*true/) {
        net_exp[env SUBSEP net] = "internal"
      }
    }
    END {
      if (bad) { printf "compose-unreadable\n" > flag; exit 0 }
      if (svc != "" && env != "") emit_place(env, svc)
      for (e in seen_env) {
        printf "{\"environment\":\"%s\",\"tool\":\"compose\",\"evidence\":\"%s\"}\n", jesc(e), jesc(evidence[e]) >> envs
        for (nk in net_decl) {
          split(nk, np, SUBSEP)
          if (np[1] != e) continue
          exposure = net_exp[e SUBSEP np[2]]
          if (exposure == "") exposure = "published"
          printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"compose\",\"kind\":\"network\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
            jesc(e "/" np[2]), jesc(e), jesc(np[2]), jesc(exposure), jesc(evidence[e]) >> nodes
        }
      }
      # pair environments for declared diffs. Values of redacted parameters are
      # compared here and never printed.
      for (i = 1; i <= env_n; i++) for (j = i + 1; j <= env_n; j++) {
        a = env_list[i]; b = env_list[j]
        if (a > b) { t = a; a = b; b = t }
        for (sk in image) {
          split(sk, sp, SUBSEP)
          if (sp[1] != a && sp[1] != b) continue
          c = sp[2]
          if ((a SUBSEP c) in image && !((b SUBSEP c) in image))
            printf "{\"change\":\"removed\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"compose\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc("present only in " a) >> diffs
          else if ((b SUBSEP c) in image && !((a SUBSEP c) in image))
            printf "{\"change\":\"added\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"compose\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc("present only in " b) >> diffs
          else if ((a SUBSEP c) in image && (b SUBSEP c) in image && image[a SUBSEP c] != image[b SUBSEP c])
            printf "{\"change\":\"image\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"compose\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc(image[a SUBSEP c] " -> " image[b SUBSEP c]) >> diffs
        }
        for (sk in replicas) {
          split(sk, sp, SUBSEP)
          c = sp[2]
          if ((a SUBSEP c) in replicas && (b SUBSEP c) in replicas && replicas[a SUBSEP c] != replicas[b SUBSEP c])
            printf "{\"change\":\"replicas\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"compose\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc(replicas[a SUBSEP c] " -> " replicas[b SUBSEP c]) >> diffs
        }
        for (sk in portjoin) {
          split(sk, sp, SUBSEP)
          c = sp[2]
          if ((a SUBSEP c) in portjoin && (b SUBSEP c) in portjoin && portjoin[a SUBSEP c] != portjoin[b SUBSEP c])
            printf "{\"change\":\"ports\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"compose\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc(portjoin[a SUBSEP c] " -> " portjoin[b SUBSEP c]) >> diffs
        }
        for (sk in secret_val) {
          split(sk, sp, SUBSEP)
          c = sp[2]; param = sp[3]
          if ((a SUBSEP c SUBSEP param) in secret_val && (b SUBSEP c SUBSEP param) in secret_val && secret_val[a SUBSEP c SUBSEP param] != secret_val[b SUBSEP c SUBSEP param])
            printf "{\"change\":\"secret\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"compose\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc("secret parameter " param " differs") >> diffs
        }
        for (sk in plain_val) {
          split(sk, sp, SUBSEP)
          c = sp[2]; param = sp[3]
          if ((a SUBSEP c SUBSEP param) in plain_val && (b SUBSEP c SUBSEP param) in plain_val && plain_val[a SUBSEP c SUBSEP param] != plain_val[b SUBSEP c SUBSEP param])
            printf "{\"change\":\"parameter\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"compose\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc(param " " plain_val[a SUBSEP c SUBSEP param] " -> " plain_val[b SUBSEP c SUBSEP param]) >> diffs
        }
      }
    }
  ' "$TMP/compose-replay.txt"; then
    refuse "compose-unreadable"
  fi
  if [[ -s "$TMP/compose-flag" ]]; then
    refuse "$(head -n 1 "$TMP/compose-flag")"
  fi
fi

# The added/removed loops above can emit a container twice (once per side of
# the image array). Collapse exact duplicate JSON lines.
if [[ -s "$DIFFS" ]]; then
  sort -u "$DIFFS" -o "$DIFFS"
fi

if [[ -s "$TMP/k8s.txt" ]]; then
  : >"$TMP/k8s-replay.txt"
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    [[ -n "$rel" ]] || continue
    {
      printf '%s\n' "-- MAPDEP FILE $rel"
      cat "$repo/$rel"
      printf '\n'
    } >>"$TMP/k8s-replay.txt"
  done <"$TMP/k8s.txt"
  awk -v places="$PLACES" -v params="$PARAMS" -v nodes="$NODES" -v envs="$ENVS" -v diffs="$DIFFS" -v flag="$TMP/k8s-flag" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function secret_key(k,    n) {
      n = tolower(k)
      gsub(/[^a-z0-9]/, "", n)
      return (n ~ /password/ || n ~ /passwd/ || n ~ /secret/ || n ~ /token/ || n ~ /apikey/ || n ~ /accountkey/ || n ~ /privatekey/)
    }
    function secret_value(v) {
      return (v ~ /[Pp]assword=/ || v ~ /AccountKey=/ || v ~ /:\/\/[^:]+:[^@]+@/)
    }
    function remember_env(e) { if (e != "" && !(e in seen_env)) { seen_env[e] = 1; env_list[++env_n] = e } }
    function env_for(ns, path,    n, parts) {
      if (ns != "") return ns
      n = split(path, parts, "/")
      if (n >= 2) return parts[n - 1]
      return "default"
    }
    function flush(    e, img, reps) {
      if (kind == "" || meta == "") return
      e = env_for(ns, path)
      remember_env(e)
      evidence[e] = path
      if (kind == "Deployment" || kind == "StatefulSet" || kind == "DaemonSet") {
        if (cname == "") cname = meta
        img = cimage
        reps = replicas
        if (reps == "") reps = "undeclared"
        printf "{\"container\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"node\":\"%s\",\"image\":\"%s\",\"replicas\":\"%s\",\"ports\":\"%s\",\"networks\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(cname), jesc(e), jesc(e), jesc(img), jesc(reps), "", jesc(e), jesc(path) >> places
        image[e SUBSEP cname] = img
        replica_of[e SUBSEP cname] = reps
        printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"kind\":\"compute\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(e "/" cname), jesc(e), jesc(cname), jesc(img), jesc(path) >> nodes
      } else if (kind == "Service") {
        printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"kind\":\"network\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(e "/svc-" meta), jesc(e), jesc(meta), jesc(sport), jesc(path) >> nodes
        svc_port[e SUBSEP meta] = sport
      } else if (kind == "Ingress") {
        printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"kind\":\"ingress\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(e "/ing-" meta), jesc(e), jesc(meta), jesc(host), jesc(path) >> nodes
        ing_host[e SUBSEP meta] = host
      }
    }
    BEGIN { kind = ""; meta = ""; ns = ""; path = "" }
    {
      raw = $0
      sub(/\r$/, "", raw)
      if (raw ~ /^-- MAPDEP FILE /) {
        flush()
        path = trim(substr(raw, 15))
        kind = ""; meta = ""; ns = ""; replicas = ""; cname = ""; cimage = ""; sport = ""; host = ""
        in_meta = 0; in_c = 0; in_env = 0; ek = ""
        next
      }
      if (raw ~ /^---[[:space:]]*$/) { flush(); kind = ""; meta = ""; ns = ""; replicas = ""; cname = ""; cimage = ""; sport = ""; host = ""; in_meta = 0; in_c = 0; in_env = 0; next }
      if (raw ~ /\t/ || index(raw, "{{") > 0) { bad = 1; next }
      if (raw ~ /^kind:[[:space:]]*/) { kind = trim(substr(raw, 6)); next }
      if (raw ~ /^metadata:[[:space:]]*$/) { in_meta = 1; next }
      if (raw ~ /^spec:[[:space:]]*$/) { in_meta = 0; next }
      if (in_meta && raw ~ /^[[:space:]]+name:[[:space:]]*/) { meta = trim(substr(raw, index(raw, ":") + 1)); next }
      if (in_meta && raw ~ /^[[:space:]]+namespace:[[:space:]]*/) { ns = trim(substr(raw, index(raw, ":") + 1)); next }
      if (raw ~ /^[[:space:]]+replicas:[[:space:]]*[0-9]+[[:space:]]*$/ && replicas == "") {
        replicas = raw; sub(/.*replicas:[[:space:]]*/, "", replicas); replicas = trim(replicas); next
      }
      if (raw ~ /containers:[[:space:]]*$/) { in_c = 1; next }
      if (in_env && raw ~ /name:[[:space:]]*/) {
        ek = trim(substr(raw, index(raw, ":") + 1)); next
      }
      if (in_c && raw ~ /^[[:space:]]+-[[:space:]]*name:[[:space:]]*/) {
        cname = trim(substr(raw, index(raw, ":") + 1)); next
      }
      if (in_c && raw ~ /^[[:space:]]+image:[[:space:]]*/) {
        cimage = trim(substr(raw, index(raw, ":") + 1)); gsub(/^["'\'']|["'\'']$/, "", cimage); next
      }
      if (in_c && raw ~ /env:[[:space:]]*$/) { in_env = 1; next }
      if (in_env && raw ~ /^[[:space:]]+-[[:space:]]*name:[[:space:]]*/) {
        ek = trim(substr(raw, index(raw, ":") + 1)); next
      }
      if (in_env && ek != "" && raw ~ /^[[:space:]]+value:[[:space:]]*/) {
        val = trim(substr(raw, index(raw, ":") + 1))
        gsub(/^["'\'']|["'\'']$/, "", val)
        e = env_for(ns, path)
        red = (secret_key(ek) || secret_value(val)) ? "yes" : "no"
        shown = (red == "yes") ? "" : val
        printf "{\"parameter\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"container\":\"%s\",\"value\":\"%s\",\"redacted\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(ek), jesc(e), jesc(cname), jesc(shown), red, jesc(path) >> params
        if (red == "yes") secret_val[e SUBSEP cname SUBSEP ek] = val
        else plain_val[e SUBSEP cname SUBSEP ek] = val
        ek = ""
        next
      }
      if (kind == "Service" && raw ~ /^[[:space:]]+port:[[:space:]]*[0-9]+/) {
        sport = raw; sub(/.*port:[[:space:]]*/, "", sport); sport = trim(sport); next
      }
      if (kind == "Ingress" && raw ~ /host:[[:space:]]*/) {
        host = trim(substr(raw, index(raw, ":") + 1)); next
      }
    }
    END {
      if (bad) { printf "kubernetes-unreadable\n" > flag; exit 0 }
      flush()
      for (e in seen_env)
        printf "{\"environment\":\"%s\",\"tool\":\"kubernetes\",\"evidence\":\"%s\"}\n", jesc(e), jesc(evidence[e]) >> envs
      for (i = 1; i <= env_n; i++) for (j = i + 1; j <= env_n; j++) {
        a = env_list[i]; b = env_list[j]
        if (a > b) { t = a; a = b; b = t }
        for (sk in image) {
          split(sk, sp, SUBSEP)
          c = sp[2]
          if ((a SUBSEP c) in image && !((b SUBSEP c) in image))
            printf "{\"change\":\"removed\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"kubernetes\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc("present only in " a) >> diffs
          else if ((b SUBSEP c) in image && !((a SUBSEP c) in image))
            printf "{\"change\":\"added\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"kubernetes\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc("present only in " b) >> diffs
          else if ((a SUBSEP c) in image && (b SUBSEP c) in image && image[a SUBSEP c] != image[b SUBSEP c])
            printf "{\"change\":\"image\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"kubernetes\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc(image[a SUBSEP c] " -> " image[b SUBSEP c]) >> diffs
        }
        for (sk in replica_of) {
          split(sk, sp, SUBSEP)
          c = sp[2]
          if ((a SUBSEP c) in replica_of && (b SUBSEP c) in replica_of && replica_of[a SUBSEP c] != replica_of[b SUBSEP c] && replica_of[a SUBSEP c] != "undeclared" && replica_of[b SUBSEP c] != "undeclared")
            printf "{\"change\":\"replicas\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"kubernetes\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc(replica_of[a SUBSEP c] " -> " replica_of[b SUBSEP c]) >> diffs
        }
        for (sk in secret_val) {
          split(sk, sp, SUBSEP)
          c = sp[2]; param = sp[3]
          if ((a SUBSEP c SUBSEP param) in secret_val && (b SUBSEP c SUBSEP param) in secret_val && secret_val[a SUBSEP c SUBSEP param] != secret_val[b SUBSEP c SUBSEP param])
            printf "{\"change\":\"secret\",\"left\":\"%s\",\"right\":\"%s\",\"tool\":\"kubernetes\",\"container\":\"%s\",\"detail\":\"%s\"}\n", jesc(a), jesc(b), jesc(c), jesc("secret parameter " param " differs") >> diffs
        }
      }
    }
  ' "$TMP/k8s-replay.txt"
  if [[ -s "$TMP/k8s-flag" ]]; then
    refuse "$(head -n 1 "$TMP/k8s-flag")"
  fi
  if [[ -s "$DIFFS" ]]; then
    sort -u "$DIFFS" -o "$DIFFS"
  fi
fi

if [[ -n "$containers_file" ]]; then
  names="$(grep -E -o '"name"[[:space:]]*:[[:space:]]*"[^"]+"' "$containers_file" | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)"/\1/' | sort -u)"
  if [[ -z "$names" ]]; then
    add_tool containers no "$containers_file"
    refuse "containers-unreadable"
  fi
  while IFS= read -r cname || [[ -n "$cname" ]]; do
    [[ -n "$cname" ]] || continue
    placed="no"
    if grep -F -q "\"container\":\"$(json_escape "$cname")\"" "$PLACES"; then
      placed="yes"
    fi
    printf '{"catalog":"%s","placed":"%s"}\n' "$(json_escape "$cname")" "$placed" >>"$CATALOG"
  done <<<"$names"
fi

sort -u -o "$TOOLS" "$TOOLS"
sort -u -o "$ENVS" "$ENVS"
sort -u -o "$NODES" "$NODES"
sort -u -o "$PLACES" "$PLACES"
sort -u -o "$PARAMS" "$PARAMS"
sort -u -o "$DIFFS" "$DIFFS"
sort -u -o "$CATALOG" "$CATALOG"

write_record drawn ""
exit 0
