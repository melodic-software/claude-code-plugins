# Bicep and ARM template reader for collect-deployment.sh. Prepend
# redact-connection.awk and deployment-diff.awk. Arguments are repo-relative
# .bicep, .bicepparam, and ARM .json paths (templates and deploymentParameters
# files) prefixed with "./". Set tool (bicep or arm: which roots this run draws),
# places, params, nodes, envs, diffs and flag to output files.
#
# One tokenizer reads Bicep and JSON into flat rows of path, kind, value. Kinds:
# s a string (a Bicep string may hold ${} interpolations, an ARM string may be a
# [ ] expression), l a number, bool or null, x an identifier or property access,
# u anything else. Only a parameter reference is resolved; every function, var,
# operator and conditional is recorded as unresolved:<text>, never evaluated.
#
# A root is a template that no module names, or one a parameters file names.
# Its environments come from its .bicepparam files (the using target) and its
# JSON parameters files (<name>.parameters.<env>.json beside <name>.bicep or
# <name>.json, or parameters.<env>.json beside the directory's only template),
# else the directory name (default at the repository root). A parameter
# resolves from a module call argument, then the environment's parameters file,
# then its default. A registry or template-spec module, a module file that is
# not tracked, a nested Microsoft.Resources/deployments resource, a using or
# extends this reader does not follow, and an unpaired parameters file each
# refuse the record by file name; a module source is never printed.

function trim(s) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
function jesc(s) { if (redact_secret_value(s)) s = "[redacted]"; gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
function dirof(p) { if (sub(/\/[^\/]*$/, "", p)) return p; return "." }
function base(p) { sub(/.*\//, "", p); return p }
function tp(f) { return f ~ /\.json$/ ? "arm" : "bicep" }
function fail(reason) { print reason > flag; failed = 1; exit 0 }
function tok(t, v) { NT++; T[NT] = t; V[NT] = v }

# Tokens: s string, n identifier or number, p punctuation, nl newline.
function tokenize(f, s,    L, i, c, c2, j, out, depth, ch, nx, m) {
  NT = 0
  L = length(s)
  i = 1
  while (i <= L) {
    c = substr(s, i, 1)
    c2 = substr(s, i, 2)
    if (c == " " || c == "\t" || c == "\r") { i++; continue }
    if (c == "\n") { tok("nl", ""); i++; continue }
    if (c2 == "//" || c == "#") { while (i <= L && substr(s, i, 1) != "\n") i++; continue }
    if (c2 == "/*") {
      j = index(substr(s, i + 2), "*/")
      if (j == 0) return 0
      i += j + 3
      continue
    }
    if (substr(s, i, 3) == "'''") {
      j = index(substr(s, i + 3), "'''")
      if (j == 0) return 0
      out = substr(s, i + 3, j - 1)
      gsub(/[\r\n]+/, " ", out)
      tok("s", out)
      i += j + 5
      continue
    }
    if (c == "'" || c == "\"") {
      out = ""; depth = 0; j = i + 1
      while (1) {
        if (j > L) return 0
        ch = substr(s, j, 1)
        if (ch == "\n") return 0
        if (depth == 0 && ch == "\\") {
          nx = substr(s, j + 1, 1)
          if (nx == c || nx == "\\" || nx == "/" || nx == "$") out = out nx
          else if (nx == "n" || nx == "t" || nx == "r") out = out " "
          else out = out "\\" nx
          j += 2
          continue
        }
        if (depth == 0 && ch == c) break
        if (c == "'" && depth == 0 && ch == "$" && substr(s, j + 1, 1) == "{") { depth = 1; out = out "${"; j += 2; continue }
        if (depth > 0 && ch == "'") {
          m = index(substr(s, j + 1), "'")
          if (m == 0) return 0
          out = out substr(s, j, m + 1)
          j += m + 1
          continue
        }
        if (depth > 0 && ch == "{") depth++
        else if (depth > 0 && ch == "}") depth--
        out = out ch
        j++
      }
      tok("s", out)
      i = j + 1
      continue
    }
    if (c ~ /[A-Za-z0-9_$]/ || (c == "-" && substr(s, i + 1, 1) ~ /[0-9]/)) {
      j = i + 1
      while (j <= L) {
        ch = substr(s, j, 1)
        if (ch ~ /[A-Za-z0-9_.$-]/) { j++; continue }
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
    if (c2 == "==" || c2 == "!=" || c2 == "<=" || c2 == ">=" || c2 == "=>" || c2 == "::" || c2 == "&&" || c2 == "||" || c2 == "??") {
      tok("p", "op " c2); i += 2; continue
    }
    if (index("{}[]()=,:@", c) > 0) { tok("p", c); i++; continue }
    tok("p", "op " c)
    i++
  }
  tok("EOF", "")
  return 1
}

function row(path, kind, value) {
  NR_++
  RF[NR_] = FILE_; RP[NR_] = path; RK[NR_] = kind; RV[NR_] = value
  FR[FILE_, ++FN[FILE_]] = NR_
  ROW[FILE_, path] = NR_
}

function skip_sep() { while (T[P] == "nl" || (T[P] == "p" && V[P] == ",")) P++ }
function skip_nl() { while (T[P] == "nl") P++ }
function is_p(k, v) { return T[k] == "p" && V[k] == v }
function opener(k) { return T[k] == "p" && (V[k] == "{" || V[k] == "[" || V[k] == "(") }
function closer(k) { return T[k] == "p" && (V[k] == "}" || V[k] == "]" || V[k] == ")") }

# Skip one balanced ( ), [ ] or { } group starting at P.
function skip_group(    d) {
  d = 0
  while (T[P] != "EOF") {
    if (opener(P)) d++
    else if (closer(P)) { d--; if (d == 0) { P++; return } }
    P++
  }
  bad = 1
}

# Skip to the newline that ends a statement at depth 0.
function skip_statement(    d) {
  d = 0
  while (T[P] != "EOF") {
    if (opener(P)) d++
    else if (closer(P)) d--
    else if (d == 0 && T[P] == "nl") return
    P++
  }
}

function parse_object(prefix, endp,    key) {
  while (!bad) {
    skip_sep()
    if (T[P] == "EOF") { if (endp != "") bad = 1; return }
    if (is_p(P, endp)) { P++; return }
    if (is_p(P, "@")) { P++; if (T[P] == "n") P++; if (is_p(P, "(")) skip_group(); continue }
    if (T[P] == "n" && V[P] == "resource" && T[P + 1] == "n") { parse_resource(prefix); continue }
    if (T[P] != "s" && T[P] != "n") { bad = 1; return }
    key = V[P]
    P++
    if (!is_p(P, ":")) { bad = 1; return }
    P++
    skip_nl()
    parse_value(prefix key)
  }
}

# A value runs to a newline, comma, or unmatched closer at depth 0.
function parse_value(path,    E, d, first, k, raw, t, n) {
  d = 0; first = 0; E = P
  while (T[E] != "EOF") {
    if (opener(E)) d++
    else if (closer(E)) {
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
  if (first == E - 1 && is_p(P, "[") && T[k] == "n" && V[k] == "for") {
    # A loop is read once: its body is item [0].
    d = 0
    for (P = k; T[P] != "EOF"; P++) {
      if (opener(P)) d++
      else if (closer(P)) d--
      else if (d == 0 && is_p(P, ":")) break
    }
    if (T[P] == "EOF") { bad = 1; return }
    P++
    skip_nl()
    if (T[P] == "n" && V[P] == "if") { P++; skip_group(); skip_nl() }
    parse_value(path "[0]")
    skip_sep()
    if (!is_p(P, "]")) { bad = 1; return }
    P++
    return
  }
  if (first == E - 1 && is_p(P, "[")) {
    P++; n = 0
    while (!bad) {
      skip_sep()
      if (is_p(P, "]")) { P++; return }
      if (T[P] == "EOF") { bad = 1; return }
      parse_value(path "[" n++ "]")
    }
    return
  }
  if (first == E - 1 && is_p(P, "{")) { P++; parse_object(path ".", "}"); return }
  raw = ""
  for (t = P; t < E; t++) {
    if (T[t] == "nl") continue
    raw = raw (raw == "" ? "" : " ") (T[t] == "s" ? "'" V[t] "'" : (T[t] == "p" ? substr(V[t], index(V[t], " ") + 1) : V[t]))
  }
  row(path, "u", raw)
  P = E
}

# resource <sym> '<type>@<version>' [existing] = { } | if (...) { } | [for ...: { }]
function parse_resource(prefix,    sym, type, pre) {
  sym = V[P + 1]
  if (T[P + 2] != "s") { bad = 1; return }
  type = V[P + 2]
  sub(/@.*/, "", type)
  P += 3
  if (T[P] == "n" && V[P] == "existing") P++
  pre = parse_decl(prefix "resource." sym)
  if (bad) return
  if (prefix == "") { RES[FILE_, ++RN[FILE_]] = pre; RTYPE[FILE_, pre] = type; RSYM[FILE_, pre] = sym }
}

# The = body of a resource or module. Returns the row prefix of its body.
function parse_decl(path) {
  if (!is_p(P, "=")) { bad = 1; return "" }
  P++
  skip_nl()
  if (T[P] == "n" && V[P] == "if") { P++; skip_group(); skip_nl() }
  if (is_p(P, "[")) { parse_value(path); return path "[0]." }
  if (!is_p(P, "{")) { bad = 1; return "" }
  parse_value(path)
  return path "."
}

function parse_bicep(    kw, name, sec, pre) {
  sec = 0
  while (!bad) {
    skip_sep()
    if (T[P] == "EOF") return
    if (is_p(P, "@")) {
      P++
      if (T[P] != "n") { bad = 1; return }
      if (V[P] ~ /^(sys\.)?secure$/) sec = 1
      P++
      if (is_p(P, "(")) skip_group()
      continue
    }
    if (T[P] != "n") { bad = 1; return }
    kw = V[P]
    if (kw == "param" || kw == "var") {
      name = V[P + 1]
      if (T[P + 1] != "n") { bad = 1; return }
      P += 2
      if (kw == "param") { PDECL[FILE_, name] = 1; if (sec) SEC[FILE_, name] = 1 }
      while (T[P] != "EOF" && T[P] != "nl" && !is_p(P, "=")) { if (opener(P)) skip_group(); else P++ }
      if (is_p(P, "=")) { P++; skip_nl(); parse_value(kw "." name ".default") }
    } else if (kw == "resource") {
      parse_resource("")
    } else if (kw == "module") {
      name = V[P + 1]
      if (T[P + 1] != "n" || T[P + 2] != "s") { bad = 1; return }
      MSRC[FILE_, name] = V[P + 2]
      P += 3
      pre = parse_decl("module." name)
      MOD[FILE_, ++MN[FILE_]] = name
      MPRE[FILE_, name] = pre
    } else if (kw == "using") {
      P++
      USING[FILE_] = (T[P] == "s") ? V[P] : "none"
      skip_statement()
    } else if (kw == "extends") {
      EXTENDS[FILE_] = 1
      skip_statement()
    } else if (kw ~ /^(targetScope|metadata|output|type|func|import|extension|provider|assert)$/) {
      skip_statement()
    } else { bad = 1; return }
    sec = 0
  }
}

function parse_file(f, s) {
  FILE_ = f
  bad = 0
  if (!tokenize(f, s)) fail(tp(f) "-unreadable:" f)
  P = 1
  skip_nl()
  if (f ~ /\.json$/) {
    if (!is_p(P, "{")) fail("arm-unreadable:" f)
    P++
    parse_object("", "}")
  } else parse_bicep()
  if (bad) fail(tp(f) "-unreadable:" f)
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

function field(f, path) {
  if ((f SUBSEP path) in ROW) { FK = RK[ROW[f, path]]; FV = RV[ROW[f, path]]; return 1 }
  FK = ""; FV = ""
  return 0
}
# Array items pre[0]., pre[1]., ... in order.
function items(f, pre, out,    n) {
  n = 0
  while (1) {
    if (!has_under(f, pre "[" n "].")) return n
    out[n + 1] = pre "[" n "]."
    n++
  }
}
function has_under(f, pre,    k, r) {
  for (k = 1; k <= FN[f]; k++) { r = FR[f, k]; if (index(RP[r], pre) == 1) return 1 }
  return 0
}

function unresolved(raw) { RES_OK = 0; return "unresolved:" raw }

# A parameters-file value is a literal; anything computed stays unresolved.
function literal(f, kind, v) {
  RES_OK = 1
  if (kind == "l") return v
  if (kind == "s" && (f ~ /\.json$/ || index(v, "${") == 0)) return v
  return unresolved(kind == "s" ? "'" v "'" : v)
}

# Resolve one value in scope sc. Sets RES_OK and RES_SEC.
function resolve(sc, kind, v, depth,    f, out, rest, p, q, inner, r, ok, sec, e) {
  RES_SEC = 0
  RES_OK = 1
  f = S_file[sc]
  if (depth > 8) return unresolved(v)
  if (kind == "l") return v
  if (kind == "u") return unresolved(v)
  if (kind == "x") {
    if ((f SUBSEP v) in PDECL) return resolve_param(sc, v, depth + 1)
    return unresolved(v)
  }
  if (f ~ /\.json$/) {
    if (substr(v, 1, 2) == "[[") return substr(v, 2)
    if (v !~ /^\[.*\]$/) return v
    e = trim(substr(v, 2, length(v) - 2))
    if (tolower(e) ~ /^parameters\([ ]*'[^']*'[ ]*\)$/) {
      p = index(e, "'")
      inner = substr(e, p + 1)
      inner = substr(inner, 1, index(inner, "'") - 1)
      if ((f SUBSEP inner) in PDECL) return resolve_param(sc, inner, depth + 1)
    }
    return unresolved(e)
  }
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
  if (!ok) { r = unresolved("'" v "'"); RES_SEC = sec; return r }
  RES_OK = 1
  RES_SEC = sec
  return out rest
}

function resolve_param(sc, name, depth,    f, cf, pf, r, sec) {
  f = S_file[sc]
  sec = ((f SUBSEP name) in SEC)
  pf = S_pf[sc]
  if (S_caller[sc] != "") {
    cf = S_file[S_caller[sc]]
    if (field(cf, S_argpre[sc] name)) { r = resolve(S_caller[sc], FK, FV, depth + 1); if (sec) RES_SEC = 1; return r }
  } else if (pf != "" && pf ~ /\.json$/) {
    if (has_under(pf, "parameters." name ".reference.")) { RES_OK = 1; RES_SEC = 1; return "reference" }
    if (field(pf, "parameters." name ".value")) { r = literal(pf, FK, FV); RES_SEC = sec; return r }
  } else if (pf != "") {
    if (field(pf, "param." name ".default")) { r = literal(pf, FK, FV); RES_SEC = sec; return r }
  }
  if (field(f, "param." name ".default") || field(f, "parameters." name ".defaultValue")) {
    r = resolve(sc, FK, FV, depth + 1); if (sec) RES_SEC = 1; return r
  }
  r = unresolved(f ~ /\.json$/ ? "parameters('" name "')" : name)
  RES_SEC = sec
  return r
}

function get(sc, path, dflt) {
  if (!field(S_file[sc], path)) { RES_OK = 1; RES_SEC = 0; return dflt }
  return resolve(sc, FK, FV, 0)
}
# get() for a field printed as is: a value from a secure parameter prints as [redacted].
function show(sc, path, dflt,    v) {
  v = get(sc, path, dflt)
  return RES_SEC ? "[redacted]" : v
}

function node(sc, id, type, name, ev) {
  printf "{\"id\":\"%s\",\"env\":\"%s\",\"tool\":\"%s\",\"kind\":\"compute\",\"name\":\"%s\",\"detail\":\"%s\",\"evidence\":\"%s\"}\n", \
    jesc(id), jesc(S_env[sc]), tool, jesc(name), jesc(type), jesc(ev) >> nodes
}

function param(sc, c, k, v, sec, ev,    e, red, pk) {
  e = S_env[sc]
  red = (sec || redact_secret(k, v)) ? "yes" : "no"
  printf "{\"parameter\":\"%s\",\"env\":\"%s\",\"tool\":\"%s\",\"container\":\"%s\",\"value\":\"%s\",\"redacted\":\"%s\",\"evidence\":\"%s\"}\n", \
    jesc(k), jesc(e), tool, jesc(c), jesc(red == "yes" ? "" : v), red, jesc(ev) >> params
  pk = e SUBSEP c SUBSEP k
  param_seen[pk] = 1
  if (red == "yes") secret_val[pk] = v
  else plain_val[pk] = v
}

function place(sc, c, img, reps, ports, compute, ev,    e) {
  e = S_env[sc]
  printf "{\"container\":\"%s\",\"env\":\"%s\",\"tool\":\"%s\",\"node\":\"%s\",\"compute\":\"%s\",\"image\":\"%s\",\"replicas\":\"%s\",\"ports\":\"%s\",\"networks\":\"\",\"evidence\":\"%s\"}\n", \
    jesc(c), jesc(e), tool, jesc(compute != "" ? compute : e), jesc(compute), jesc(img), jesc(reps), jesc(ports), jesc(ev) >> places
  placed[e SUBSEP c] = 1
  image[e SUBSEP c] = img
  replica_of[e SUBSEP c] = reps
  if (ports != "") portjoin[e SUBSEP c] = ports
}

# One env entry: a secret reference or secure value is a redacted parameter.
function env_entry(sc, c, g, secret_key, ev,    f, k, v) {
  f = S_file[sc]
  k = show(sc, g "name", "")
  if (k == "") return
  if (field(f, g secret_key)) {
    v = (secret_key == "secretRef") ? "reference" : resolve(sc, FK, FV, 0)
    param(sc, c, k, v, 1, ev)
    return
  }
  v = get(sc, g "value", "")
  param(sc, c, k, v, RES_SEC, ev)
}

# The compute node id a reference names: a Bicep <sym>.id, or an ARM
# resourceId('<type>', <name>) whose name matches a declared resource.
function compute_ref(sc, path, type,    f, v, e, lt, p, nm) {
  f = S_file[sc]
  if (!field(f, path)) return ""
  if (FK == "x" && FV ~ /^[A-Za-z_][A-Za-z0-9_]*\.id$/) {
    v = substr(FV, 1, length(FV) - 3)
    return ((sc SUBSEP type SUBSEP "sym" SUBSEP v) in CID) ? CID[sc, type, "sym", v] : ""
  }
  if (FK != "s" || FV !~ /^\[.*\]$/) return ""
  e = trim(substr(FV, 2, length(FV) - 2))
  lt = tolower(e)
  if (index(lt, "resourceid('" type "'") != 1) return ""
  e = substr(e, length(type) + 14)
  sub(/^[ ]*,[ ]*/, "", e)
  if (substr(e, length(e)) != ")") return ""
  e = trim(substr(e, 1, length(e) - 1))
  if (e ~ /^'[^']*'$/) nm = substr(e, 2, length(e) - 2)
  else { nm = resolve(sc, "s", "[" e "]", 0); if (!RES_OK) return "" }
  return ((sc SUBSEP type SUBSEP "name" SUBSEP nm) in CID) ? CID[sc, type, "name", nm] : ""
}

# A containers list that is an expression places one container named for the
# resource, its image the unresolved expression.
function unread_containers(sc, rp, path, reps, ports, cl,    f, img) {
  f = S_file[sc]
  if (!field(f, rp path)) return 0
  img = resolve(sc, FK, FV, 0)
  if (RES_SEC) img = "[redacted]"
  place(sc, show(sc, rp "name", RSYM[f, rp]), img, reps, ports, cl, f)
  return 1
}

function map_scope(sc,    f, i, rp, type, lt, id, nm, n, k, gs, eg, cp, c, img, reps, ports, cl, j, m, fx, raw, pv) {
  f = S_file[sc]
  for (i = 1; i <= RN[f]; i++) {
    rp = RES[f, i]; lt = tolower(RTYPE[f, rp])
    if (lt == "microsoft.resources/deployments") fail(tp(f) "-deployment-unread:" f ":" RSYM[f, rp])
    if (lt !~ /^microsoft\.(app\/(managed|connected)environments|web\/serverfarms|containerservice\/managedclusters|containerinstance\/containergroups)$/) continue
    id = S_env[sc] "/" S_prefix[sc] RSYM[f, rp]
    nm = show(sc, rp "name", RSYM[f, rp])
    node(sc, id, RTYPE[f, rp], nm, f)
    CID[sc, lt, "sym", RSYM[f, rp]] = id
    CID[sc, lt, "name", get(sc, rp "name", RSYM[f, rp])] = id
  }
  for (i = 1; i <= RN[f]; i++) {
    rp = RES[f, i]; lt = tolower(RTYPE[f, rp])
    if (lt == "microsoft.app/containerapps") {
      cl = compute_ref(sc, rp "properties.managedEnvironmentId", "microsoft.app/managedenvironments")
      if (cl == "") cl = compute_ref(sc, rp "properties.environmentId", "microsoft.app/managedenvironments")
      if (cl == "") cl = compute_ref(sc, rp "properties.environmentId", "microsoft.app/connectedenvironments")
      reps = show(sc, rp "properties.template.scale.minReplicas", "undeclared")
      ports = show(sc, rp "properties.configuration.ingress.targetPort", "")
      if (unread_containers(sc, rp, "properties.template.containers", reps, ports, cl)) continue
      n = items(f, rp "properties.template.containers", gs)
      for (k = 1; k <= n; k++) {
        c = show(sc, gs[k] "name", RSYM[f, rp])
        place(sc, c, show(sc, gs[k] "image", ""), reps, ports, cl, f)
        m = items(f, gs[k] "env", eg)
        for (j = 1; j <= m; j++) env_entry(sc, c, eg[j], "secretRef", f)
      }
    } else if (lt == "microsoft.containerinstance/containergroups") {
      id = S_env[sc] "/" S_prefix[sc] RSYM[f, rp]
      if (unread_containers(sc, rp, "properties.containers", "undeclared", "", id)) continue
      n = items(f, rp "properties.containers", gs)
      for (k = 1; k <= n; k++) {
        cp = gs[k] "properties."
        c = show(sc, gs[k] "name", RSYM[f, rp])
        ports = ""
        m = items(f, cp "ports", eg)
        for (j = 1; j <= m; j++) { pv = show(sc, eg[j] "port", ""); if (pv != "") ports = (ports == "" ? pv : ports "," pv) }
        place(sc, c, show(sc, cp "image", ""), "undeclared", ports, id, f)
        m = items(f, cp "environmentVariables", eg)
        for (j = 1; j <= m; j++) env_entry(sc, c, eg[j], "secureValue", f)
      }
    } else if (lt == "microsoft.web/sites") {
      fx = "properties.siteConfig.linuxFxVersion"
      if (!field(f, rp fx)) fx = "properties.siteConfig.windowsFxVersion"
      if (!field(f, rp fx)) continue
      raw = FV
      img = get(sc, rp fx, "")
      if (img ~ /^DOCKER[|]/) img = substr(img, 8)
      else if (index(toupper(raw), "DOCKER|") == 0) continue
      if (RES_SEC) img = "[redacted]"
      c = show(sc, rp "name", RSYM[f, rp])
      cl = compute_ref(sc, rp "properties.serverFarmId", "microsoft.web/serverfarms")
      place(sc, c, img, "undeclared", "", cl, f)
      m = items(f, rp "properties.siteConfig.appSettings", eg)
      for (j = 1; j <= m; j++) env_entry(sc, c, eg[j], "", f)
    }
  }
}

function new_scope(f, env, caller, argpre, prefix, pf) {
  NS++
  S_file[NS] = f; S_env[NS] = env; S_caller[NS] = caller; S_argpre[NS] = argpre; S_prefix[NS] = prefix; S_pf[NS] = pf
  return NS
}

function instantiate(sc, depth,    f, i, m, c) {
  if (depth > 10) fail(tp(S_file[sc]) "-module-unread:" S_file[sc] ":module-depth")
  map_scope(sc)
  f = S_file[sc]
  for (i = 1; i <= MN[f]; i++) {
    m = MOD[f, i]
    c = new_scope(MTARGET[f, m], S_env[sc], sc, MPRE[f, m] "params.", S_prefix[sc] "module." m ".", "")
    instantiate(c, depth + 1)
  }
}

function add_env(e, ev) {
  if (!(e in env_seen)) { env_seen[e] = 1; env_list[++env_n] = e; env_ev[e] = ev }
  else if (index(", " env_ev[e] ", ", ", " ev ", ") == 0) env_ev[e] = env_ev[e] ", " ev
}

# A relative path joined to a directory, or "" when it climbs out of the repository.
function join(d, rel,    t, nseg, seg, j, out, depth) {
  t = (d == "." ? rel : d "/" rel)
  nseg = split(t, seg, "/"); out = ""; depth = 0
  for (j = 1; j <= nseg; j++) {
    if (seg[j] == "" || seg[j] == ".") continue
    if (seg[j] == "..") { if (depth == 0) return ""; sub(/\/?[^\/]*$/, "", out); depth--; continue }
    out = (out == "" ? seg[j] : out "/" seg[j]); depth++
  }
  return out
}

function dir_env(t,    d) { d = dirof(t); return d == "." ? "default" : base(d) }

function root_scope(t, env, pf) {
  add_env(env, t (pf != "" ? ", " pf : ""))
  instantiate(new_scope(t, env, "", "", "", pf), 0)
}

END {
  if (failed) exit 0
  for (i = 1; i <= nfiles; i++) parse_file(files[i], src[files[i]])
  for (i = 1; i <= nfiles; i++) {
    f = files[i]
    if (f ~ /\.bicep$/) is_tpl[f] = 1
    else if (f ~ /\.json$/ && field(f, "$schema")) {
      if (tolower(FV) ~ /deploymenttemplate/) is_tpl[f] = 1
      else if (tolower(FV) ~ /deploymentparameters/) is_pjson[f] = 1
    }
    if (!is_tpl[f]) continue
    # ARM declarations: resources (an array, or an object under languageVersion 2.0) and
    # parameters, secure when typed securestring or secureobject.
    for (k = 1; k <= FN[f]; k++) {
      r = FR[f, k]
      if (f ~ /\.json$/ && RP[r] ~ /^resources(\[[0-9]+\]|\.[^.\[]+)\.type$/ && RK[r] == "s") {
        pre = substr(RP[r], 1, length(RP[r]) - 4)
        sym = substr(pre, 11, length(pre) - 11)
        if (substr(pre, 10, 1) == "[") sym = "resources" substr(pre, 10, length(pre) - 10)
        RES[f, ++RN[f]] = pre; RTYPE[f, pre] = RV[r]; RSYM[f, pre] = sym
      }
      if (f ~ /\.json$/ && RP[r] ~ /^parameters\.[^.]+\.type$/) {
        name = substr(RP[r], 12, length(RP[r]) - 16)
        PDECL[f, name] = 1
        if (tolower(RV[r]) ~ /^secure(string|object)$/) SEC[f, name] = 1
      }
    }
    # A module is a local Bicep or ARM file; a registry or template-spec source is unread.
    for (k = 1; k <= MN[f]; k++) {
      m = MOD[f, k]
      t = (MSRC[f, m] ~ /^(br|ts)[:\/]/) ? "" : join(dirof(f), MSRC[f, m])
      if (t == "") fail("bicep-module-unread:" f ":module." m)
      MTARGET[f, m] = t
      is_mod[t] = 1
    }
  }
  for (i = 1; i <= nfiles; i++) {
    f = files[i]
    for (k = 1; k <= MN[f]; k++) if (!is_tpl[MTARGET[f, MOD[f, k]]]) fail("bicep-module-unread:" f ":module." MOD[f, k])
  }
  # Pair each parameters file with its template.
  for (i = 1; i <= nfiles; i++) {
    f = files[i]
    if (f ~ /\.bicepparam$/) {
      if (EXTENDS[f] || USING[f] == "" || USING[f] == "none" || USING[f] ~ /^(br|ts)[:\/]/) fail("bicep-param-unread:" f)
      t = join(dirof(f), USING[f])
      if (!is_tpl[t]) fail("bicep-param-unread:" f)
      e = base(f); sub(/\.bicepparam$/, "", e)
      if (index(e, ".") > 0) sub(/.*\./, "", e)
      else if (e == base(t) || e ".bicep" == base(t) || e ".json" == base(t)) e = ""
    } else if (is_pjson[f]) {
      b = base(f); d = dirof(f); t = ""
      if (match(b, /\.parameters([.-][^.]+)?\.json$/)) {
        stem = substr(b, 1, RSTART - 1)
        if (is_tpl[join(d, stem ".bicep")]) t = join(d, stem ".bicep")
        else if (is_tpl[join(d, stem ".json")]) t = join(d, stem ".json")
      }
      if (t == "") {
        n = 0
        for (j = 1; j <= nfiles; j++) if (is_tpl[files[j]] && !is_mod[files[j]] && dirof(files[j]) == d) { n++; t = files[j] }
        if (n != 1) fail("arm-parameters-unpaired:" f)
      }
      e = b; sub(/\.json$/, "", e)
      if (match(e, /parameters[.-]/)) e = substr(e, RSTART + RLENGTH)
      else e = ""
    } else continue
    PT[++npf] = t; PFILE[npf] = f; PENV[npf] = (e == "" ? dir_env(t) : e)
    has_pf[t] = 1
  }
  for (i = 1; i <= nfiles; i++) {
    t = files[i]
    if (!is_tpl[t] || tp(t) != tool || (is_mod[t] && !has_pf[t])) continue
    if (!has_pf[t]) { root_scope(t, dir_env(t), ""); continue }
    for (j = 1; j <= npf; j++) if (PT[j] == t) root_scope(t, PENV[j], PFILE[j])
  }
  for (i = 1; i <= env_n; i++)
    printf "{\"environment\":\"%s\",\"tool\":\"%s\",\"evidence\":\"%s\"}\n", jesc(env_list[i]), tool, jesc(env_ev[env_list[i]]) >> envs
  for (i = 1; i <= env_n; i++) for (j = i + 1; j <= env_n; j++) {
    a = env_list[i]; b = env_list[j]
    if (a > b) { t = a; a = b; b = t }
    container_diffs(a, b, tool)
    param_port_diffs(a, b, tool)
  }
}
