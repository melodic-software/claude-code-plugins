# Terraform reader for collect-deployment.sh. Prepend redact-connection.awk and
# deployment-diff.awk. Arguments are repo-relative .tf, .tf.json, .tfvars and
# .tfvars.json paths prefixed with "./". Set places, params, nodes, envs, diffs
# and flag to output files.
#
# One tokenizer reads native HCL and the JSON syntax alike into flat rows of
# path, kind, value. Kinds: s a string (it may hold ${} interpolations), l a
# number or bool, x a traversal such as var.name, u anything else. A string that
# is one whole interpolation, and a heredoc or container_definitions string
# holding JSON, is read as the expression inside it. jsonencode() is read
# through; every other function, operator, for-expression, conditional, local
# and dynamic block is recorded as unresolved:<text>, never evaluated.
#
# A root is a directory of configuration that no local module source names.
# Its environments are the <env> of an envs/<env>/ or environments/<env>/ path,
# else one per <env>.tfvars beside or above it, else the directory name
# (default at the repository root). var.X resolves from a module call argument,
# then the root's tfvars files, then the variable default. A remote module
# source, or a local one with no configuration, refuses the record as
# terraform-module-unread:<file>:module.<name>; the source is never printed.

function trim(s) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
function jesc(s) { if (redact_secret_value(s)) s = "[redacted]"; gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
function dirof(p) { if (sub(/\/[^\/]*$/, "", p)) return p; return "." }
function base(p) { sub(/.*\//, "", p); return p }
function fail(reason) { print reason > flag; failed = 1; exit 0 }

function tok(t, v) { NT++; T[NT] = t; V[NT] = v }

# Tokens: s string, n identifier or number or traversal, p punctuation, nl newline.
function tokenize(f, s,    L, i, c, c2, j, out, depth, ch, nx, inner, rest, tag, body, m, e, line, pk) {
  NT = 0
  L = length(s)
  i = 1
  while (i <= L) {
    c = substr(s, i, 1)
    c2 = substr(s, i, 2)
    if (c == " " || c == "\t" || c == "\r") { i++; continue }
    if (c == "\n") { tok("nl", ""); i++; continue }
    if (c == "#" || c2 == "//") { while (i <= L && substr(s, i, 1) != "\n") i++; continue }
    if (c2 == "/*") {
      j = index(substr(s, i + 2), "*/")
      if (j == 0) return 0
      i += j + 3
      continue
    }
    if (c == "\"") {
      out = ""; depth = 0; j = i + 1
      while (1) {
        if (j > L) return 0
        ch = substr(s, j, 1)
        if (ch == "\n" && depth == 0) return 0
        if (ch == "\\") {
          nx = substr(s, j + 1, 1)
          if (nx == "\"" || nx == "\\") out = out nx
          else if (nx == "n" || nx == "t" || nx == "r") out = out " "
          else out = out "\\" nx
          j += 2
          continue
        }
        if (ch == "$" && substr(s, j + 1, 1) == "{") { depth++; out = out "${"; j += 2; continue }
        if (depth > 0 && ch == "{") depth++
        else if (depth > 0 && ch == "}") depth--
        else if (ch == "\"" && depth == 0) break
        out = out ch
        j++
      }
      pk =(NT >= 2 && T[NT] == "p" && (V[NT] == "=" || V[NT] == ":")) ? V[NT - 1] : ""
      inner = ""
      if (f ~ /\.json$/ && substr(out, 1, 2) == "${" && substr(out, length(out)) == "}" && index(substr(out, 3), "${") == 0)
        inner = substr(out, 3, length(out) - 3)
      else if (pk == "container_definitions" && trim(out) ~ /^[\[{]/)
        inner = out
      if (inner != "") { s = substr(s, 1, i - 1) " " inner " " substr(s, j + 1); L = length(s); continue }
      tok("s", out)
      i = j + 1
      continue
    }
    if (c2 == "<<" && match(substr(s, i), /^<<-?[A-Za-z_][A-Za-z0-9_]*[ \t\r]*\n/)) {
      tag = substr(s, i, RLENGTH)
      sub(/^<<-?/, "", tag)
      tag = trim(tag)
      j = i + RLENGTH
      body = ""
      e = 0
      while (j <= L) {
        m = index(substr(s, j), "\n")
        line = (m == 0) ? substr(s, j) : substr(s, j, m - 1)
        j = (m == 0) ? L + 1 : j + m
        if (trim(line) == tag) { e = 1; break }
        body = body line "\n"
      }
      if (!e) return 0
      if (trim(body) ~ /^[\[{]/) { s = substr(s, 1, i - 1) " " body " " substr(s, j); L = length(s); continue }
      gsub(/\n/, " ", body)
      tok("s", trim(body))
      i = j
      continue
    }
    if (c ~ /[A-Za-z0-9_]/) {
      j = i
      while (j <= L) {
        ch = substr(s, j, 1)
        if (ch ~ /[A-Za-z0-9_.*-]/) { j++; continue }
        if (ch == "[") {
          m = index(substr(s, j), "]")
          if (m == 0) return 0
          j += m
          continue
        }
        break
      }
      tok("n", substr(s, i, j - i))
      i = j
      continue
    }
    if ((c == "=" && (substr(s, i + 1, 1) == "=" || substr(s, i + 1, 1) == ">")) || ((c == "!" || c == "<" || c == ">") && substr(s, i + 1, 1) == "=")) {
      tok("p", "op " c2); i += 2; continue
    }
    if (index("{}[]()=,:", c) > 0) { tok("p", c); i++; continue }
    tok("p", "op " c)
    i++
  }
  tok("EOF", "")
  return 1
}

function row(path, kind, value) {
  NR_++
  RF[NR_] = FILE_; RP[NR_] = path; RK[NR_] = kind; RV[NR_] = value
}

function skip_sep() { while (T[P] == "nl" || (T[P] == "p" && V[P] == ",")) P++ }
function is_p(k, v) { return T[k] == "p" && V[k] == v }

function parse_body(prefix, closer,    key, path, k) {
  while (!bad) {
    skip_sep()
    if (T[P] == "EOF") { if (closer != "") bad = 1; return }
    if (is_p(P, closer)) { P++; return }
    if (T[P] != "s" && T[P] != "n") { bad = 1; return }
    key = V[P]
    P++
    if (is_p(P, "=") || is_p(P, ":")) { P++; parse_expr(prefix key); continue }
    path = prefix key
    while (T[P] == "s" || T[P] == "n") { path = path "." V[P]; P++ }
    if (!is_p(P, "{")) { bad = 1; return }
    P++
    if (prefix != "") { k = occ[FILE_, path]++; path = path "[" k "]" }
    parse_body(path ".", "}")
  }
}

# The expression runs to a newline, comma, or unmatched closer at depth 0.
function parse_expr(path,    E, d, first, k, raw, t, n) {
  d = 0; first = 0; E = P
  while (T[E] != "EOF") {
    if (T[E] == "p" && (V[E] == "{" || V[E] == "[" || V[E] == "(")) d++
    else if (T[E] == "p" && (V[E] == "}" || V[E] == "]" || V[E] == ")")) {
      if (d == 0) break
      d--
      if (d == 0 && first == 0) first = E
    } else if (d == 0 && (T[E] == "nl" || is_p(E, ","))) break
    E++
  }
  if (d != 0 || E == P) { bad = 1; return }
  if (E == P + 1 && T[P] == "s") { row(path, "s", V[P]); P = E; return }
  if (E == P + 1 && T[P] == "n") {
    row(path, (V[P] ~ /^-?[0-9.]+$/ || V[P] ~ /^(true|false|null)$/) ? "l" : "x", V[P])
    P = E
    return
  }
  k = P + 1
  while (T[k] == "nl") k++
  if (first == E - 1 && is_p(P, "[") && !(T[k] == "n" && V[k] == "for")) {
    P++; n = 0
    while (!bad) {
      skip_sep()
      if (is_p(P, "]")) { P++; return }
      if (T[P] == "EOF") { bad = 1; return }
      parse_expr(path "[" n++ "]")
    }
    return
  }
  if (first == E - 1 && is_p(P, "{") && !(T[k] == "n" && V[k] == "for")) { P++; parse_body(path ".", "}"); return }
  if (first == E - 1 && T[P] == "n" && V[P] ~ /^(jsonencode|tolist|toset)$/ && is_p(P + 1, "(")) {
    P += 2
    skip_sep()
    parse_expr(path)
    skip_sep()
    if (!is_p(P, ")")) { bad = 1; return }
    P++
    return
  }
  raw = ""
  for (t = P; t < E; t++) {
    if (T[t] == "nl") continue
    raw = raw (raw == "" ? "" : " ") (T[t] == "s" ? "\"" V[t] "\"" : (T[t] == "p" ? substr(V[t], index(V[t], " ") + 1) : V[t]))
  }
  row(path, "u", raw)
  P = E
}

function parse_file(f, s) {
  FILE_ = f
  bad = 0
  if (!tokenize(f, s)) fail("terraform-unreadable:" f)
  P = 1
  while (T[P] == "nl") P++
  if (f ~ /\.json$/) {
    if (!is_p(P, "{")) fail("terraform-unreadable:" f)
    P++
    parse_body("", "}")
  } else parse_body("", "")
  if (bad) fail("terraform-unreadable:" f)
}

BEGIN { NR_ = 0; nfiles = 0 }
{
  if (FNR == 1) {
    f = FILENAME
    sub(/^\.\//, "", f)
    files[++nfiles] = f
  }
  src[f] = src[f] $0 "\n"
}

# Lookups over the rows of one directory.
function field(d, pre, name,    k, r, rest) {
  for (k = 1; k <= DN[d]; k++) {
    r = DR[d, k]
    if (index(RP[r], pre) != 1) continue
    rest = substr(RP[r], length(pre) + 1)
    gsub(/\[[0-9]+\]/, "", rest)
    if (rest == name) { FK = RK[r]; FV = RV[r]; FF = RF[r]; return 1 }
  }
  FK = ""; FV = ""; FF = ""
  return 0
}
function has_under(d, pre, re,    k, r) {
  for (k = 1; k <= DN[d]; k++) {
    r = DR[d, k]
    if (index(RP[r], pre) == 1 && substr(RP[r], length(pre) + 1) ~ re) return 1
  }
  return 0
}
# Distinct group prefixes under pre whose remainder starts with re, in file order.
function groups(d, pre, re, out,    k, r, rest, g, n, seen) {
  n = 0
  for (k = 1; k <= DN[d]; k++) {
    r = DR[d, k]
    if (index(RP[r], pre) != 1) continue
    rest = substr(RP[r], length(pre) + 1)
    if (!match(rest, re)) continue
    g = pre substr(rest, 1, RLENGTH)
    if (!(g in seen)) { seen[g] = 1; out[++n] = g }
  }
  return n
}

function unresolved(raw) { RES_OK = 0; return "unresolved:" raw }

# Resolve one value in scope sc. Sets RES_OK and RES_SEC.
function resolve(sc, kind, v, depth,    out, rest, p, q, inner, r, ok, sec) {
  RES_SEC = 0
  RES_OK = 1
  if (depth > 8) return unresolved(v)
  if (kind == "l") return v
  if (kind == "u") return unresolved(v)
  if (kind == "x") {
    if (v ~ /^var\.[A-Za-z0-9_-]+$/) return resolve_var(sc, substr(v, 5), depth + 1)
    return unresolved(v)
  }
  if (index(v, "%{") > 0) return unresolved(v)
  out = ""; rest = v; ok = 1; sec = 0
  while ((p = index(rest, "${")) > 0) {
    out = out substr(rest, 1, p - 1)
    rest = substr(rest, p + 2)
    q = index(rest, "}")
    if (q == 0) return unresolved(v)
    inner = trim(substr(rest, 1, q - 1))
    r = resolve(sc, "x", inner, depth + 1)
    if (RES_SEC) sec = 1
    if (!RES_OK) { ok = 0; break }
    out = out r
    rest = substr(rest, q + 1)
  }
  if (!ok) { r = unresolved(v); RES_SEC = sec; return r }
  RES_OK = 1
  RES_SEC = sec
  return out rest
}

function resolve_var(sc, name, depth,    d, cd, key, i, f, r, sec) {
  d = S_dir[sc]
  sec = (field(d, "variable." name ".", "sensitive") && FV == "true")
  if (S_caller[sc] != "") {
    cd = S_dir[S_caller[sc]]
    if (field(cd, S_argpre[sc], name)) { r = resolve(S_caller[sc], FK, FV, depth + 1); if (sec) RES_SEC = 1; return r }
  } else {
    for (i = S_tfn[sc]; i >= 1; i--) {
      f = S_tff[sc, i]
      if ((f SUBSEP name) in TVK) { r = resolve(sc, TVK[f, name], TVV[f, name], depth + 1); if (sec) RES_SEC = 1; return r }
    }
  }
  if (field(d, "variable." name ".", "default")) { r = resolve(sc, FK, FV, depth + 1); if (sec) RES_SEC = 1; return r }
  r = unresolved("var." name)
  RES_SEC = sec
  return r
}

# The name of the <rtype> resource a value references, or "".
function ref(kind, v, rtype) {
  if (kind == "s" && v ~ /^\$\{[^}]*\}$/) { v = trim(substr(v, 3, length(v) - 3)); kind = "x" }
  if (kind != "x" || index(v, rtype ".") != 1) return ""
  v = substr(v, length(rtype) + 2)
  sub(/[.\[].*$/, "", v)
  return v
}

# get() for a field printed as is: a value from a sensitive variable prints as [redacted].
function show(sc, pre, name, dflt,    v) {
  v = get(sc, pre, name, dflt)
  return RES_SEC ? "[redacted]" : v
}

function get(sc, pre, name, dflt) {
  if (!field(S_dir[sc], pre, name)) { RES_OK = 1; RES_SEC = 0; return dflt }
  return resolve(sc, FK, FV, 0)
}

function node(sc, id, type, name, ev) {
  printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"terraform\",\"kind\":\"compute\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
    jesc(id), jesc(S_env[sc]), jesc(name), jesc(type), jesc(ev) >> nodes
}

function param(sc, c, k, v, sec, ev,    e, red, pk) {
  e = S_env[sc]
  red = (sec || redact_secret(k, v)) ? "yes" : "no"
  printf "{\"parameter\":\"%s\",\"env\":\"%s\",\"tool\":\"terraform\",\"container\":\"%s\",\"value\":\"%s\",\"redacted\":\"%s\",\"evidence\":\"%s\"}\n", \
    jesc(k), jesc(e), jesc(c), jesc(red == "yes" ? "" : v), red, jesc(ev) >> params
  pk = e SUBSEP c SUBSEP k
  param_seen[pk] = 1
  if (red == "yes") secret_val[pk] = v
  else plain_val[pk] = v
}

function place(sc, c, img, reps, ports, compute, ev,    e) {
  e = S_env[sc]
  printf "{\"container\":\"%s\",\"env\":\"%s\",\"tool\":\"terraform\",\"node\":\"%s\",\"compute\":\"%s\",\"image\":\"%s\",\"replicas\":\"%s\",\"ports\":\"%s\",\"networks\":\"\",\"evidence\":\"%s\"}\n", \
    jesc(c), jesc(e), jesc(compute != "" ? compute : e), jesc(compute), jesc(img), jesc(reps), jesc(ports), jesc(ev) >> places
  placed[e SUBSEP c] = 1
  image[e SUBSEP c] = img
  replica_of[e SUBSEP c] = reps
  if (ports != "") portjoin[e SUBSEP c] = ports
}

# One container block: name, image, ports, and env entries. An env entry that
# holds a secret reference instead of a value is a redacted parameter.
function container(sc, g, dflt, reps, compute, ports, envre, secre, portre, portkey, ev,    d, c, img, n, i, pg, eg, k, v, pv, sec) {
  d = S_dir[sc]
  c = show(sc, g, "name", dflt)
  img = show(sc, g, "image", "")
  n = groups(d, g, portre, pg)
  for (i = 1; i <= n; i++) if (field(d, pg[i], portkey)) { pv = resolve(sc, FK, FV, 0); if (RES_SEC) pv = "[redacted]"; ports = (ports == "" ? pv : ports "," pv) }
  place(sc, c, img, reps, ports, compute, ev)
  n = groups(d, g, envre, eg)
  for (i = 1; i <= n; i++) {
    k = show(sc, eg[i], "name", "")
    if (k == "") continue
    if (has_under(d, eg[i], secre)) { param(sc, c, k, "reference", 1, ev); continue }
    v = get(sc, eg[i], "value", "")
    sec = RES_SEC
    param(sc, c, k, v, sec, ev)
  }
}

function compute_id(sc, type, name) { return S_env[sc] "/" S_prefix[sc] type "." name }

function map_scope(sc,    d, k, r, parts, type, name, pre, id, n, i, gs, cl, td, reps, ports, svc, key) {
  d = S_dir[sc]
  for (k = 1; k <= DN[d]; k++) {
    r = DR[d, k]
    if (RP[r] !~ /^resource\.[^.]+\.[^.]+\./) continue
    split(RP[r], parts, ".")
    key = parts[2] "." parts[3]
    if ((sc SUBSEP key) in done) continue
    done[sc, key] = 1
    res_list[sc, ++res_n[sc]] = key
    res_file[sc, key] = RF[r]
  }
  # Services name the task definition and cluster an ECS container runs with.
  for (i = 1; i <= res_n[sc]; i++) {
    split(res_list[sc, i], parts, ".")
    if (parts[1] != "aws_ecs_service") continue
    pre = "resource.aws_ecs_service." parts[2] "."
    td = field(d, pre, "task_definition") ? ref(FK, FV, "aws_ecs_task_definition") : ""
    cl = field(d, pre, "cluster") ? ref(FK, FV, "aws_ecs_cluster") : ""
    cl = ((sc SUBSEP "aws_ecs_cluster." cl) in done) ? compute_id(sc, "aws_ecs_cluster", cl) : ""
    reps = show(sc, pre, "desired_count", "undeclared")
    if (td != "" && (sc SUBSEP "aws_ecs_task_definition." td) in done) {
      if (!((sc SUBSEP td) in svc_cl)) { svc_cl[sc, td] = cl; svc_reps[sc, td] = reps }
    } else {
      td = field(d, pre, "task_definition") ? unresolved(FV) : ""
      place(sc, show(sc, pre, "name", parts[2]), td, reps, "", cl, res_file[sc, res_list[sc, i]])
    }
  }
  for (i = 1; i <= res_n[sc]; i++) {
    key = res_list[sc, i]
    split(key, parts, ".")
    type = parts[1]; name = parts[2]
    pre = "resource." key "."
    if (type ~ /^(aws_ecs_cluster|aws_eks_cluster|azurerm_container_app_environment|azurerm_kubernetes_cluster|google_container_cluster)$/) {
      node(sc, compute_id(sc, type, name), type, show(sc, pre, "name", name), res_file[sc, key])
    } else if (type == "aws_ecs_task_definition") {
      reps = ((sc SUBSEP name) in svc_reps) ? svc_reps[sc, name] : "undeclared"
      cl = ((sc SUBSEP name) in svc_cl) ? svc_cl[sc, name] : ""
      n = groups(d, pre, "^container_definitions\\[[0-9]+\\]\\.", gs)
      if (n == 0 && field(d, pre, "container_definitions")) place(sc, name, resolve(sc, FK, FV, 0), reps, "", cl, res_file[sc, key])
      for (k = 1; k <= n; k++)
        container(sc, gs[k], name, reps, cl, "", "^(environment|secrets)\\[[0-9]+\\]\\.", "^valueFrom$", "^portMappings\\[[0-9]+\\]\\.", "containerPort", res_file[sc, key])
    } else if (type == "azurerm_container_app") {
      cl = field(d, pre, "container_app_environment_id") ? ref(FK, FV, "azurerm_container_app_environment") : ""
      cl = ((sc SUBSEP "azurerm_container_app_environment." cl) in done) ? compute_id(sc, "azurerm_container_app_environment", cl) : ""
      reps = show(sc, pre, "template.min_replicas", "undeclared")
      ports = show(sc, pre, "ingress.target_port", "")
      n = groups(d, pre, "^template(\\[[0-9]+\\])?\\.container(\\[[0-9]+\\])?\\.", gs)
      for (k = 1; k <= n; k++)
        container(sc, gs[k], name, reps, cl, ports, "^env(\\[[0-9]+\\])?\\.", "^secret_name$", "^$", "", res_file[sc, key])
    } else if (type == "google_cloud_run_v2_service") {
      reps = show(sc, pre, "template.scaling.min_instance_count", "undeclared")
      n = groups(d, pre, "^template(\\[[0-9]+\\])?\\.containers(\\[[0-9]+\\])?\\.", gs)
      for (k = 1; k <= n; k++)
        container(sc, gs[k], name, reps, "", "", "^env(\\[[0-9]+\\])?\\.", "^value_source", "^ports(\\[[0-9]+\\])?\\.", "container_port", res_file[sc, key])
    } else if (type ~ /^kubernetes_(deployment|stateful_set|daemonset|daemon_set)(_v1)?$/) {
      id = compute_id(sc, type, name)
      node(sc, id, type, show(sc, pre, "metadata.name", name), res_file[sc, key])
      reps = show(sc, pre, "spec.replicas", "undeclared")
      n = groups(d, pre, "^spec(\\[[0-9]+\\])?\\.template(\\[[0-9]+\\])?\\.spec(\\[[0-9]+\\])?\\.container(\\[[0-9]+\\])?\\.", gs)
      for (k = 1; k <= n; k++)
        container(sc, gs[k], name, reps, id, "", "^env(\\[[0-9]+\\])?\\.", "^value_from", "^port(\\[[0-9]+\\])?\\.", "container_port", res_file[sc, key])
    }
  }
}

function new_scope(d, env, caller, argpre, prefix) {
  NS++
  S_dir[NS] = d; S_env[NS] = env; S_caller[NS] = caller; S_argpre[NS] = argpre; S_prefix[NS] = prefix
  return NS
}

function instantiate(sc, depth,    d, i, m, c) {
  if (depth > 10) fail("terraform-module-unread:" MF[S_dir[sc], 1] ":module-depth")
  map_scope(sc)
  d = S_dir[sc]
  for (i = 1; i <= MN[d]; i++) {
    m = MNAME[d, i]
    c = new_scope(MTARGET[d, i], S_env[sc], sc, "module." m ".", S_prefix[sc] "module." m ".")
    instantiate(c, depth + 1)
  }
}

function add_env(e, ev) {
  if (!(e in env_seen)) { env_seen[e] = 1; env_list[++env_n] = e; env_ev[e] = ev }
  else if (index(", " env_ev[e] ", ", ", " ev ", ") == 0) env_ev[e] = env_ev[e] ", " ev
}

# Lowest precedence first: terraform.tfvars, terraform.tfvars.json, *.auto.tfvars in
# lexical order, then the environment's own file.
function root_scope(r, env, named,    sc, i, n, pass, b) {
  sc = new_scope(r, env, "", "", "")
  n = 0
  for (pass = 1; pass <= 3; pass++)
    for (i = 1; i <= nfiles; i++) {
      if (TVROOT[files[i]] != r || !TVAUTO[files[i]]) continue
      b = base(files[i])
      if ((pass == 1 && b == "terraform.tfvars") || (pass == 2 && b == "terraform.tfvars.json") || (pass == 3 && b !~ /^terraform\.tfvars/))
        S_tff[sc, ++n] = files[i]
    }
  if (named != "") S_tff[sc, ++n] = named
  S_tfn[sc] = n
  add_env(env, RFILES[r] (named != "" ? ", " named : ""))
  instantiate(sc, 0)
}

END {
  if (failed) exit 0
  for (i = 1; i <= nfiles; i++) {
    f = files[i]
    parse_file(f, src[f])
  }
  for (r = 1; r <= NR_; r++) {
    d = dirof(RF[r])
    if (RF[r] ~ /\.tfvars(\.json)?$/) {
      if (RP[r] !~ /[.\[]/) { TVK[RF[r], RP[r]] = RK[r]; TVV[RF[r], RP[r]] = RV[r] }
      continue
    }
    DR[d, ++DN[d]] = r
  }
  for (i = 1; i <= nfiles; i++) {
    f = files[i]
    if (f ~ /\.tfvars(\.json)?$/) continue
    d = dirof(f)
    if (!(d in cfg)) { cfg[d] = 1; dirs[++ndirs] = d; RFILES[d] = f } else RFILES[d] = RFILES[d] ", " f
  }
  # Module calls: a local source joins its directory to the caller; anything else is unread.
  for (i = 1; i <= ndirs; i++) {
    d = dirs[i]
    for (k = 1; k <= DN[d]; k++) {
      r = DR[d, k]
      if (RP[r] !~ /^module\.[^.]+\.source$/) continue
      split(RP[r], parts, ".")
      if (RK[r] != "s" || RV[r] !~ /^\.\.?(\/|$)/) fail("terraform-module-unread:" RF[r] ":module." parts[2])
      t = (d == "." ? RV[r] : d "/" RV[r])
      nseg = split(t, seg, "/"); out = ""; depth = 0
      for (j = 1; j <= nseg; j++) {
        if (seg[j] == "" || seg[j] == ".") continue
        if (seg[j] == "..") {
          if (depth == 0) fail("terraform-module-unread:" RF[r] ":module." parts[2])
          sub(/\/?[^\/]*$/, "", out); depth--; continue
        }
        out = (out == "" ? seg[j] : out "/" seg[j]); depth++
      }
      if (out == "") out = "."
      if (!(out in cfg)) fail("terraform-module-unread:" RF[r] ":module." parts[2])
      MN[d]++
      MNAME[d, MN[d]] = parts[2]
      MTARGET[d, MN[d]] = out
      MF[d, MN[d]] = RF[r]
      is_mod[out] = 1
    }
  }
  # Each tfvars file belongs to the nearest root at or above it.
  for (i = 1; i <= nfiles; i++) {
    f = files[i]
    if (f !~ /\.tfvars(\.json)?$/) continue
    d = dirof(f)
    while (!((d in cfg) && !(d in is_mod))) {
      if (d == ".") fail("terraform-orphan-tfvars:" f)
      d = dirof(d)
    }
    TVROOT[f] = d
    TVAUTO[f] = (base(f) ~ /^terraform\.tfvars(\.json)?$/ || base(f) ~ /\.auto\.tfvars(\.json)?$/)
  }
  for (i = 1; i <= ndirs; i++) {
    r = dirs[i]
    if (r in is_mod) continue
    if (match(r, /(^|\/)(envs|environments)\/[^\/]+/)) {
      e = substr(r, RSTART, RLENGTH)
      sub(/.*\//, "", e)
      named = ""
      for (j = 1; j <= nfiles; j++) if (TVROOT[files[j]] == r && !TVAUTO[files[j]]) named = files[j]
      root_scope(r, e, named)
      continue
    }
    nnamed = 0
    for (j = 1; j <= nfiles; j++) {
      f = files[j]
      if (TVROOT[f] != r || TVAUTO[f]) continue
      e = base(f)
      sub(/\.tfvars(\.json)?$/, "", e)
      root_scope(r, e, f)
      nnamed++
    }
    if (nnamed == 0) root_scope(r, (r == "." ? "default" : base(r)), "")
  }
  for (i = 1; i <= env_n; i++)
    printf "{\"environment\":\"%s\",\"tool\":\"terraform\",\"evidence\":\"%s\"}\n", jesc(env_list[i]), jesc(env_ev[env_list[i]]) >> envs
  for (i = 1; i <= env_n; i++) for (j = i + 1; j <= env_n; j++) {
    a = env_list[i]; b = env_list[j]
    if (a > b) { t = a; a = b; b = t }
    container_diffs(a, b, "terraform")
    param_port_diffs(a, b, "terraform")
  }
}
