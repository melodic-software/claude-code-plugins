# Pulumi YAML reader for collect-deployment.sh. Prepend redact-connection.awk
# and deployment-diff.awk, then yaml-rows.awk. Arguments are repo-relative
# Pulumi.yaml files of runtime yaml and Pulumi.<stack>.yaml files prefixed with
# "./". Set tool to pulumi-yaml.
#
# Maps aws:ecs:Cluster, aws:ecs:TaskDefinition and aws:ecs:Service, with the
# aws:ecs/<type>:<Type> form accepted. The environments of a project are its
# Pulumi.<stack>.yaml files beside it, else its directory name (default at the
# repository root). ${pulumi.stack} and ${pulumi.project} resolve. A config
# key resolves from the stack file (<project>:<key>, or <key>), then the
# project's config default; ${resource.attr} links a service to its cluster and
# task definition. Everything else, fn::join, variables, invokes, is recorded
# as unresolved:<text>, never evaluated. A secret: true config key, a secure:
# stack value and fn::secret are redacted. A stack file with no project beside
# it is not read.

BEGIN { CAP = 0; PN_CLUSTER = "name"; PN_SERVICE = "name" }

function cfg_secret(f, name) { return fld(f, "config." name ".secret") && tolower(FV) == "true" }

function resolve_cfg(sc, name,    f, sf, sec, keys, i, p, r) {
  f = S_file[sc]; sf = S_sf[sc]
  sec = cfg_secret(f, name)
  RES_OK = 1
  if (sf != "") {
    keys[1] = S_proj[sc] ":" name; keys[2] = name
    for (i = 1; i <= 2; i++) {
      p = "config." keys[i]
      if ((sf SUBSEP p ".secure") in RV) { RES_SEC = 1; return RV[sf, p ".secure"] }
      if ((sf SUBSEP p) in RV) { RES_SEC = sec; return RV[sf, p] }
      if ((sf SUBSEP p) in KTY) { r = unres(sf, p); RES_SEC = (sec || RES_SEC); return r }
    }
  }
  if (fld(f, "config." name ".default") || fld(f, "config." name)) { RES_SEC = sec; return FV }
  r = unresolved("${" name "}")
  RES_SEC = sec
  return r
}

function cfg_known(sc, name,    f, sf) {
  f = S_file[sc]; sf = S_sf[sc]
  if (has(f, "config." name)) return 1
  return sf != "" && (has(sf, "config." S_proj[sc] ":" name) || has(sf, "config." name))
}

function resolve_at(sc, p, depth,    f, v, out, rest, i, q, inner, r, sec, ok) {
  f = S_file[sc]; RES_SEC = 0; RES_OK = 1
  if (depth > 8) return unres(f, p)
  if ((f SUBSEP p) in RV) {
    v = RV[f, p]
    if (index(v, "${") == 0) return v
    out = ""; rest = v; ok = 1; sec = 0
    while ((i = index(rest, "${")) > 0) {
      out = out substr(rest, 1, i - 1)
      rest = substr(rest, i + 2)
      q = index(rest, "}")
      if (q == 0) { ok = 0; break }
      inner = trim(substr(rest, 1, q - 1))
      rest = substr(rest, q + 1)
      if (inner == "pulumi.stack" && S_stack[sc] != "") r = S_stack[sc]
      else if (inner == "pulumi.project" && S_proj[sc] != "") r = S_proj[sc]
      else if (cfg_known(sc, inner)) { r = resolve_cfg(sc, inner); if (RES_SEC) sec = 1; if (!RES_OK) { ok = 0; break } }
      else { ok = 0; break }
      out = out r
    }
    if (!ok) { r = unres(f, p); RES_SEC = (sec || RES_SEC); return r }
    RES_OK = 1; RES_SEC = sec
    return out rest
  }
  if (KN[f, p] == 1 && has(f, p ".fn::secret")) {
    r = resolve_at(sc, p ".fn::secret", depth + 1)
    RES_SEC = 1
    return r
  }
  return unres(f, p)
}

# The resource id a ${id} or ${id.attr} value names, when it is declared.
function lref(sc, p,    f, v) {
  f = S_file[sc]
  if (!fld(f, p) || FV !~ /^\$\{[^.}]+(\.[^}]*)?\}$/) return ""
  v = substr(FV, 3, length(FV) - 3)
  sub(/\..*$/, "", v)
  return ((sc SUBSEP v) in KIND_OF) ? v : ""
}

function cdpath(f, pre,    p) {
  p = jp(pre, "containerDefinitions")
  return has(f, p ".fn::toJSON") ? p ".fn::toJSON" : p
}

function collect_res(sc,    f, n, i, R, id, t, k, m, tp) {
  f = S_file[sc]
  n = kids(f, "resources", R); m = 0
  for (i = 1; i <= n; i++) {
    id = KK[f, R[i]]
    if (!fld(f, R[i] ".type")) continue
    t = FV
    if (split(t, tp, ":") != 3 || tolower(tp[1]) != "aws" || tolower(tp[2]) !~ /^ecs(\/.*)?$/) continue
    k = (tolower(tp[3]) == "cluster") ? "cluster" : (tolower(tp[3]) == "taskdefinition") ? "taskdef" : (tolower(tp[3]) == "service") ? "service" : ""
    if (k == "") continue
    m++
    RID[m] = id; RKIND[m] = k; RTYPE[m] = t; RPRE[m] = R[i] ".properties"
    KIND_OF[sc, id] = k
  }
  return m
}

function new_scope(f, env, sf, stack, proj) {
  NS++
  S_file[NS] = f; S_env[NS] = env; S_sf[NS] = sf; S_stack[NS] = stack; S_proj[NS] = proj
  return NS
}

function root_scope(t, env, sf, stack, proj) {
  add_env(env, t (sf != "" ? ", " sf : ""))
  map_ecs(new_scope(t, env, sf, stack, proj))
}

END {
  if (failed) exit 0
  parse_all()
  for (i = 1; i <= nfiles; i++) if (base(files[i]) ~ /^Pulumi\.ya?ml$/) projects[++nproj] = files[i]
  for (i = 1; i <= nproj; i++) {
    t = projects[i]; d = dirof(t)
    proj = fld(t, "name") ? FV : ""
    nst = 0
    for (j = 1; j <= nfiles; j++) {
      s = files[j]
      if (dirof(s) != d || base(s) ~ /^Pulumi\.ya?ml$/ || base(s) !~ /^Pulumi\..+\.ya?ml$/) continue
      st = base(s); sub(/^Pulumi\./, "", st); sub(/\.ya?ml$/, "", st)
      root_scope(t, st, s, st, proj)
      nst++
    }
    if (nst == 0) root_scope(t, dir_env(t), "", "", proj)
  }
  finish()
}
