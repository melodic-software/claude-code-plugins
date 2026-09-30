#!/usr/bin/env bash
# Collect a per-environment deployment record from committed IaC.
#
# WHY. A deployment diagram is a fact only when every node is a declaration in
# a named file. This script reads Docker Compose, Kubernetes manifests,
# Terraform, Bicep, ARM, CloudFormation, and Pulumi YAML as text. It does not
# call a cloud API,
# even when --live is passed, and it never runs terraform, bicep, or az, or
# reads state.
#
# Usage:
#   collect-deployment.sh [--repo <path>] [--out <file>] [--generated-on <date>]
#       [--live] [--containers <file>]
#   collect-deployment.sh --help
#
# Tracked files only (`git ls-files`), CI directories (.github and the like)
# excluded. Shipped readers: Compose, Kubernetes manifests, and Terraform (.tf,
# .tf.json, .tfvars, .tfvars.json; see terraform-reader.awk), and Bicep and ARM
# templates with their .bicepparam and deploymentParameters files (see
# azure-reader.awk), CloudFormation YAML and JSON templates with their JSON
# parameter files, and Pulumi projects of runtime yaml with their
# Pulumi.<stack>.yaml files (see cloudformation-reader.awk, pulumi-reader.awk,
# and the shared yaml-rows.awk). A Pulumi project of any other runtime, Helm (a
# Chart.yaml, a Terraform helm_release, or a Pulumi kubernetes:helm.sh resource),
# and Kustomize are recognized and then the record is refused, including when a
# shipped reader also matches, so the diagram is never a partial read. A
# resource a shipped reader parses and has no mapping for is listed in
# `unmapped` (tool, resource type, file). When no container was placed and that
# list is not empty, the record is refused as no-mapped-container and keeps the
# list. A compose base file and its compose.override.yaml, or the files
# a tracked .env COMPOSE_FILE lists, merge in Compose merge order into one
# environment named for the directory: scalars are overridden, ports and
# networks append without duplicates, environment merges by key. Any other
# file beside them, an override with no base, or a !reset or !override tag
# refuses the record as compose-not-mergeable:<file>.
#
# A placement names the compute node it runs on (`compute`): a Compose service,
# or a Kubernetes workload shared by its containers. `relationships` holds the
# Service selector and Ingress backend links from a network or ingress node to
# a container.
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
EDGES="$TMP/edges.jsonl"
PARAMS="$TMP/params.jsonl"
DIFFS="$TMP/diffs.jsonl"
UNMAPPED="$TMP/unmapped.jsonl"
CATALOG="$TMP/catalog.jsonl"
: >"$TOOLS"
: >"$ENVS"
: >"$NODES"
: >"$PLACES"
: >"$EDGES"
: >"$PARAMS"
: >"$DIFFS"
: >"$UNMAPPED"
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
      emit_array relationships "$EDGES"
      printf ',\n'
      emit_array parameters "$PARAMS"
      printf ',\n'
      emit_array diffs "$DIFFS"
      printf ',\n'
      emit_array unmapped "$UNMAPPED"
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
  : >"$EDGES"
  : >"$PARAMS"
  : >"$DIFFS"
  : >"$CATALOG"
  # The refusal for a read that drew no container keeps the list that explains it.
  [[ "$1" == no-mapped-container ]] || : >"$UNMAPPED"
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
: >"$TMP/tf.txt"
: >"$TMP/azure.txt"
: >"$TMP/cfn.txt"
: >"$TMP/pulumi.txt"
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

# The runtime of a Pulumi.yaml: "yaml" only for a program written in the file itself.
# A main: key, or runtime options such as a compiler, make it something else.
pulumi_runtime() {
  awk -f - "$1" <<'AWK'
function unq(s) { gsub(/^["']|["']$/, "", s); return s }
function val(s) { sub(/[ \t]+#.*$/, "", s); return unq(trim(s)) }
function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
/^main:/ { extra = 1 }
/^runtime:[ \t]*(#.*)?$/ { blk = 1; next }
/^runtime:/ {
  v = $0; sub(/^runtime:[ \t]*/, "", v); blk = 0
  if (v ~ /^\{/) {
    if (v ~ /options/) extra = 1
    if (match(v, /name:[ \t]*["']?[A-Za-z0-9._+-]+/)) { rt = substr(v, RSTART, RLENGTH); sub(/name:[ \t]*["']?/, "", rt) }
  } else rt = val(v)
  next
}
blk && /^[ \t]+name:/ { v = $0; sub(/^[ \t]+name:[ \t]*/, "", v); rt = val(v); next }
blk && /^[ \t]+options:/ { extra = 1; next }
blk && /^[^ \t#]/ { blk = 0 }
END { rt = tolower(rt); if (rt !~ /^[a-z0-9._+-]+$/) rt = "unknown"; print (extra && rt == "yaml") ? "yaml-options" : rt }
AWK
}

# A CloudFormation template names the format version, or holds a Resources
# section with AWS:: types. A YAML file needs Resources at the left margin.
is_cfn_template() {
  local file="$1"
  if grep -E -q '^[[:space:]]*"?AWSTemplateFormatVersion"?[[:space:]]*:' "$file"; then
    return 0
  fi
  case "$file" in
  *.json) grep -E -q '"Resources"[[:space:]]*:' "$file" ;;
  *) grep -E -q '^Resources[[:space:]]*:' "$file" ;;
  esac && grep -E -q '"?Type"?[[:space:]]*:[[:space:]]*"?AWS::[A-Za-z0-9]+::[A-Za-z0-9]+' "$file"
}

# A CloudFormation parameter file: the ParameterKey/ParameterValue array, or an
# object whose first key is Parameters.
is_cfn_parameter_file() {
  grep -q '"ParameterKey"' "$1" && grep -q '"ParameterValue"' "$1" && return 0
  [[ "$(tr -d '[:space:]' <"$1" | head -c 15)" == '{"Parameters":{' ]] && ! grep -q '"Resources"' "$1"
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
    runtime="$(pulumi_runtime "$repo/$rel")"
    if [[ "$runtime" == yaml ]]; then
      printf '%s\n' "$rel" >>"$TMP/pulumi.txt"
      add_tool pulumi-yaml yes "$rel"
      shipped=1
      if grep -q 'kubernetes:helm\.sh/' "$repo/$rel"; then
        add_tool helm no "$rel (kubernetes:helm.sh)"
        unshipped=1
      fi
    else
      add_tool pulumi no "$rel (runtime $runtime)"
      unshipped=1
    fi
    continue
    ;;
  Pulumi.*.yaml | Pulumi.*.yml)
    printf '%s\n' "$rel" >>"$TMP/pulumi.txt"
    continue
    ;;
  kustomization.yaml | kustomization.yml)
    add_tool kustomize no "$rel"
    unshipped=1
    continue
    ;;
  *.bicep | *.bicepparam)
    printf '%s\n' "$rel" >>"$TMP/azure.txt"
    add_tool bicep yes "$rel"
    shipped=1
    continue
    ;;
  *.tf | *.tfvars | *.tf.json | *.tfvars.json)
    printf '%s\n' "$rel" >>"$TMP/tf.txt"
    add_tool terraform yes "$rel"
    shipped=1
    # A Helm release declared in Terraform is Helm, which this skill does not read.
    if grep -E -q '^[[:space:]]*resource[[:space:]]+"?helm_release"?[[:space:]]|"helm_release"[[:space:]]*:' "$repo/$rel"; then
      add_tool helm no "$rel (helm_release)"
      unshipped=1
    fi
    continue
    ;;
  *.json)
    if grep -E -i -q '"[$]schema"[[:space:]]*:[[:space:]]*"[^"]*deploymentTemplate' "$repo/$rel"; then
      printf '%s\n' "$rel" >>"$TMP/azure.txt"
      add_tool arm yes "$rel"
      shipped=1
      continue
    fi
    if grep -E -i -q '"[$]schema"[[:space:]]*:[[:space:]]*"[^"]*deploymentParameters' "$repo/$rel"; then
      printf '%s\n' "$rel" >>"$TMP/azure.txt"
      continue
    fi
    if is_cfn_parameter_file "$repo/$rel"; then
      printf '%s\n' "$rel" >>"$TMP/cfn.txt"
      continue
    fi
    ;;
  *) ;;
  esac
  if [[ "$base" == *.yml || "$base" == *.yaml || "$base" == *.json || "$base" == *.template ]] &&
    is_cfn_template "$repo/$rel"; then
    printf '%s\n' "$rel" >>"$TMP/cfn.txt"
    add_tool cloudformation yes "$rel"
    shipped=1
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

# Compose merges a base file with its override, or the files a tracked .env
# COMPOSE_FILE lists, in that order. The layers of one directory are one
# environment named for the directory. Any other file beside them has no
# declared place in the merge, so the record is refused naming it.
in_dir() {
  if [[ "$1" == "." ]]; then printf '%s' "$2"; else printf '%s/%s' "$1" "$2"; fi
}
: >"$TMP/compose-layers.txt"
while IFS= read -r dir || [[ -n "$dir" ]]; do
  files=()
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    [[ "$(dirname "$rel")" == "$dir" ]] && files+=("$rel")
  done <"$TMP/compose.txt"
  layers=()
  envfile="$(in_dir "$dir" .env)"
  if [[ -f "$repo/$envfile" && ! -L "$repo/$envfile" ]] && git -C "$repo" ls-files --error-unmatch -- "$envfile" >/dev/null 2>&1; then
    listed="$(sed -n 's/^COMPOSE_FILE=//p' "$repo/$envfile" | tail -n 1 | tr -d "\"'\r")"
    sep="$(sed -n 's/^COMPOSE_PATH_SEPARATOR=//p' "$repo/$envfile" | tail -n 1 | tr -d "\"'\r")"
    if [[ -n "$listed" ]]; then
      IFS="${sep:-:}" read -r -a entries <<<"$listed"
      for entry in "${entries[@]}"; do
        layer="$(in_dir "$dir" "$entry")"
        grep -q -x -F -- "$layer" "$TMP/compose.txt" || refuse "compose-not-mergeable:$layer"
        layers+=("$layer")
      done
    fi
  fi
  if [[ ${#layers[@]} -eq 0 ]]; then
    for name in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
      layer="$(in_dir "$dir" "$name")"
      grep -q -x -F -- "$layer" "$TMP/compose.txt" || continue
      layers+=("$layer")
      for ext in yaml yml; do
        layer="$(in_dir "$dir" "${name%%.y*}.override.$ext")"
        if grep -q -x -F -- "$layer" "$TMP/compose.txt"; then
          layers+=("$layer")
          break
        fi
      done
      break
    done
  fi
  if [[ ${#layers[@]} -gt 0 ]]; then
    for rel in "${files[@]}"; do
      printf '%s\n' "${layers[@]}" | grep -q -x -F -- "$rel" || refuse "compose-not-mergeable:$rel"
    done
    if [[ "$dir" == "." ]]; then layer_env=default; else layer_env="$(basename "$dir")"; fi
    for rel in "${layers[@]}"; do
      printf '%s\t%s\n' "$rel" "$layer_env" >>"$TMP/compose-layers.txt"
    done
  else
    for rel in "${files[@]}"; do
      [[ "$(basename "$rel")" == *override* ]] && refuse "compose-not-mergeable:$rel"
      printf '%s\t%s\n' "$rel" "$(env_of_compose "$rel")" >>"$TMP/compose-layers.txt"
    done
  fi
done < <(awk '{ if (sub(/\/[^\/]*$/, "")) print; else print "." }' "$TMP/compose.txt" | sort -u)

if [[ -s "$TMP/compose-layers.txt" ]]; then
  : >"$TMP/compose-replay.txt"
  while IFS=$'\t' read -r rel env_name || [[ -n "$rel" ]]; do
    [[ -n "$rel" ]] || continue
    {
      printf '%s\n' "-- MAPDEP FILE $rel $env_name"
      cat "$repo/$rel"
      printf '\n'
    } >>"$TMP/compose-replay.txt"
  done <"$TMP/compose-layers.txt"
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
      printf "{\"container\":\"%s\",\"env\":\"%s\",\"tool\":\"compose\",\"node\":\"%s\",\"compute\":\"%s\",\"image\":\"%s\",\"replicas\":\"%s\",\"ports\":\"%s\",\"networks\":\"%s\",\"evidence\":\"%s\"}\n", \
        jesc(svc), jesc(env), jesc(nets), jesc(env "/" svc), jesc(img), jesc(reps), jesc(ports), jesc(nets), jesc(evidence[env]) >> places
      printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"compose\",\"kind\":\"compute\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
        jesc(env "/" svc), jesc(env), jesc(svc), jesc(img), jesc(evidence[env]) >> nodes
    }
    function note_svc(e, s) { if (!((e SUBSEP s) in svc_seen)) { svc_seen[e SUBSEP s] = 1; svc_list[++svc_n] = e SUBSEP s } }
    function append_unique(map, k, v) {
      if ((k SUBSEP v) in uniq) return
      uniq[k SUBSEP v] = 1
      map[k] = (map[k] == "" ? v : map[k] "," v)
    }
    BEGIN { env = ""; path = ""; badmsg = "" }
    {
      raw = $0
      sub(/\r$/, "", raw)
      if (raw ~ /^-- MAPDEP FILE /) {
        split(substr(raw, 15), bits, " ")
        path = bits[1]
        env = bits[2]
        remember_env(env)
        if (env in evidence) evidence[env] = evidence[env] ", " path
        else evidence[env] = path
        section = ""
        svc = ""
        key = ""
        next
      }
      if (raw ~ /\t/ || (index(raw, "{{") > 0 && raw ~ /^[[:space:]-]*(name|image|namespace|replicas|kind):/)) { if (badmsg == "") badmsg = "compose-unreadable"; next }
      if (raw ~ /^[ ]*#/) next
      line = raw
      sub(/[ ]+#.*$/, "", line)
      content = trim(line)
      if (content == "") next
      if (content ~ /(^|[[:space:]:])!(reset|override)([[:space:]]|$)/) { if (badmsg == "") badmsg = "compose-not-mergeable:" path; next }
      nind = ind(line)
      if (nind == 0) {
        svc = ""
        if (content == "services:") { section = "services"; key = "" }
        else if (content == "networks:") { section = "networks"; key = "" }
        else { section = ""; key = "" }
        next
      }
      if (section == "services" && nind == 2 && content ~ /:$/ && content !~ /^-/) {
        svc = content
        sub(/:$/, "", svc)
        note_svc(env, svc)
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
        append_unique(portjoin, env SUBSEP svc, v)
        next
      }
      if (section == "services" && key == "networks" && content ~ /^-/) {
        v = content
        sub(/^-[[:space:]]*/, "", v)
        gsub(/^["'\'']|["'\'']$/, "", v)
        append_unique(netjoin, env SUBSEP svc, v)
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
          pk = env SUBSEP svc SUBSEP k
          if (!(pk in param_seen)) param_list[++param_n] = pk
          param_seen[pk] = 1
          param_path[pk] = path
          delete secret_val[pk]
          delete plain_val[pk]
          if (redact_secret(k, val)) secret_val[pk] = val
          else plain_val[pk] = val
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
        if (!((env SUBSEP net) in net_exp)) net_exp[env SUBSEP net] = "published"
        next
      }
      if (section == "networks" && content ~ /^internal:[[:space:]]*true/) {
        net_exp[env SUBSEP net] = "internal"
      } else if (section == "networks" && content ~ /^internal:[[:space:]]*false/) {
        net_exp[env SUBSEP net] = "published"
      }
    }
    END {
      if (badmsg != "") { print badmsg > flag; exit 0 }
      for (i = 1; i <= svc_n; i++) {
        split(svc_list[i], sp, SUBSEP)
        emit_place(sp[1], sp[2])
      }
      for (i = 1; i <= param_n; i++) {
        pk = param_list[i]
        split(pk, sp, SUBSEP)
        red = (pk in secret_val) ? "yes" : "no"
        printf "{\"parameter\":\"%s\",\"env\":\"%s\",\"tool\":\"compose\",\"container\":\"%s\",\"value\":\"%s\",\"redacted\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(sp[3]), jesc(sp[1]), jesc(sp[2]), jesc(red == "yes" ? "" : plain_val[pk]), red, jesc(param_path[pk]) >> params
      }
      for (e in seen_env) {
        printf "{\"environment\":\"%s\",\"tool\":\"compose\",\"evidence\":\"%s\"}\n", jesc(e), jesc(evidence[e]) >> envs
        for (nk in net_decl) {
          split(nk, np, SUBSEP)
          if (np[1] != e) continue
          exposure = net_exp[e SUBSEP np[2]]
          if (exposure == "") exposure = "published"
          printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"compose\",\"kind\":\"network\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
            jesc(e "/" np[2]), jesc(e), jesc(np[2]), jesc(exposure), jesc(evidence[e]) >> nodes
          node_seen[e SUBSEP "network" SUBSEP np[2]] = exposure
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
        node_diffs(a, b, "compose")
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
  awk -v places="$PLACES" -v edges="$EDGES" -v params="$PARAMS" -v nodes="$NODES" -v envs="$ENVS" -v diffs="$DIFFS" -v flag="$TMP/k8s-flag" -f "$REDACT_AWK" -f "$SCRIPT_DIR/deployment-diff.awk" -f - "$TMP/k8s-replay.txt" <<<'
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function jesc(s) { if (redact_secret_value(s)) s = "[redacted]"; gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function remember_env(e) { if (e != "" && !(e in seen_env)) { seen_env[e] = 1; env_list[++env_n] = e } }
    function env_for(ns, path,    n, parts) {
      if (ns != "") return ns
      n = split(path, parts, "/")
      if (n >= 2) return parts[n - 1]
      return "default"
    }
    function ind(s) { match(s, /^ */); return RLENGTH }
    function is_workload() { return kind == "Deployment" || kind == "StatefulSet" || kind == "DaemonSet" }
    function add_line(list, item) { return (list == "" ? item : list "\n" item) }
    # One workload can hold several containers (a sidecar); each is its own placement,
    # and all of them run on the workload node.
    function flush(    e, key, n, pairs, i) {
      if (kind == "" || meta == "") return
      e = env_for(ns, path)
      remember_env(e)
      evidence[e] = path
      key = e SUBSEP meta
      if (is_workload()) {
        if (cname == "" && emitted == 0) cname = meta
        if (cname != "") emit_container(e)
        wl_list[++wl_cnt] = key
        n = split(pod_pairs, pairs, "\n")
        for (i = 1; i <= n; i++) if (pairs[i] != "") pod_has[key SUBSEP pairs[i]] = 1
      } else if (kind == "Service") {
        printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"kind\":\"network\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(e "/svc-" meta), jesc(e), jesc(meta), jesc(sport), jesc(path) >> nodes
        node_seen[e SUBSEP "network" SUBSEP meta] = sport
        svc_port[key] = sport
        svc_list[++svc_cnt] = key
        svc_sel[key] = sel
        svc_path[key] = path
      } else if (kind == "Ingress") {
        printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"kind\":\"ingress\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(e "/ing-" meta), jesc(e), jesc(meta), jesc(host), jesc(path) >> nodes
        node_seen[e SUBSEP "ingress" SUBSEP meta] = host
        ing_host[key] = host
        ing_list[++ing_cnt] = key
        ing_be[key] = backends
        ing_path[key] = path
      }
    }
    function emit_container(e,    img, reps, wl) {
        emitted++
        img = cimage
        reps = replicas
        if (reps == "") reps = "undeclared"
        wl = (meta != "" ? meta : cname)
        if (emitted == 1)
          printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"kind\":\"compute\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
            jesc(e "/wl-" wl), jesc(e), jesc(wl), jesc(kind), jesc(path) >> nodes
        printf "{\"container\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"node\":\"%s\",\"compute\":\"%s\",\"image\":\"%s\",\"replicas\":\"%s\",\"ports\":\"%s\",\"networks\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(cname), jesc(e), jesc(e), jesc(e "/wl-" wl), jesc(img), jesc(reps), jesc(cports), jesc(e), jesc(path) >> places
        placed[e SUBSEP cname] = 1
        if (cports != "") portjoin[e SUBSEP cname] = cports
        image[e SUBSEP cname] = img
        replica_of[e SUBSEP cname] = reps
        wl_c[e, wl, ++wl_cn[e, wl]] = cname
    }
    function selects(skey, wkey,    n, pairs, i) {
      if (svc_sel[skey] == "") return 0
      n = split(svc_sel[skey], pairs, "\n")
      for (i = 1; i <= n; i++) if (!((wkey SUBSEP pairs[i]) in pod_has)) return 0
      return 1
    }
    function emit_edge(from, label, evid, wkey,    wp, i) {
      split(wkey, wp, SUBSEP)
      for (i = 1; i <= wl_cn[wp[1], wp[2]]; i++)
        printf "{\"from\":\"%s\",\"to\":\"%s\",\"to_compute\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"label\":\"%s\",\"evidence\":\"%s\"}\n", \
          jesc(from), jesc(wl_c[wp[1], wp[2], i]), jesc(wp[1] "/wl-" wp[2]), jesc(wp[1]), jesc(label), jesc(evid) >> edges
    }
    # A Service selects the containers of every workload whose pod labels hold its whole
    # selector; an Ingress routes to the containers of the Services its backends name.
    function emit_edges(    s, w, g, b, n, be, sp, ip, wp, skey, disp) {
      for (s = 1; s <= svc_cnt; s++) for (w = 1; w <= wl_cnt; w++) {
        split(svc_list[s], sp, SUBSEP); split(wl_list[w], wp, SUBSEP)
        if (sp[1] != wp[1] || !selects(svc_list[s], wl_list[w])) continue
        disp = svc_sel[svc_list[s]]; gsub(/\n/, ",", disp)
        emit_edge(sp[1] "/svc-" sp[2], "selects " disp, svc_path[svc_list[s]], wl_list[w])
      }
      for (g = 1; g <= ing_cnt; g++) {
        split(ing_list[g], ip, SUBSEP)
        n = split(ing_be[ing_list[g]], be, "\n")
        for (b = 1; b <= n; b++) {
          if (be[b] == "" || (g SUBSEP be[b]) in be_done) continue
          be_done[g SUBSEP be[b]] = 1
          skey = ip[1] SUBSEP be[b]
          if (!(skey in svc_sel)) continue
          for (w = 1; w <= wl_cnt; w++) {
            split(wl_list[w], wp, SUBSEP)
            if (wp[1] == ip[1] && selects(skey, wl_list[w]))
              emit_edge(ip[1] "/ing-" ip[2], "routes " (ing_host[ing_list[g]] != "" ? ing_host[ing_list[g]] : be[b]), ing_path[ing_list[g]], wl_list[w])
          }
        }
      }
    }
    function reset_resource() {
      kind = ""; meta = ""; ns = ""; replicas = ""; cname = ""; cimage = ""; cports = ""; sport = ""; host = ""
      in_meta = 0; in_c = 0; in_env = 0; ek = ""; cind = -1; emitted = 0
      blk = ""; blk_ind = 0; in_isvc = 0; no_pod = 0; pod_pairs = ""; sel = ""; backends = ""
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
      # A key: value block (pod labels, a Service selector) runs until the indent falls back.
      if (blk != "") {
        if (raw ~ /^[[:space:]]*(#.*)?$/) next
        if (ind(raw) > blk_ind) {
          if (blk != "skip" && raw ~ /:/) {
            v = trim(raw)
            k = v; sub(/:.*/, "", k)
            sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/^["'\'']|["'\'']$/, "", v)
            if (blk == "pod") pod_pairs = add_line(pod_pairs, k "=" v)
            else sel = add_line(sel, k "=" v)
          }
          next
        }
        blk = ""
      }
      if (raw ~ /^[[:space:]]+labels:[[:space:]]*$/) { blk = (!in_meta && !no_pod) ? "pod" : "skip"; blk_ind = ind(raw); next }
      if (raw ~ /^[[:space:]]+selector:[[:space:]]*$/) { blk = "sel"; blk_ind = ind(raw); next }
      if (raw ~ /volumeClaimTemplates:/) { no_pod = 1; next }
      if (raw ~ /^[[:space:]]+service:[[:space:]]*$/) { in_isvc = 1; next }
      if (in_isvc && raw ~ /^[[:space:]]+name:[[:space:]]*/) {
        backends = add_line(backends, trim(substr(raw, index(raw, ":") + 1))); in_isvc = 0; next
      }
      if (raw ~ /^[[:space:]]+serviceName:[[:space:]]*/) {
        backends = add_line(backends, trim(substr(raw, index(raw, ":") + 1))); next
      }
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
      # A valueFrom reference (a Secret, ConfigMap, or field) has no value here: its presence is
      # recorded as a redacted parameter and never compared beyond that.
      if (in_env && ek != "" && raw ~ /^[[:space:]]+valueFrom:/) {
        e = env_for(ns, path)
        printf "{\"parameter\":\"%s\",\"env\":\"%s\",\"tool\":\"kubernetes\",\"container\":\"%s\",\"value\":\"\",\"redacted\":\"yes\",\"evidence\":\"%s\"}\n", \
          jesc(ek), jesc(e), jesc(cname), jesc(path) >> params
        secret_val[e SUBSEP cname SUBSEP ek] = "valueFrom"
        param_seen[e SUBSEP cname SUBSEP ek] = 1
        ek = ""
        next
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
      emit_edges()
      for (e in seen_env)
        printf "{\"environment\":\"%s\",\"tool\":\"kubernetes\",\"evidence\":\"%s\"}\n", jesc(e), jesc(evidence[e]) >> envs
      for (i = 1; i <= env_n; i++) for (j = i + 1; j <= env_n; j++) {
        a = env_list[i]; b = env_list[j]
        if (a > b) { t = a; a = b; b = t }
        container_diffs(a, b, "kubernetes")
        param_port_diffs(a, b, "kubernetes")
        node_diffs(a, b, "kubernetes")
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

if [[ -s "$TMP/tf.txt" ]]; then
  tf_args=()
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    tf_args+=("./$rel")
  done <"$TMP/tf.txt"
  if ! (cd "$repo" && awk -v places="$PLACES" -v params="$PARAMS" -v nodes="$NODES" -v envs="$ENVS" -v diffs="$DIFFS" -v unmapped="$UNMAPPED" -v flag="$TMP/tf-flag" \
    -f "$REDACT_AWK" -f "$SCRIPT_DIR/deployment-diff.awk" -f "$SCRIPT_DIR/terraform-reader.awk" "${tf_args[@]}"); then
    refuse "terraform-unreadable"
  fi
  if [[ -s "$TMP/tf-flag" ]]; then
    refuse "$(head -n 1 "$TMP/tf-flag")"
  fi
fi

# Bicep and ARM share one reader, run once per tool so each tool's environments
# are diffed only against its own.
if [[ -s "$TMP/azure.txt" ]]; then
  az_args=()
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    az_args+=("./$rel")
  done <"$TMP/azure.txt"
  for az_tool in bicep arm; do
    grep -q "\"name\":\"$az_tool\"" "$TOOLS" || continue
    if ! (cd "$repo" && awk -v tool="$az_tool" -v places="$PLACES" -v params="$PARAMS" -v nodes="$NODES" -v envs="$ENVS" -v diffs="$DIFFS" -v unmapped="$UNMAPPED" -v flag="$TMP/az-flag" \
      -f "$REDACT_AWK" -f "$SCRIPT_DIR/deployment-diff.awk" -f "$SCRIPT_DIR/azure-reader.awk" "${az_args[@]}"); then
      refuse "$az_tool-unreadable"
    fi
    if [[ -s "$TMP/az-flag" ]]; then
      refuse "$(head -n 1 "$TMP/az-flag")"
    fi
  done
fi

# CloudFormation and Pulumi YAML share one flattener and run once per tool.
for yaml_tool in cloudformation pulumi-yaml; do
  grep -q "\"name\":\"$yaml_tool\"" "$TOOLS" || continue
  yaml_list="$TMP/cfn.txt"
  yaml_reader="cloudformation-reader.awk"
  if [[ "$yaml_tool" == pulumi-yaml ]]; then
    yaml_list="$TMP/pulumi.txt"
    yaml_reader="pulumi-reader.awk"
  fi
  yaml_args=()
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    yaml_args+=("./$rel")
  done <"$yaml_list"
  if ! (cd "$repo" && awk -v tool="$yaml_tool" -v places="$PLACES" -v params="$PARAMS" -v nodes="$NODES" -v envs="$ENVS" -v diffs="$DIFFS" -v unmapped="$UNMAPPED" -v flag="$TMP/yaml-flag" \
    -f "$REDACT_AWK" -f "$SCRIPT_DIR/deployment-diff.awk" -f "$SCRIPT_DIR/yaml-rows.awk" -f "$SCRIPT_DIR/$yaml_reader" "${yaml_args[@]}"); then
    refuse "${yaml_tool%-yaml}-unreadable"
  fi
  if [[ -s "$TMP/yaml-flag" ]]; then
    refuse "$(head -n 1 "$TMP/yaml-flag")"
  fi
done

# Resources were read and none of them is a container the readers map: an empty
# environment would look like a full read.
if [[ ! -s "$PLACES" && -s "$UNMAPPED" ]]; then
  refuse "no-mapped-container"
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
sort -u -o "$EDGES" "$EDGES"
sort -u -o "$PARAMS" "$PARAMS"
sort -u -o "$DIFFS" "$DIFFS"
sort -u -o "$UNMAPPED" "$UNMAPPED"
sort -u -o "$CATALOG" "$CATALOG"

write_record drawn ""
exit 0
