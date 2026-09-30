#!/usr/bin/env bash
# Render deployment.md from a collect-deployment.sh record.
#
# Usage:
#   render-deployment.sh --record <deployment.json> --out <dir>
#       [--dialect likec4|c4-plantuml|none] [--env <name>] [--diff <a> <b>]
#   render-deployment.sh --help
#
# --dialect is diagram_dialect.system, resolved by lib/resolve-diagram-dialect.sh.
# likec4 and c4-plantuml write deployment.md with one fenced likec4 or plantuml
# block. none (the default) writes the same file with the tables and no diagram.
# Every printed value passes through lib/redact-connection.awk.
#
# Exit: 0 rendered; 1 unreadable record; 2 usage; 3 unknown environment,
# refusal rendered.
set -uo pipefail

REDACT_AWK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/redact-connection.awk"

usage() {
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf 'render-deployment.sh: %s\n' "$1" >&2
  exit "$2"
}

record=""
out=""
dialect="none"
env_filter=""
diff_a=""
diff_b=""

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
  --out)
    [[ $# -ge 2 ]] || die "--out needs a path" 2
    out="$2"
    shift 2
    ;;
  --dialect)
    [[ $# -ge 2 ]] || die "--dialect needs a value" 2
    dialect="$2"
    shift 2
    ;;
  --env)
    [[ $# -ge 2 ]] || die "--env needs a name" 2
    env_filter="$2"
    shift 2
    ;;
  --diff)
    [[ $# -ge 3 ]] || die "--diff needs two environments" 2
    diff_a="$2"
    diff_b="$3"
    shift 3
    ;;
  *)
    die "unknown argument: $1" 2
    ;;
  esac
done

[[ -n "$record" && -n "$out" ]] || die "--record and --out are required" 2
[[ -f "$record" ]] || die "record is not a file: $record" 1
case "$dialect" in
likec4 | c4-plantuml | none) ;;
*) die "--dialect must be likec4, c4-plantuml, or none, got: $dialect" 2 ;;
esac

md="$out/deployment.md"
target="$md"
mkdir -p "$out"

set +e
summary="$(
  awk -v dialect="$dialect" -v env_filter="$env_filter" -v diff_a="$diff_a" -v diff_b="$diff_b" -v md="$target" -f "$REDACT_AWK" -f - "$record" <<<'
    function die(msg) { printf "render-deployment.sh: %s\n", msg > "/dev/stderr"; exit 1 }
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function clean(s) { return redact_secret_value(s) ? "[redacted]" : s }
    function lab(s) { s = clean(s); gsub(/[`"'\''\\]/, "", s); gsub(/[\r\n]/, " ", s); gsub(/@/, "(at)", s); return s }
    function field(line, key,    re, rest, i) {
      re = "\"" key "\":"
      i = index(line, re)
      if (i == 0) return ""
      rest = substr(line, i + length(re))
      sub(/^[[:space:]]*/, "", rest)
      if (substr(rest, 1, 1) != "\"") return ""
      rest = substr(rest, 2)
      i = index(rest, "\"")
      if (i == 0) return ""
      return substr(rest, 1, i - 1)
    }
    function jget(line, key,    s) { s = field(line, key); gsub(/\\"/, "\"", s); gsub(/\\\\/, "\\", s); return s }
    function safe(s) { s = clean(s); gsub(/"/, "'\''", s); gsub(/\|/, "/", s); gsub(/`/, "'\''", s); gsub(/[\r\n]/, " ", s); return s }
    function hostof(p) { return (p in host) ? host[p] : "" }
    function alias(prefix, i, s,    a) { a = clean(s); gsub(/[^A-Za-z0-9_]/, "_", a); return prefix i "_" a }
    function take_array(first, key, prefix,    line, item) {
      line = trim(first)
      if (line == "\"" key "\": []" || line == "\"" key "\": [],") return
      if (line != "\"" key "\": [") die(key " is not one object per line or []")
      while ((getline line) > 0) {
        item = trim(line)
        if (item == "]" || item == "],") return
        sub(/,$/, "", item)
        if (index(item, prefix) != 1) die(key " line is not one " prefix " object")
        count[key]++
        held[key, count[key]] = item
      }
      die(key " array was not closed")
    }
    function reason_prose(r) {
      if (r == "live-state-requested") return "A live-state comparison was requested. No live adapter is shipped, and committed IaC was not read. No diagram was drawn."
      if (r == "partial-read") return "More than one IaC tool is declared, and at least one has no shipped adapter. Drawing the shipped subset would be a partial read. No diagram was drawn."
      if (r == "adapter-not-shipped") return "The only IaC tools in this repository have no shipped adapter. No diagram was drawn."
      if (r == "no-declared-iac") return "No Compose file, Kubernetes manifest, or Terraform configuration was found in tracked files. No diagram was drawn."
      if (index(r, "terraform-unreadable") == 1) return "The named Terraform file did not parse (an unclosed block, string, comment, or heredoc). It was not half-read. No diagram was drawn."
      if (index(r, "terraform-module-unread:") == 1) return "The named module call has a remote source, or a local source with no tracked configuration. Its resources cannot be read from this repository, so the root was not half-read. The source is not printed. No diagram was drawn."
      if (index(r, "terraform-orphan-tfvars:") == 1) return "The named tfvars file has no Terraform configuration at or above its directory, so it belongs to no root. No diagram was drawn."
      if (r == "not-a-git-repository") return "The subject is not a git repository, so tracked IaC cannot be separated from untracked files. No diagram was drawn."
      if (r == "compose-unreadable" || r == "kubernetes-unreadable") return "A shipped manifest used a construct this adapter does not read (a tab, or a template marker in a name, image, namespace, replicas, or kind field). No diagram was drawn."
      if (r == "containers-unreadable") return "containers.json was present and is not a schema_version 1 catalog. It was not half-read. No diagram was drawn."
      if (index(r, "compose-not-mergeable:") == 1) return "The named Compose file has no declared place in a merge (a variant beside a base with no COMPOSE_FILE order, an override with no base, a second base) or uses a !reset or !override tag this adapter does not merge. It was not guessed. No diagram was drawn."
      if (r == "unknown-environment") return "A requested environment (--env or --diff) is not in the record. No diagram was drawn."
      return "The record refused to draw a diagram."
    }
    BEGIN {
      if ((getline line) <= 0) die("empty record")
      if (trim(line) != "{") die("record does not start with an object")
      if ((getline line) <= 0) die("missing schema_version")
      if (trim(line) != "\"schema_version\": 1,") die("not schema_version 1")
      while ((getline line) > 0) {
        t = trim(line)
        if (t == "}") break
        if (t ~ /^"generated_on":/) generated = jget(t, "generated_on")
        else if (t ~ /^"subject":/) subject = jget(t, "subject")
        else if (t ~ /^"status":/) status = jget(t, "status")
        else if (t ~ /^"reason":/) reason = jget(t, "reason")
        else if (t ~ /^"tools":/) take_array(t, "tools", "{\"name\":")
        else if (t ~ /^"environments":/) take_array(t, "environments", "{\"environment\":")
        else if (t ~ /^"nodes":/) take_array(t, "nodes", "{\"id\":")
        else if (t ~ /^"placements":/) take_array(t, "placements", "{\"container\":")
        else if (t ~ /^"relationships":/) take_array(t, "relationships", "{\"from\":")
        else if (t ~ /^"parameters":/) take_array(t, "parameters", "{\"parameter\":")
        else if (t ~ /^"diffs":/) take_array(t, "diffs", "{\"change\":")
        else if (t ~ /^"catalog":/) take_array(t, "catalog", "{\"catalog\":")
        else if (t ~ /^"[a-z_]+": \[$/) die("unknown array " t)
      }
      if (status != "drawn" && status != "refused") die("status is missing")
      ne = count["environments"] + 0
      for (i = 1; i <= ne; i++) env_name[i] = jget(held["environments", i], "environment")
      exit_code = 0
      if (status == "drawn") {
        nreq = split(env_filter "\n" diff_a "\n" diff_b, req, "\n")
        for (r = 1; r <= nreq; r++) {
          if (req[r] == "") continue
          found = 0
          for (i = 1; i <= ne; i++) if (env_name[i] == req[r]) found = 1
          if (!found) { status = "refused"; reason = "unknown-environment"; exit_code = 3; break }
        }
      }
      reason = safe(reason)
      print "# Deployment" > md
      print "" > md
      print "Generated on " safe(generated) "." > md
      print "" > md
      print "Subject: " safe(subject) "." > md
      print "" > md
      print "Status: " status "." > md
      print "" > md
      if (status == "refused") {
        print "Reason: " reason "." > md
        print "" > md
        print reason_prose(reason) > md
        print "" > md
      } else {
        print "Dialect: " dialect ", from diagram_dialect.system." > md
        print "" > md
        if (env_filter != "") { print "Environment: " safe(env_filter) "." > md; print "" > md }
      }
      print "## Tools" > md
      print "" > md
      nt = count["tools"] + 0
      if (nt == 0) print "None." > md
      else {
        print "| Name | Shipped | Evidence |" > md
        print "|---|---|---|" > md
        for (i = 1; i <= nt; i++) {
          item = held["tools", i]
          print "| " safe(jget(item, "name")) " | " safe(jget(item, "shipped")) " | " safe(jget(item, "evidence")) " |" > md
        }
      }
      print "" > md
      if (reason == "unknown-environment") {
        print "## Environments" > md
        print "" > md
        for (i = 1; i <= ne; i++) print "- " safe(env_name[i]) > md
        print "" > md
      }
      ndiffs = count["diffs"] + 0
      shown_d = 0
      if (status != "refused") {
        print "## Diff" > md
        print "" > md
        if (diff_a == "") {
          print "No --diff was requested. Declared differences between environments are listed when two environments were collected." > md
          print "" > md
        }
        for (i = 1; i <= ndiffs; i++) {
          item = held["diffs", i]
          L = jget(item, "left"); R = jget(item, "right")
          if (diff_a != "" && !((L == diff_a && R == diff_b) || (L == diff_b && R == diff_a))) continue
          if (env_filter != "" && L != env_filter && R != env_filter) continue
          shown_d++
          rows[shown_d] = "| " safe(jget(item, "change")) " | " safe(L) " / " safe(R) " | " safe(jget(item, "tool")) " | " safe(jget(item, "container")) " | " safe(jget(item, "detail")) " |"
        }
        kinds = "container added or removed, image, replicas, ports, network or Ingress added or removed, network exposure or port or Ingress host, parameter added or removed, parameter value, secret parameter differs (the value is never printed)"
        if (shown_d == 0) {
          print "No differences of these kinds: " kinds "." > md
        } else {
          print "Kinds compared: " kinds "." > md
          print "" > md
          print "| Change | Environments | Tool | Container | Detail |" > md
          print "|---|---|---|---|---|" > md
          for (i = 1; i <= shown_d; i++) print rows[i] > md
        }
        print "" > md
        print "Networks and Ingress hosts are not compared." > md
        print "" > md
        print "## Diagram" > md
        print "" > md
        np = count["placements"] + 0
        nn = count["nodes"] + 0
        nr = count["relationships"] + 0
        drawn_p = 0
        for (n = 1; n <= nn; n++)
          if (jget(held["nodes", n], "kind") == "compute") cnode[jget(held["nodes", n], "env") SUBSEP jget(held["nodes", n], "id")] = 1
        for (p = 1; p <= np; p++) {
          pit = held["placements", p]
          cid = jget(pit, "compute")
          if (cid != "" && ((jget(pit, "env") SUBSEP cid) in cnode)) { host[p] = cid; hosts[jget(pit, "env") SUBSEP cid] = 1 }
        }
        if (dialect == "c4-plantuml") {
          print "```plantuml" > md
          print "@startuml" > md
          print "!include <C4/C4_Deployment>" > md
          for (i = 1; i <= ne; i++) {
            e = env_name[i]
            if (env_filter != "" && e != env_filter) continue
            print "Deployment_Node(" alias("env", i, e) ", \"" lab(e) "\", \"environment\") {" > md
            for (n = 1; n <= nn; n++) {
              item = held["nodes", n]
              if (jget(item, "env") != e || jget(item, "kind") == "compute") continue
              net_alias[e SUBSEP jget(item, "name")] = alias("n", n, jget(item, "name"))
              node_alias[e SUBSEP jget(item, "id")] = alias("n", n, jget(item, "name"))
              print "  Deployment_Node(" alias("n", n, jget(item, "name")) ", \"" lab(jget(item, "name")) "\", \"" lab(jget(item, "kind")) "\", \"" lab(jget(item, "detail")) "\")" > md
            }
            for (n = 1; n <= nn; n++) {
              item = held["nodes", n]
              if (jget(item, "env") != e || jget(item, "kind") != "compute" || !((e SUBSEP jget(item, "id")) in hosts)) continue
              print "  Deployment_Node(" alias("cn", n, jget(item, "name")) ", \"" lab(jget(item, "name")) "\", \"compute\", \"" lab(jget(item, "detail")) "\") {" > md
              for (p = 1; p <= np; p++) {
                pit = held["placements", p]
                if (jget(pit, "env") != e || hostof(p) != jget(item, "id")) continue
                drawn_p++
                print "    Container(" alias("c", p, jget(pit, "container")) ", \"" lab(jget(pit, "container")) "\", \"" lab(jget(pit, "image")) "\", \"replicas " lab(jget(pit, "replicas")) "\")" > md
              }
              print "  }" > md
            }
            for (p = 1; p <= np; p++) {
              item = held["placements", p]
              if (jget(item, "env") != e || hostof(p) != "") continue
              drawn_p++
              print "  Container(" alias("c", p, jget(item, "container")) ", \"" lab(jget(item, "container")) "\", \"" lab(jget(item, "image")) "\", \"replicas " lab(jget(item, "replicas")) "\")" > md
            }
            print "}" > md
            for (r = 1; r <= nr; r++) {
              item = held["relationships", r]
              if (jget(item, "env") != e || !((e SUBSEP jget(item, "from")) in node_alias)) continue
              for (p = 1; p <= np; p++) {
                pit = held["placements", p]
                if (jget(pit, "env") == e && jget(pit, "container") == jget(item, "to") && hostof(p) == jget(item, "to_compute"))
                  print "Rel(" node_alias[e SUBSEP jget(item, "from")] ", " alias("c", p, jget(pit, "container")) ", \"" lab(jget(item, "label")) "\")" > md
              }
            }
            for (p = 1; p <= np; p++) {
              item = held["placements", p]
              if (jget(item, "env") != e) continue
              nnet = split(jget(item, "networks"), nets, ",")
              for (k = 1; k <= nnet; k++)
                if ((e SUBSEP nets[k]) in net_alias)
                  print "Rel(" alias("c", p, jget(item, "container")) ", " net_alias[e SUBSEP nets[k]] ", \"joins\")" > md
            }
          }
          print "@enduml" > md
          print "```" > md
          print "" > md
        } else if (dialect == "likec4") {
          print "```likec4" > md
          print "specification {" > md
          print "  element container" > md
          print "  deploymentNode environment" > md
          print "  deploymentNode node" > md
          print "}" > md
          print "model {" > md
          for (p = 1; p <= np; p++) {
            item = held["placements", p]
            if (env_filter != "" && jget(item, "env") != env_filter) continue
            print "  " alias("c", p, jget(item, "container")) " = container \047" lab(jget(item, "container")) "\047 {" > md
            print "    technology \047" lab(jget(item, "image")) "\047" > md
            print "    description \047replicas " lab(jget(item, "replicas")) "\047" > md
            print "  }" > md
          }
          print "}" > md
          print "deployment {" > md
          for (i = 1; i <= ne; i++) {
            e = env_name[i]
            if (env_filter != "" && e != env_filter) continue
            print "  " alias("env", i, e) " = environment \047" lab(e) "\047 {" > md
            for (n = 1; n <= nn; n++) {
              item = held["nodes", n]
              if (jget(item, "env") != e || jget(item, "kind") == "compute") continue
              node_alias[e SUBSEP jget(item, "id")] = alias("n", n, jget(item, "name"))
              print "    " alias("n", n, jget(item, "name")) " = node \047" lab(jget(item, "name")) "\047 \047" lab(jget(item, "kind")) " " lab(jget(item, "detail")) "\047" > md
            }
            for (n = 1; n <= nn; n++) {
              item = held["nodes", n]
              if (jget(item, "env") != e || jget(item, "kind") != "compute" || !((e SUBSEP jget(item, "id")) in hosts)) continue
              print "    " alias("cn", n, jget(item, "name")) " = node \047" lab(jget(item, "name")) "\047 \047compute " lab(jget(item, "detail")) "\047 {" > md
              for (p = 1; p <= np; p++) {
                pit = held["placements", p]
                if (jget(pit, "env") != e || hostof(p) != jget(item, "id")) continue
                drawn_p++
                cpath[p] = alias("env", i, e) "." alias("cn", n, jget(item, "name")) "." alias("c", p, jget(pit, "container"))
                print "      instanceOf " alias("c", p, jget(pit, "container")) > md
              }
              print "    }" > md
            }
            for (p = 1; p <= np; p++) {
              item = held["placements", p]
              if (jget(item, "env") != e || hostof(p) != "") continue
              drawn_p++
              cpath[p] = alias("env", i, e) "." alias("c", p, jget(item, "container"))
              print "    instanceOf " alias("c", p, jget(item, "container")) > md
            }
            print "  }" > md
            for (r = 1; r <= nr; r++) {
              item = held["relationships", r]
              if (jget(item, "env") != e || !((e SUBSEP jget(item, "from")) in node_alias)) continue
              for (p = 1; p <= np; p++) {
                pit = held["placements", p]
                if (jget(pit, "env") == e && jget(pit, "container") == jget(item, "to") && hostof(p) == jget(item, "to_compute"))
                  print "  " alias("env", i, e) "." node_alias[e SUBSEP jget(item, "from")] " -> " cpath[p] " \047" lab(jget(item, "label")) "\047" > md
              }
            }
          }
          print "}" > md
          print "views {" > md
          for (i = 1; i <= ne; i++) {
            e = env_name[i]
            if (env_filter != "" && e != env_filter) continue
            print "  deployment view " alias("view", i, e) " {" > md
            print "    title \047" lab(e) "\047" > md
            print "    include " alias("env", i, e) ".**" > md
            print "  }" > md
          }
          print "}" > md
          print "```" > md
          print "" > md
        } else {
          print "No C4 view is drawn: diagram_dialect.system is unset (no C4 view emitted). The tables here come from the record." > md
          print "" > md
          for (p = 1; p <= np; p++) {
            e = jget(held["placements", p], "env")
            if (env_filter == "" || e == env_filter) drawn_p++
          }
        }
        nc = count["catalog"] + 0
        print "## Containers" > md
        print "" > md
        if (nc == 0) {
          print "map-containers output was not present. Container names came from the IaC." > md
          print "" > md
        } else {
          print "| Name | Placed by the IaC that was read |" > md
          print "|---|---|" > md
          for (i = 1; i <= nc; i++) {
            item = held["catalog", i]
            print "| " safe(jget(item, "catalog")) " | " safe(jget(item, "placed")) " |" > md
          }
          print "" > md
        }
      }
      tools = ""
      for (i = 1; i <= nt; i++) {
        if (jget(held["tools", i], "shipped") != "yes") continue
        tools = (tools == "" ? jget(held["tools", i], "name") : tools "," jget(held["tools", i], "name"))
      }
      if (tools == "") tools = "none"
      tools = safe(tools)
      printf "deployment: status=%s reason=%s tools=%s environments=%d placements=%d diffs=%d dialect=%s\n", \
        status, (reason == "" ? "none" : reason), tools, ne, drawn_p + 0, shown_d + 0, dialect
      exit exit_code
    }
  '
)"
rc=$?
set -e
if [[ $rc -ne 0 && $rc -ne 3 ]]; then
  [[ "$target" == "$md" ]] && rm -f "$md"
  exit "$rc"
fi
printf '%s\n' "$summary"
exit "$rc"
