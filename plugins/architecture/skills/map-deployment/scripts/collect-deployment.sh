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
# Tracked files only (`git ls-files`), CI directories (.github and the like)
# excluded. Shipped readers: Compose and Kubernetes manifests. Terraform (any
# .tf, .tfvars, .tf.json), ARM templates, Pulumi, Bicep, CloudFormation, Helm
# (a Chart.yaml), and Kustomize are recognized and then the record is refused,
# including when a shipped reader also matches, so the diagram is never a
# partial read. A compose base file beside a compose.<x>.yaml override in one
# directory is refused as layered-compose: the layers merge into one
# environment and this reader does not merge them.
#
# Output: deployment.json, schema_version 1, one object per line. Every value
# written passes through plugins/architecture/lib/redact-connection.awk; a
# value or key that carries a credential is dropped.
#
# Exit: 0 = a record was written (including a refusal); 1 = bad path; 2 = usage.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT_AWK="$SCRIPT_DIR/../../../lib/redact-connection.awk"
# shellcheck source=../../../lib/github-remote.sh
source "$SCRIPT_DIR/../../../lib/github-remote.sh"

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
  [[ -f "$repo/$rel" && ! -L "$repo/$rel" ]] || continue
  base="$(basename "$rel")"
  case "$base" in
  deployment.json | deployment.md | deployment.dsl) continue ;;
  *) ;;
  esac
  case "$rel" in
  .github/* | */.github/* | .gitlab/* | */.gitlab/* | .circleci/* | */.circleci/* | .azuredevops/* | .buildkite/* | .forgejo/* | .gitea/*) continue ;;
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
  *.tf | *.tfvars | *.tf.json)
    add_tool terraform no "$rel"
    unshipped=1
    continue
    ;;
  *.json)
    if grep -E -q '"[$]schema"[[:space:]]*:[[:space:]]*"[^"]*deploymentTemplate' "$repo/$rel"; then
      add_tool arm no "$rel"
      unshipped=1
      continue
    fi
    ;;
  *) ;;
  esac
  if [[ "$base" == *.yml || "$base" == *.yaml || "$base" == *.json || "$base" == *.template ]] &&
    grep -E -q '^[[:space:]]*"?AWSTemplateFormatVersion"?[[:space:]]*:' "$repo/$rel"; then
    add_tool cloudformation no "$rel"
    unshipped=1
    continue
  fi
  case "$rel" in
  *.yml | *.yaml)
    # A template inside a chart belongs to Helm, which the Chart.yaml already declared.
    chart="$(dirname "$(dirname "$rel")")"
    if [[ "$(basename "$(dirname "$rel")")" == templates && (-f "$repo/$chart/Chart.yaml" || -f "$repo/$chart/Chart.yml") ]]; then
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

# A base file plus any variant in one directory is a merged stack, and a bare
# override is one half of it. Environment-per-directory layouts never match.
is_compose_base() {
  case "$(basename "$1")" in
  compose.yml | compose.yaml | docker-compose.yml | docker-compose.yaml) return 0 ;;
  *) return 1 ;;
  esac
}
: >"$TMP/compose-base-dirs.txt"
while IFS= read -r rel || [[ -n "$rel" ]]; do
  is_compose_base "$rel" && dirname "$rel" >>"$TMP/compose-base-dirs.txt"
done <"$TMP/compose.txt"
while IFS= read -r rel || [[ -n "$rel" ]]; do
  is_compose_base "$rel" && continue
  if [[ "$(basename "$rel")" == *override* ]] || grep -q -x -F "$(dirname "$rel")" "$TMP/compose-base-dirs.txt"; then
    refuse "layered-compose"
  fi
done <"$TMP/compose.txt"
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
  if ! awk -v places="$PLACES" -v params="$PARAMS" -v nodes="$NODES" -v envs="$ENVS" -v diffs="$DIFFS" -v flag="$TMP/compose-flag" -f "$REDACT_AWK" -f "$SCRIPT_DIR/deployment-diff.awk" -f - "$TMP/compose-replay.txt" <<<'
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function ind(s,    i) { i = 1; while (substr(s, i, 1) == " ") i++; return i - 1 }
    function jesc(s) { if (redact_secret_value(s)) s = "[redacted]"; gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function remember_env(e) { if (!(e in seen_env)) { seen_env[e] = 1; env_list[++env_n] = e } }
    function emit_place(env, svc,    nets, img, reps, ports) {
      nets = netjoin[env SUBSEP svc]
      if (nets == "") nets = "default"
      img = image[env SUBSEP svc]
      reps = replicas[env SUBSEP svc]
      if (reps == "") reps = "undeclared"
      ports = portjoin[env SUBSEP svc]
      placed[env SUBSEP svc] = 1
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
      if (raw ~ /\t/ || (index(raw, "{{") > 0 && raw ~ /^[[:space:]-]*(name|image|namespace|replicas|kind):/)) { bad = 1; next }
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
          red = redact_secret(k, val) ? "yes" : "no"
          shown = (red == "yes") ? "" : val
          printf "{\"parameter\":\"%s\",\"env\":\"%s\",\"tool\":\"compose\",\"container\":\"%s\",\"value\":\"%s\",\"redacted\":\"%s\",\"evidence\":\"%s\"}\n", \
            jesc(k), jesc(env), jesc(svc), jesc(shown), red, jesc(path) >> params
          if (red == "yes") secret_val[env SUBSEP svc SUBSEP k] = val
          else plain_val[env SUBSEP svc SUBSEP k] = val
          param_seen[env SUBSEP svc SUBSEP k] = 1
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
        param_port_diffs(a, b, "compose")
      }
    }
  '; then
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
  awk -v places="$PLACES" -v params="$PARAMS" -v nodes="$NODES" -v envs="$ENVS" -v diffs="$DIFFS" -v flag="$TMP/k8s-flag" -f "$REDACT_AWK" -f "$SCRIPT_DIR/deployment-diff.awk" -f - "$TMP/k8s-replay.txt" <<<'
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function jesc(s) { if (redact_secret_value(s)) s = "[redacted]"; gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function remember_env(e) { if (e != "" && !(e in seen_env)) { seen_env[e] = 1; env_list[++env_n] = e } }
    function env_for(ns, path,    n, parts) {
      if (ns != "") return ns
      n = split(path, parts, "/")
      if (n >= 2) return parts[n - 1]
      return "default"
    }
    function is_workload() { return kind == "Deployment" || kind == "StatefulSet" || kind == "DaemonSet" }
    # One workload can hold several containers (a sidecar); each is its own placement.
    function flush(    e) {
      if (kind == "" || meta == "") return
      e = env_for(ns, path)
      remember_env(e)
      evidence[e] = path
      if (is_workload()) {
        if (cname == "" && emitted == 0) cname = meta
        if (cname != "") emit_container(e)
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
    function emit_container(e,    img, reps) {
        emitted++
        img = cimage
        reps = replicas
        if (reps == "") reps = "undeclared"
        printf "{\"container\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"node\":\"%s\",\"image\":\"%s\",\"replicas\":\"%s\",\"ports\":\"%s\",\"networks\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(cname), jesc(e), jesc(e), jesc(img), jesc(reps), jesc(cports), jesc(e), jesc(path) >> places
        placed[e SUBSEP cname] = 1
        if (cports != "") portjoin[e SUBSEP cname] = cports
        image[e SUBSEP cname] = img
        replica_of[e SUBSEP cname] = reps
        printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"kind\":\"compute\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(e "/" cname), jesc(e), jesc(cname), jesc(img), jesc(path) >> nodes
    }
    function reset_resource() {
      kind = ""; meta = ""; ns = ""; replicas = ""; cname = ""; cimage = ""; cports = ""; sport = ""; host = ""
      in_meta = 0; in_c = 0; in_env = 0; ek = ""; cind = -1; emitted = 0
    }
    BEGIN { reset_resource(); path = "" }
    {
      raw = $0
      sub(/\r$/, "", raw)
      if (raw ~ /^-- MAPDEP FILE /) {
        flush()
        path = trim(substr(raw, 15))
        reset_resource()
        next
      }
      if (raw ~ /^---[[:space:]]*$/) { flush(); reset_resource(); next }
      if (raw ~ /\t/ || (index(raw, "{{") > 0 && raw ~ /^[[:space:]-]*(name|image|namespace|replicas|kind):/)) { bad = 1; next }
      if (raw ~ /^kind:[[:space:]]*/) { kind = trim(substr(raw, 6)); next }
      if (raw ~ /^metadata:[[:space:]]*$/) { in_meta = 1; next }
      if (raw ~ /^spec:[[:space:]]*$/) { in_meta = 0; next }
      if (in_meta && raw ~ /^[[:space:]]+name:[[:space:]]*/) { meta = trim(substr(raw, index(raw, ":") + 1)); next }
      if (in_meta && raw ~ /^[[:space:]]+namespace:[[:space:]]*/) { ns = trim(substr(raw, index(raw, ":") + 1)); next }
      if (raw ~ /^[[:space:]]+replicas:[[:space:]]*[0-9]+[[:space:]]*$/ && replicas == "") {
        replicas = raw; sub(/.*replicas:[[:space:]]*/, "", replicas); replicas = trim(replicas); next
      }
      if (raw ~ /containers:[[:space:]]*$/) { in_c = 1; next }
      # A list item at the first container item indent starts the next container.
      if (in_c && raw ~ /^[[:space:]]+-[[:space:]]*name:/) {
        match(raw, /^[[:space:]]+/)
        if (cind < 0 || RLENGTH == cind) {
          cind = RLENGTH
          if (cname != "" && is_workload()) emit_container(env_for(ns, path))
          cname = trim(substr(raw, index(raw, ":") + 1)); cimage = ""; cports = ""; in_env = 0; ek = ""; next
        }
      }
      if (in_c && raw ~ /containerPort:[[:space:]]*[0-9]+/) {
        v = raw; sub(/.*containerPort:[[:space:]]*/, "", v); v = trim(v)
        cports = (cports == "" ? v : cports "," v); next
      }
      if (in_env && raw ~ /name:[[:space:]]*/) {
        ek = trim(substr(raw, index(raw, ":") + 1)); next
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
        red = redact_secret(ek, val) ? "yes" : "no"
        shown = (red == "yes") ? "" : val
        printf "{\"parameter\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"container\":\"%s\",\"value\":\"%s\",\"redacted\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(ek), jesc(e), jesc(cname), jesc(shown), red, jesc(path) >> params
        if (red == "yes") secret_val[e SUBSEP cname SUBSEP ek] = val
        else plain_val[e SUBSEP cname SUBSEP ek] = val
        param_seen[e SUBSEP cname SUBSEP ek] = 1
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
        param_port_diffs(a, b, "kubernetes")
      }
    }
  '
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
