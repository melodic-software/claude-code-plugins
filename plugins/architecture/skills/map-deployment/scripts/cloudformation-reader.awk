# CloudFormation reader for collect-deployment.sh. Prepend redact-connection.awk
# and deployment-diff.awk, then yaml-rows.awk. Arguments are repo-relative YAML
# or JSON templates and JSON parameter files prefixed with "./". Set tool to
# cloudformation.
#
# Maps AWS::ECS::Cluster, AWS::ECS::TaskDefinition and AWS::ECS::Service. A
# template with no parameter file is one environment named for its directory
# (default at the repository root). A parameter file, the ParameterKey and
# ParameterValue array or a { "Parameters": {} } object, is one environment:
# <stem>.parameters.<env>.json or <stem>.<env>.json beside <stem>.<ext>, else
# <env>.json (or parameters.<env>.json) when the repository holds exactly one
# template. Only a Ref to a template parameter and a Sub over parameters are
# resolved, from the parameter file then the parameter Default; every other
# intrinsic is recorded as unresolved:<text>, never evaluated. A NoEcho
# parameter, a parameter whose name names a credential, a dynamic reference
# and a container secret are redacted. A
# Transform, a nested AWS::CloudFormation::Stack, and a parameter file with no
# template to pair refuse the record by file name.

BEGIN { CAP = 1; CLUSTER_NAME_PROP = "ClusterName"; SERVICE_NAME_PROP = "ServiceName" }

function resolve_param(sc, name, depth,    f, pf, r, sec) {
  f = S_file[sc]; pf = S_pf[sc]
  sec = (((f SUBSEP name) in SECP) || redact_secret_key(name))
  RES_OK = 1
  if (fld(f, "Parameters." name ".Type") && tolower(FV) ~ /^aws::ssm::parameter::value/) { r = unresolved("{Ref:" name "}"); RES_SEC = sec; return r }
  if (pf != "" && ((pf SUBSEP name) in PFV)) r = PFV[pf, name]
  else if (fld(f, "Parameters." name ".Default")) r = FV
  else { r = unresolved("{Ref:" name "}"); RES_SEC = sec; return r }
  RES_SEC = (sec || index(r, "{{resolve:") > 0)
  return r
}

function resolve_at(sc, p, depth,    f, v, nm, out, rest, i, q, inner, r, sec, ok) {
  f = S_file[sc]; RES_SEC = 0; RES_OK = 1
  if (depth > 8) return unres(f, p)
  if ((f SUBSEP p) in RV) {
    v = RV[f, p]
    if (index(v, "{{resolve:") > 0) RES_SEC = 1
    return v
  }
  if (KN[f, p] != 1) return unres(f, p)
  if ((f SUBSEP p ".Ref") in RV) {
    nm = RV[f, p ".Ref"]
    if ((f SUBSEP nm) in PDECL) return resolve_param(sc, nm, depth + 1)
    return unres(f, p)
  }
  if ((f SUBSEP p ".Fn::Sub") in RV) {
    v = RV[f, p ".Fn::Sub"]
    out = ""; rest = v; ok = 1; sec = (index(v, "{{resolve:") > 0)
    while ((i = index(rest, "${")) > 0) {
      out = out substr(rest, 1, i - 1)
      rest = substr(rest, i + 2)
      q = index(rest, "}")
      if (q == 0) { ok = 0; break }
      inner = trim(substr(rest, 1, q - 1))
      rest = substr(rest, q + 1)
      if (substr(inner, 1, 1) == "!") { out = out "${" substr(inner, 2) "}"; continue }
      if (!((f SUBSEP inner) in PDECL)) { ok = 0; break }
      r = resolve_param(sc, inner, depth + 1)
      if (RES_SEC) sec = 1
      if (!RES_OK) { ok = 0; break }
      out = out r
    }
    if (!ok) { r = unres(f, p); RES_SEC = (sec || RES_SEC); return r }
    RES_OK = 1; RES_SEC = sec
    return out rest
  }
  return unres(f, p)
}

# The logical id a Ref or GetAtt names, when it is a declared resource.
function lref(sc, p,    f, v) {
  f = S_file[sc]
  if ((f SUBSEP p ".Ref") in RV) v = RV[f, p ".Ref"]
  else if ((f SUBSEP p ".Fn::GetAtt") in RV) { v = RV[f, p ".Fn::GetAtt"]; sub(/\..*$/, "", v) }
  else if ((f SUBSEP p ".Fn::GetAtt[0]") in RV) v = RV[f, p ".Fn::GetAtt[0]"]
  else return ""
  return ((sc SUBSEP v) in KIND_OF) ? v : ""
}

function cdpath(f, pre) { return jp(pre, "ContainerDefinitions") }

function collect_res(sc,    f, n, i, R, id, t, k, m) {
  f = S_file[sc]
  n = kids(f, "Resources", R); m = 0
  for (i = 1; i <= n; i++) {
    id = KK[f, R[i]]
    if (!fld(f, R[i] ".Type")) continue
    t = FV
    if (t == "AWS::CloudFormation::Stack") fail("cloudformation-stack-unread:" f ":" id)
    k = (t == "AWS::ECS::Cluster") ? "cluster" : (t == "AWS::ECS::TaskDefinition") ? "taskdef" : (t == "AWS::ECS::Service") ? "service" : ""
    if (k == "") { note_unmapped(tool, t, f); continue }
    m++
    RID[m] = id; RKIND[m] = k; RTYPE[m] = t; RPRE[m] = R[i] ".Properties"
    KIND_OF[sc, id] = k
  }
  return m
}

function new_scope(f, env, pf) {
  NS++
  S_file[NS] = f; S_env[NS] = env; S_pf[NS] = pf
  return NS
}

function root_scope(t, env, pf) {
  add_env(env, t (pf != "" ? ", " pf : ""))
  map_ecs(new_scope(t, env, pf))
}

END {
  if (failed) exit 0
  parse_all()
  for (i = 1; i <= nfiles; i++) {
    f = files[i]
    if (has(f, "Resources") || has(f, "AWSTemplateFormatVersion")) {
      tpls[++ntpl] = f
      if (has(f, "Transform")) fail("cloudformation-transform-unread:" f)
      n = kids(f, "Parameters", ks)
      for (j = 1; j <= n; j++) {
        PDECL[f, KK[f, ks[j]]] = 1
        if (fld(f, ks[j] ".NoEcho") && tolower(FV) == "true") SECP[f, KK[f, ks[j]]] = 1
      }
      continue
    }
    pfiles[++npf] = f
    if (is_arr(f, "")) {
      n = kids(f, "", ks)
      for (j = 1; j <= n; j++) if (fld(f, ks[j] ".ParameterKey")) { k = FV; if (fld(f, ks[j] ".ParameterValue")) PFV[f, k] = FV }
    } else {
      n = kids(f, "Parameters", ks)
      for (j = 1; j <= n; j++) if (fld(f, ks[j])) PFV[f, KK[f, ks[j]]] = FV
    }
  }
  for (i = 1; i <= npf; i++) {
    f = pfiles[i]; b = base(f); d = dirof(f); t = ""; e = ""
    for (j = 1; j <= ntpl; j++) {
      stem = base(tpls[j]); sub(/\.[^.]*$/, "", stem)
      if (dirof(tpls[j]) == d && index(b, stem ".") == 1) { t = tpls[j]; e = substr(b, length(stem) + 2); break }
    }
    if (t == "") {
      if (ntpl != 1) fail("cloudformation-parameters-unpaired:" f)
      t = tpls[1]; e = b
      stem = base(t); sub(/\.[^.]*$/, "", stem)
      if (index(b, stem ".") == 1) e = substr(b, length(stem) + 2)
    }
    sub(/\.json$/, "", e)
    sub(/^(parameters|params)[.-]/, "", e)
    sub(/[.-](parameters|params)$/, "", e)
    if (e == "parameters" || e == "params") e = ""
    PT[i] = t; PFILE[i] = f; PENV[i] = (e == "" ? dir_env(f) : e)
    has_pf[t] = 1
  }
  for (i = 1; i <= ntpl; i++) {
    t = tpls[i]
    if (!has_pf[t]) { root_scope(t, dir_env(t), ""); continue }
    for (j = 1; j <= npf; j++) if (PT[j] == t) root_scope(t, PENV[j], PFILE[j])
  }
  finish()
}
