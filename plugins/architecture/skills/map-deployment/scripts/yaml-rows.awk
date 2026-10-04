# YAML and JSON flattener plus the ECS mapping shared by the CloudFormation and
# Pulumi YAML readers. Prepend redact-connection.awk and deployment-diff.awk,
# append a reader that defines resolve_at(), collect_res(), lref(), cdpath(), a
# BEGIN block setting CAP, CLUSTER_NAME_PROP and SERVICE_NAME_PROP, and an END
# block that calls parse_all(), builds scopes, and calls finish(). Arguments are
# repo-relative paths prefixed with "./". Set tool (cloudformation or
# pulumi-yaml), places, params, nodes, envs, diffs and flag to output files.
#
# Every file is flattened into rows of path, kind, value. Kinds: s a string, l a
# number, bool or null. A short tag (!Ref x, !Sub "..", !GetAtt a.b) becomes the
# long form (Ref, Fn::Sub, Fn::GetAtt) under its node, so YAML tags and JSON
# intrinsics read the same. A block scalar is one string. Anchors, aliases, the
# << merge key, duplicate keys, tabs as indentation,
# and more than one document are not read: the file refuses as
# <cloudformation|pulumi>-unreadable:<file>.

function trim(s) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
function jesc(s) { if (redact_secret_value(s)) s = "[redacted]"; gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
function dirof(p) { if (sub(/\/[^\/]*$/, "", p)) return p; return "." }
function base(p) { sub(/.*\//, "", p); return p }
function dir_env(t,    d) { d = dirof(t); return d == "." ? "default" : base(d) }
function fail(reason) { print reason > flag; failed = 1; exit 0 }
function jp(p, k) { return p == "" ? k : p "." k }
function ck(k) { return CAP ? toupper(substr(k, 1, 1)) substr(k, 2) : k }

BEGIN { pfx = tool; sub(/-yaml$/, "", pfx); nfiles = 0 }
{
  if (FNR == 1) {
    f = FILENAME
    sub(/^\.\//, "", f)
    files[++nfiles] = f
  }
  src[f] = src[f] $0 "\n"
}

# Drop a trailing comment; a quote opens only at the start of a token.
function uncomment(s,    L, k, c, q, out, pc) {
  L = length(s); q = ""; out = ""
  for (k = 1; k <= L; k++) {
    c = substr(s, k, 1)
    pc = (k > 1) ? substr(s, k - 1, 1) : " "
    if (q == "") {
      if (c == "#" && (pc == " " || pc == "\t")) break
      if ((c == "\"" || c == "'") && (pc == " " || pc == "\t" || pc == "[" || pc == "{" || pc == "," || pc == ":")) q = c
    } else if (q == "\"" && c == "\\") {
      out = out c; k++; c = substr(s, k, 1)
    } else if (q == "'" && c == "'" && substr(s, k + 1, 1) == "'") {
      out = out c; k++; c = "'"
    } else if (c == q) q = ""
    out = out c
  }
  return out
}

function prep_lines(s,    i, l) {
  NL = split(s, LR, "\n")
  if (NL > 0 && LR[NL] == "") NL--
  for (i = 1; i <= NL; i++) {
    l = LR[i]; sub(/\r$/, "", l); LR[i] = l
    LI[i] = 0; LC[i] = ""; TB[i] = 0
    if (l ~ /^ *$/) continue
    match(l, /^ */); LI[i] = RLENGTH
    if (substr(l, LI[i] + 1, 1) == "\t") TB[i] = 1
    LC[i] = trim(uncomment(substr(l, LI[i] + 1)))
  }
}

# Structure registration. KTY node type (m map, a array), KN/KP children in
# order, KK the key of a child, ROW/RK/RV scalar rows.
function set_type(p, t) { KTY[FILE_, p] = t }
function reg(p, kp, key) {
  if ((FILE_ SUBSEP kp) in SEEN) { bad = 1; return }
  SEEN[FILE_, kp] = 1
  KN[FILE_, p]++
  KP[FILE_, p, KN[FILE_, p]] = kp
  KK[FILE_, kp] = key
}
function child_m(p, key,    kp) { set_type(p, "m"); kp = jp(p, key); reg(p, kp, key); return kp }
function child_a(p, n,    kp) { set_type(p, "a"); kp = p "[" n "]"; reg(p, kp, n); return kp }
function row(p, kind, v) { ROW[FILE_, p] = 1; RK[FILE_, p] = kind; RV[FILE_, p] = v }
function skind(v) { return (v ~ /^-?[0-9][0-9.]*$/ || tolower(v) ~ /^(true|false|null)$/ || v == "~") ? "l" : "s" }
function fnkey(tag) { sub(/^!/, "", tag); return (tag == "Ref" || tag == "Condition") ? tag : "Fn::" tag }

# Lookups over one file f.
function fld(f, p) {
  if ((f SUBSEP p) in ROW) { FK = RK[f, p]; FV = RV[f, p]; return 1 }
  FK = ""; FV = ""
  return 0
}
function has(f, p) { return ((f SUBSEP p) in ROW) || ((f SUBSEP p) in KTY) }
function is_arr(f, p) { return ((f SUBSEP p) in KTY) && KTY[f, p] == "a" }
function kids(f, p, out,    n, i) { n = KN[f, p] + 0; for (i = 1; i <= n; i++) out[i] = KP[f, p, i]; return n }
function items(f, p, out) { if (!is_arr(f, p)) return 0; return kids(f, p, out) }
# Compact text of a subtree, for unresolved:<text>.
function serialize(f, p,    t, n, i, out, kp) {
  if ((f SUBSEP p) in ROW) return (RK[f, p] == "s") ? "\"" RV[f, p] "\"" : RV[f, p]
  if (!((f SUBSEP p) in KTY)) return ""
  t = KTY[f, p]; n = KN[f, p] + 0; out = ""
  for (i = 1; i <= n; i++) { kp = KP[f, p, i]; out = out (i > 1 ? "," : "") (t == "m" ? KK[f, kp] ":" : "") serialize(f, kp) }
  return (t == "a") ? "[" out "]" : "{" out "}"
}

# Flow collections and quoted scalars, read from FS_ at FP.
function fws() { while (substr(FS_, FP, 1) == " " || substr(FS_, FP, 1) == "\t") FP++ }
function fquoted(    q, out, ch, nx) {
  q = substr(FS_, FP, 1); out = ""; FP++
  while (1) {
    if (FP > length(FS_)) { fqerr = 1; return "" }
    ch = substr(FS_, FP, 1)
    if (q == "\"" && ch == "\\") {
      nx = substr(FS_, FP + 1, 1)
      if (nx == "\"" || nx == "\\" || nx == "/") out = out nx
      else if (nx == "n" || nx == "t" || nx == "r") out = out " "
      else out = out "\\" nx
      FP += 2
      continue
    }
    if (q == "'" && ch == "'" && substr(FS_, FP + 1, 1) == "'") { out = out "'"; FP += 2; continue }
    if (ch == q) { FP++; return out }
    out = out ch
    FP++
  }
}
function fkey(    c, j, ch) {
  fws()
  c = substr(FS_, FP, 1)
  if (c == "\"" || c == "'") { fqerr = 0; c = fquoted(); if (fqerr) bad = 1; return c }
  j = FP
  while (j <= length(FS_)) {
    ch = substr(FS_, j, 1)
    if (ch == "," || ch == "}" || (ch == ":" && (substr(FS_, j + 1, 1) == " " || j == length(FS_) || substr(FS_, j + 1, 1) ~ /[,}]/))) break
    j++
  }
  c = trim(substr(FS_, FP, j - FP))
  FP = j
  if (c == "") bad = 1
  return c
}
function fparse(path,    c, n, kp, key, j, ch, tag, v) {
  fws()
  c = substr(FS_, FP, 1)
  if (c == "[") {
    FP++; set_type(path, "a"); n = 0
    while (!bad) {
      fws(); c = substr(FS_, FP, 1)
      if (c == "]") { FP++; return }
      if (c == "") { bad = 1; return }
      fparse(child_a(path, n++))
      fws(); c = substr(FS_, FP, 1)
      if (c == ",") FP++
      else if (c != "]") { bad = 1; return }
    }
    return
  }
  if (c == "{") {
    FP++; set_type(path, "m")
    while (!bad) {
      fws(); c = substr(FS_, FP, 1)
      if (c == "}") { FP++; return }
      if (c == "") { bad = 1; return }
      key = fkey()
      if (bad || key == "<<") { bad = 1; return }
      kp = child_m(path, key)
      fws()
      if (substr(FS_, FP, 1) == ":") {
        FP++; fws(); c = substr(FS_, FP, 1)
        if (c == "," || c == "}") row(kp, "l", "")
        else fparse(kp)
      } else row(kp, "l", "")
      fws(); c = substr(FS_, FP, 1)
      if (c == ",") FP++
      else if (c != "}") { bad = 1; return }
    }
    return
  }
  if (c == "!") {
    j = FP
    while (j <= length(FS_) && substr(FS_, j, 1) != " " && substr(FS_, j, 1) != "\t") j++
    tag = substr(FS_, FP, j - FP); FP = j
    fws(); c = substr(FS_, FP, 1)
    if (c == "" || c == "," || c == "]" || c == "}") { bad = 1; return }
    if (tag ~ /^!!/) { fparse(path); return }
    fparse(child_m(path, fnkey(tag)))
    return
  }
  if (c == "\"" || c == "'") {
    fqerr = 0; v = fquoted()
    if (fqerr) { bad = 1; return }
    row(path, "s", v)
    return
  }
  if (c == "&" || c == "*") { bad = 1; return }
  j = FP
  while (j <= length(FS_)) { ch = substr(FS_, j, 1); if (ch == "," || ch == "]" || ch == "}") break; j++ }
  v = trim(substr(FS_, FP, j - FP)); FP = j
  if (v == "") { bad = 1; return }
  row(path, skind(v), v)
}

# Bracket depth of s outside quotes.
function depth_of(s,    L, k, c, q, pc, d) {
  L = length(s); q = ""; d = 0
  for (k = 1; k <= L; k++) {
    c = substr(s, k, 1); pc = (k > 1) ? substr(s, k - 1, 1) : " "
    if (q == "") {
      if ((c == "\"" || c == "'") && (pc == " " || pc == "\t" || pc == "[" || pc == "{" || pc == "," || pc == ":")) q = c
      else if (c == "[" || c == "{") d++
      else if (c == "]" || c == "}") d--
    } else if (q == "\"" && c == "\\") k++
    else if (c == q) q = ""
  }
  return d
}

function cur() {
  while (P <= NL && LC[P] == "") P++
  if (P > NL) return 0
  if (TB[P]) { bad = 1; return 0 }
  return 1
}
function is_dash(c) { return c == "-" || substr(c, 1, 2) == "- " }

# A mapping entry "key: value" sets KEY and VAL. A value that is a tag, flow
# collection, alias, block scalar, or quoted scalar with no key is not an entry.
function split_key(s,    c, k, L, ch) {
  KEY = ""; VAL = ""
  c = substr(s, 1, 1)
  L = length(s)
  if (c == "\"" || c == "'") {
    FS_ = s; FP = 1; fqerr = 0
    KEY = fquoted()
    if (fqerr) return 0
    fws()
    if (substr(FS_, FP, 1) == ":" && (FP == L || substr(FS_, FP + 1, 1) == " ")) { VAL = trim(substr(s, FP + 1)); return 1 }
    return 0
  }
  if (index("[{!&*|>%@`", c) > 0) return 0
  for (k = 1; k <= L; k++) {
    if (substr(s, k, 1) == ":" && (k == L || substr(s, k + 1, 1) == " ")) {
      KEY = trim(substr(s, 1, k - 1))
      VAL = trim(substr(s, k + 1))
      return KEY != ""
    }
  }
  return 0
}

function block_scalar(path, ind,    raw, out, bi, n) {
  P++; out = ""; bi = -1
  while (P <= NL) {
    raw = LR[P]
    if (raw ~ /^ *$/) { P++; continue }
    match(raw, /^ */)
    if (RLENGTH <= ind) break
    if (bi < 0) bi = RLENGTH
    out = out (out == "" ? "" : " ") trim(raw)
    P++
  }
  row(path, "s", out)
}

# The value after a key or dash. ind is the indent of that key or dash: a
# child block must sit deeper, and a key may hold a sequence at its own indent.
function parse_value(path, v, ind, iskey,    tag, rest, c) {
  if (substr(v, 1, 1) == "!") {
    tag = v; sub(/[ \t].*$/, "", tag)
    rest = trim(substr(v, length(tag) + 1))
    if (tag ~ /^!!/) { parse_value(path, rest, ind, iskey); return }
    parse_value(child_m(path, fnkey(tag)), rest, ind, iskey)
    return
  }
  if (v == "") {
    P++
    if (cur() && LI[P] > ind) parse_block(path, LI[P])
    else if (iskey && cur() && LI[P] == ind && is_dash(LC[P])) parse_seq(path, ind)
    else row(path, "l", "")
    return
  }
  c = substr(v, 1, 1)
  if (c == "|" || c == ">") { block_scalar(path, ind); return }
  if (c == "&" || c == "*") { bad = 1; return }
  if (c == "\"" || c == "'") {
    while (1) {
      FS_ = v; FP = 1; fqerr = 0
      fquoted()
      if (!fqerr) break
      P++
      if (P > NL) { bad = 1; return }
      v = v " " trim(LR[P])
    }
  } else if (c == "[" || c == "{") {
    while (depth_of(v) > 0) {
      P++
      if (P > NL) { bad = 1; return }
      v = v " " LC[P]
    }
  } else {
    # A plain scalar continues on the lines indented deeper than its key.
    while (1) {
      P++
      if (!(cur() && LI[P] > ind)) break
      v = v " " LC[P]
    }
    row(path, skind(v), v)
    return
  }
  P++
  FS_ = v; FP = 1
  fparse(path)
  fws()
  if (!bad && FP <= length(FS_)) bad = 1
}

function parse_seq(path, ind,    n, rest, ip, off, tail) {
  set_type(path, "a"); n = 0
  while (!bad && cur() && LI[P] == ind && is_dash(LC[P])) {
    tail = substr(LC[P], 2)
    rest = trim(tail)
    ip = child_a(path, n++)
    if (rest == "") {
      P++
      if (cur() && LI[P] > ind) parse_block(ip, LI[P])
      else row(ip, "l", "")
      continue
    }
    off = ind + match(tail, /[^ ]/)
    if (is_dash(rest) || split_key(rest)) {
      LC[P] = rest; LI[P] = off
      parse_block(ip, off)
    } else parse_value(ip, rest, ind, 0)
  }
  if (!bad && cur() && LI[P] > ind) bad = 1
}

function parse_map(path, ind,    kp, key, val) {
  set_type(path, "m")
  while (!bad && cur() && LI[P] == ind && !is_dash(LC[P])) {
    if (!split_key(LC[P])) { bad = 1; return }
    key = KEY; val = VAL
    if (key == "<<") { bad = 1; return }
    if (substr(key, 1, 1) == "!" || substr(key, 1, 1) == "&") { bad = 1; return }
    kp = child_m(path, key)
    parse_value(kp, val, ind, 1)
  }
  if (!bad && cur() && LI[P] > ind) bad = 1
}

function parse_block(path, ind) {
  if (!cur() || LI[P] != ind) { bad = 1; return }
  if (is_dash(LC[P])) parse_seq(path, ind)
  else parse_map(path, ind)
}

function parse_file(f, s,    i, first, full, c) {
  FILE_ = f; bad = 0; P = 1
  prep_lines(s)
  first = 0
  for (i = 1; i <= NL; i++) if (LC[i] != "") { first = i; break }
  if (first == 0) fail(pfx "-unreadable:" f)
  c = substr(LC[first], 1, 1)
  if (c == "{" || c == "[") {
    full = ""
    for (i = first; i <= NL; i++) full = full " " LC[i]
    if (depth_of(full) != 0) fail(pfx "-unreadable:" f)
    FS_ = full; FP = 1
    fparse("")
    fws()
    if (FP <= length(FS_)) bad = 1
  } else {
    P = first
    if (LC[P] == "---") P++
    if (cur()) parse_block("", LI[P])
    if (!bad && cur()) bad = 1
  }
  if (bad) fail(pfx "-unreadable:" f)
}
function parse_all(    i) { for (i = 1; i <= nfiles; i++) parse_file(files[i], src[files[i]]) }

# Values.
function unresolved(raw) { RES_OK = 0; return "unresolved:" raw }
# The unresolved text of a subtree. A secret marker anywhere inside it makes the value secret.
function unres(f, p,    t) {
  t = serialize(f, p)
  RES_SEC = (index(t, "{{resolve:") > 0 || index(t, "secure:") > 0 || index(t, "fn::secret:") > 0)
  return unresolved(t)
}
function get(sc, p, dflt) {
  if (!has(S_file[sc], p)) { RES_OK = 1; RES_SEC = 0; return dflt }
  return resolve_at(sc, p, 0)
}
# get() for a field printed as is: a secret value prints as [redacted].
function show(sc, p, dflt,    v) {
  v = get(sc, p, dflt)
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

# One ECS container definition: name, image, ports, environment and secrets. A
# secret reference is a redacted parameter. sfx is appended to the container name.
function ecs_container(sc, g, dflt, reps, cl, ev, sfx,    f, c, img, ports, pg, eg, m, j, pv, k, v, sec) {
  f = S_file[sc]
  c = show(sc, jp(g, ck("name")), dflt) sfx
  img = show(sc, jp(g, ck("image")), "")
  ports = ""
  m = items(f, jp(g, ck("portMappings")), pg)
  for (j = 1; j <= m; j++) { pv = show(sc, jp(pg[j], ck("containerPort")), ""); if (pv != "") ports = (ports == "" ? pv : ports "," pv) }
  place(sc, c, img, reps, ports, cl, ev)
  m = items(f, jp(g, ck("environment")), eg)
  for (j = 1; j <= m; j++) {
    k = show(sc, jp(eg[j], ck("name")), "")
    if (k == "") continue
    v = get(sc, jp(eg[j], ck("value")), "")
    sec = RES_SEC
    param(sc, c, k, v, sec, ev)
  }
  m = items(f, jp(g, ck("secrets")), eg)
  for (j = 1; j <= m; j++) {
    k = show(sc, jp(eg[j], ck("name")), "")
    if (k == "") continue
    v = get(sc, jp(eg[j], ck("valueFrom")), "")
    param(sc, c, k, v, 1, ev)
  }
}

# The cluster, task definition and service of one scope. collect_res() lists
# them in RID, RKIND (cluster, taskdef, service), RTYPE and RPRE, and sets
# KIND_OF[sc, id].
function map_ecs(sc,    f, n, i, j, id, pre, td, cl, nid, reps, img, gs, k, m, ns, sfx) {
  f = S_file[sc]
  n = collect_res(sc)
  for (i = 1; i <= n; i++) {
    if (RKIND[i] != "cluster") continue
    nid = S_env[sc] "/" RID[i]
    node(sc, nid, RTYPE[i], show(sc, jp(RPRE[i], CLUSTER_NAME_PROP), RID[i]), f)
    CID[sc, RID[i]] = nid
  }
  # A service names the task definition and cluster its containers run with.
  for (i = 1; i <= n; i++) {
    if (RKIND[i] != "service") continue
    pre = RPRE[i]
    td = lref(sc, jp(pre, ck("taskDefinition")))
    cl = lref(sc, jp(pre, ck("cluster")))
    nid = ((sc SUBSEP cl) in CID) ? CID[sc, cl] : ""
    reps = show(sc, jp(pre, ck("desiredCount")), "undeclared")
    if (td != "" && KIND_OF[sc, td] == "taskdef") {
      k = ++SVC_N[sc, td]
      SVC_ID[sc, td, k] = RID[i]; SVC_CL[sc, td, k] = nid; SVC_REPS[sc, td, k] = reps
    } else {
      img = has(f, jp(pre, ck("taskDefinition"))) ? unresolved("taskDefinition") : ""
      place(sc, show(sc, jp(pre, SERVICE_NAME_PROP), RID[i]), img, reps, "", nid, f)
    }
  }
  for (i = 1; i <= n; i++) {
    if (RKIND[i] != "taskdef") continue
    id = RID[i]; pre = RPRE[i]
    m = items(f, cdpath(f, pre), gs)
    ns = ((sc SUBSEP id) in SVC_N) ? SVC_N[sc, id] : 0
    # Each service runs the task definition on its own cluster with its own count; with two
    # or more, its resource id keeps their placements of one container apart.
    for (j = 1; j <= (ns > 0 ? ns : 1); j++) {
      reps = ns > 0 ? SVC_REPS[sc, id, j] : "undeclared"
      cl = ns > 0 ? SVC_CL[sc, id, j] : ""
      sfx = ns > 1 ? "@" SVC_ID[sc, id, j] : ""
      for (k = 1; k <= m; k++) ecs_container(sc, gs[k], id, reps, cl, f, sfx)
      if (m == 0) place(sc, id sfx, unresolved("containerDefinitions"), reps, "", cl, f)
    }
  }
}

function add_env(e, ev) {
  if (!(e in env_seen)) { env_seen[e] = 1; env_list[++env_n] = e; env_ev[e] = ev }
  else if (index(", " env_ev[e] ", ", ", " ev ", ") == 0) env_ev[e] = env_ev[e] ", " ev
}

function finish(    i, j, a, b, t) {
  for (i = 1; i <= env_n; i++)
    printf "{\"environment\":\"%s\",\"tool\":\"%s\",\"evidence\":\"%s\"}\n", jesc(env_list[i]), tool, jesc(env_ev[env_list[i]]) >> envs
  for (i = 1; i <= env_n; i++) for (j = i + 1; j <= env_n; j++) {
    a = env_list[i]; b = env_list[j]
    if (a > b) { t = a; a = b; b = t }
    container_diffs(a, b, tool)
    param_port_diffs(a, b, tool)
  }
}
