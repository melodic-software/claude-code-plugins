# Trace one C# entry point through textual call sites.
#
# The bash wrapper sets FLOW_ROOT, FLOW_ENTRY, FLOW_DEPTH, FLOW_SUBJECT,
# FLOW_GENERATED_ON, and FLOW_STATUS. Arguments are repo-relative .cs paths.
# Matched text only. Nothing is executed.
#
# A refusal is one line written to FLOW_STATUS beginning with "refused:".
# On success the record is written to stdout and FLOW_STATUS is left empty.

function jesc(s) {
  gsub(/\\/, "\\\\", s)
  gsub(/"/, "\\\"", s)
  gsub(/\t/, "\\t", s)
  gsub(/\r/, "\\r", s)
  gsub(/\n/, "\\n", s)
  return s
}

# A line without its trailing comment and with string contents emptied.
function strip(line,    s) {
  s = line
  sub(/\/\/.*/, "", s)
  gsub(/"[^"]*"/, "\"\"", s)
  return s
}

function role_of(rel,    p, n, a) {
  p = tolower(rel)
  if (p ~ /\/(transport|controllers|endpoints|api)\//) return "transport"
  if (p ~ /\/application\//) return "application"
  if (p ~ /\/domain\//) return "domain"
  if (p ~ /\/infrastructure\//) return "infrastructure"
  n = split(rel, a, "/")
  if (n >= 2) return tolower(a[n - 1])
  return "unknown"
}

function read_file(rel,    path, line, n) {
  path = root "/" rel
  n = 0
  while ((getline line < path) > 0) {
    gsub(/\r/, "", line)
    n++
    lines[rel, n] = line
  }
  close(path)
  nlines[rel] = n
  files[++nfiles] = rel
  index_file(rel)
}

# A type declaration line; leaves RSTART and RLENGTH on its modifiers, keyword and name.
function is_type_decl(s) {
  return match(s, /^[[:space:]]*(\[[^]]*\][[:space:]]*)*([a-z]+[[:space:]]+)*(class|struct|record|interface)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)
}

# Brace depth at the start of every line, and one record per class, struct,
# record or interface: file, header line, body range, member depth, kind and
# base types. A call binds through these records, never through a bare name.
function index_file(rel,    n, i, depth, s, hdr, rest, tk, nt, name, kind, is_partial, base, nb, bs, b, k) {
  n = nlines[rel]
  depth = 0
  for (i = 1; i <= n; i++) {
    d0[rel, i] = depth
    s = strip(lines[rel, i])
    depth += gsub(/\{/, "{", s) - gsub(/\}/, "}", s)
  }
  for (i = 1; i <= n; i++) {
    s = strip(lines[rel, i])
    if (!is_type_decl(s)) continue
    hdr = substr(s, RSTART, RLENGTH)
    rest = substr(s, RSTART + RLENGTH)
    nt = split(hdr, tk, /[[:space:]]+/)
    name = tk[nt]
    kind = (tk[nt - 1] == "interface" ? "interface" : "class")
    is_partial = (hdr ~ /(^|[[:space:]])partial[[:space:]]/)
    while (rest ~ /<[^<>]*>/) gsub(/<[^<>]*>/, "", rest)
    gsub(/\([^()]*\)/, "", rest)
    if (rest !~ /:/ && i < n && strip(lines[rel, i + 1]) ~ /^[[:space:]]*:/) rest = strip(lines[rel, i + 1])
    base = ""
    if (match(rest, /^[[:space:]]*:/)) {
      rest = substr(rest, RLENGTH + 1)
      sub(/(where[[:space:]].*|\{.*|;.*)$/, "", rest)
      nb = split(rest, bs, ",")
      for (b = 1; b <= nb; b++) {
        gsub(/[[:space:]]/, "", bs[b])
        sub(/.*\./, "", bs[b])
        if (bs[b] != "") base = base " " bs[b]
      }
    }
    k = ++ncls
    c_name[k] = name
    c_kind[k] = kind
    c_rel[k] = rel
    c_line[k] = i
    c_base[k] = base
    c_lo[k] = i
    c_hi[k] = 0
    if (find_body(rel, i)) {
      c_lo[k] = body_lo
      c_hi[k] = body_hi
      c_inner[k] = d0[rel, body_lo] + 1
    }
    nparts[name]++
    part[name, nparts[name]] = k
    if (kind == "class") {
      nconc[name]++
      if (!is_partial) nnp[name]++
    }
    nfcls[rel]++
    fcls[rel, nfcls[rel]] = k
  }
}

# The innermost type whose body holds the line, or 0.
function class_at(rel, line,    j, k, best, span, bspan) {
  best = 0
  bspan = 0
  for (j = 1; j <= nfcls[rel]; j++) {
    k = fcls[rel, j]
    if (line < c_line[k] || line > c_hi[k]) continue
    span = c_hi[k] - c_line[k]
    if (!best || span < bspan) {
      best = k
      bspan = span
    }
  }
  return best
}

function route_of(line,    s) {
  if (!match(line, /(Http(Get|Post|Put|Delete|Patch)|Route|Map(Get|Post|Put|Delete|Patch))[[:space:]]*\([[:space:]]*"/))
    return ""
  s = substr(line, RSTART + RLENGTH)
  if (match(s, /^[^"]*/)) return substr(s, 1, RLENGTH)
  return ""
}

# A declaration line starts with an access modifier, after any attributes. A
# modifier inside an identifier (_internalService, publicUrl) is not one.
function has_modifier(line) {
  return line ~ /^[[:space:]]*(\[[^]]*\][[:space:]]*)*(public|private|protected|internal)[[:space:]]/
}

function is_decl(line, name) {
  if (!has_modifier(line)) return 0
  return match(line, "(^|[^A-Za-z0-9_])" name "[[:space:]]*\\(")
}

# The declaration a route attribute sits on. A route above a type is not
# composed with the routes of its methods, so it names no method (0).
function method_after(rel, attr_line,    i, line) {
  for (i = attr_line; i <= attr_line + 12 && i <= nlines[rel]; i++) {
    line = lines[rel, i]
    if (is_type_decl(line)) return 0
    if (has_modifier(line) && line ~ /\(/) return i
  }
  return attr_line
}

# Whether the handler takes the verb. The Map* call on the route line, or an
# Http* attribute in the handler's attribute block, names the verbs it takes;
# none named takes any.
function verb_ok(rel, i, ml, verb,    lo, hi, j, s, vs) {
  if (verb == "") return 1
  lo = i
  hi = i
  if (lines[rel, i] !~ /Map(Get|Post|Put|Delete|Patch)/) {
    while (lo > 1 && lines[rel, lo - 1] ~ /^[[:space:]]*\[/) lo--
    if (ml > i) hi = ml
  }
  vs = ""
  for (j = lo; j <= hi; j++) {
    s = lines[rel, j]
    while (match(s, /(Http|Map)(Get|Post|Put|Delete|Patch)/)) {
      vs = vs " " toupper(substr(s, RSTART, RLENGTH))
      s = substr(s, RSTART + RLENGTH)
    }
  }
  gsub(/HTTP|MAP/, "", vs)
  return (vs == "" || index(vs " ", " " verb " ") > 0)
}

# The one declaration a Map* call names as its handler, MapGet("/x", Handle) or
# MapGet("/x", Type.Handle): a member of a class holding the call, or of Type.
# Sets mh_rel and mh_line and returns 1. A lambda, or a name that is not exactly
# one declaration, returns 0.
function map_handler(rel, at,    s, n, hp, j, p, i, k, hits) {
  s = lines[rel, at]
  if (!match(s, /Map(Get|Post|Put|Delete|Patch)[[:space:]]*\([[:space:]]*"[^"]*"[[:space:]]*,[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*[,)]/)) return 0
  s = substr(s, RSTART, RLENGTH)
  sub(/^[^"]*"[^"]*"[[:space:]]*,[[:space:]]*/, "", s)
  sub(/[[:space:]]*[,)]$/, "", s)
  n = split(s, hp, ".")
  hits = 0
  if (n > 1) {
    for (j = 1; j <= nparts[hp[n - 1]]; j++) hits += count_decl(part[hp[n - 1], j], hp[n])
  } else {
    for (j = 1; j <= nfcls[rel]; j++) {
      k = fcls[rel, j]
      if (at >= c_line[k] && at <= c_hi[k]) hits += count_decl(k, hp[n])
    }
  }
  return (hits == 1)
}

# Counts the members of class record p declared as `name` and remembers the last in mh_rel and mh_line.
function count_decl(p, name,    i, hits) {
  hits = 0
  for (i = c_lo[p] + 1; i <= c_hi[p]; i++)
    if (d0[c_rel[p], i] == c_inner[p] && is_decl(lines[c_rel[p], i], name)) {
      hits++
      mh_rel = c_rel[p]
      mh_line = i
    }
  return hits
}

function add_entry(rel, decl, cite,    j) {
  for (j = 1; j <= nentries; j++)
    if (ent_rel[j] == rel && ent_line[j] == decl) return
  nentries++
  ent_rel[nentries] = rel
  ent_line[nentries] = decl
  ent_cite[nentries] = cite
}

function find_body(rel, start_line,    i, n, depth, started, line, stripped, c, j) {
  n = nlines[rel]
  depth = 0
  started = 0
  body_lo = 0
  body_hi = 0
  for (i = start_line; i <= n; i++) {
    line = lines[rel, i]
    stripped = strip(line)
    for (j = 1; j <= length(stripped); j++) {
      c = substr(stripped, j, 1)
      # An expression-bodied member has no block; the next brace belongs to someone else.
      if (!started && substr(stripped, j, 2) == "=>") return 0
      if (!started && c == ";") return 0
      if (c == "{") {
        if (!started) {
          started = 1
          depth = 1
          body_lo = i
          continue
        }
        depth++
      } else if (c == "}" && started) {
        depth--
        if (depth == 0) {
          body_hi = i
          return 1
        }
      }
    }
  }
  return 0
}

function keyword(method) {
  return method ~ /^(if|for|while|switch|catch|foreach|lock|using|return|sizeof|typeof|nameof|else|do|throw|try|get|set|new)$/
}

# The type written before `name` in the declaration on stripped line s, "var"
# when it is inferred, or "" when s declares no such name. member=1 reads a
# field or property, member=0 a parameter or local.
function type_in_line(s, name, member,    ty, tail) {
  if (index(s, name) == 0) return ""
  while (s ~ /<[^<>]*>/) gsub(/<[^<>]*>/, "", s)
  tail = (member ? "[[:space:]]*(;|=|\\{|$)" : "([[:space:]]*(;|=|,|\\)|\\{|$)|[[:space:]]+in[[:space:]])")
  if (!match(s, "(^|[^A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_.]*\\??[[:space:]]+" name tail)) return ""
  ty = substr(s, RSTART, RLENGTH)
  sub(/^[^A-Za-z_]+/, "", ty)
  sub(/\??[[:space:]].*/, "", ty)
  sub(/.*\./, "", ty)
  if (ty ~ /^(return|await|throw|yield|else|in|is|as|new|case|goto|using|lock|out|ref|params|not|and|or|when|default|class|struct|record|interface|enum|namespace)$/) return ""
  if (ty == "var") {
    if (match(s, "[[:space:]]" name "[[:space:]]*=[[:space:]]*new[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*")) {
      ty = substr(s, RSTART, RLENGTH)
      sub(/.*new[[:space:]]+/, "", ty)
      sub(/.*\./, "", ty)
    }
  }
  return ty
}

# The type of a parameter or local declared in lines lo..hi of rel; the last declaration wins.
function scan_decl(rel, lo, hi, name,    i, t, found) {
  found = ""
  for (i = lo; i <= hi; i++) {
    t = type_in_line(strip(lines[rel, i]), name, 0)
    if (t != "") found = t
  }
  return found
}

# The type of a field, a property or a primary-constructor parameter of one
# class declaration, or "".
function class_member(p, name,    r, i, s, t) {
  r = c_rel[p]
  for (i = c_line[p]; i <= c_hi[p]; i++) {
    s = strip(lines[r, i])
    if (i <= c_lo[p]) {
      if (i == c_line[p] && !sub(/^[^(]*\(/, "(", s)) continue
      t = type_in_line(s, name, 0)
    } else if (d0[r, i] == c_inner[p]) {
      t = type_in_line(s, name, 1)
    } else {
      continue
    }
    if (t != "") return t
  }
  return ""
}

# The type of a member of the class named nm, its other parts and its in-tree
# base classes. A member found in a base class or in a class declared in
# another file than the call site sets tv_ev to "inferred".
function member_type(nm, name, hop,    j, p, ty, nb, bs, i) {
  if (hop > 8) return ""
  for (j = 1; j <= nparts[nm]; j++) {
    p = part[nm, j]
    ty = class_member(p, name)
    if (ty != "") {
      if (hop > 0 || c_rel[p] != ev_rel) tv_ev = "inferred"
      return ty
    }
  }
  for (j = 1; j <= nparts[nm]; j++) {
    nb = split(c_base[part[nm, j]], bs, " ")
    for (i = 1; i <= nb; i++) {
      if (bs[i] == nm || !nparts[bs[i]]) continue
      ty = member_type(bs[i], name, hop + 1)
      if (ty != "") return ty
    }
  }
  return ""
}

# The declared type of `name` where the method that starts at decl_line calls it at line `at`.
function scope_type(rel, decl_line, at, name,    ty, k) {
  ty = scan_decl(rel, decl_line, at, name)
  if (ty != "") return ty
  k = class_at(rel, decl_line)
  if (!k) return ""
  return member_type(c_name[k], name, 0)
}

# The type of the receiver path parts[1..m], or "" when it cannot be told. A
# type name written at the call site (Repository.Save, Console.WriteLine) is
# its own evidence. After the first name each step reads a member of the type
# before it, and a type outside the tree ends the walk.
function receiver_type(rel, decl_line, at, parts, m, k,    ty, j) {
  j = 1
  if (parts[1] == "this") {
    if (!k) return ""
    if (m == 1) return c_name[k]
    j = 2
  }
  ty = scope_type(rel, decl_line, at, parts[j])
  if (ty == "var") return ""
  if (ty == "") {
    if (!nparts[parts[j]] && parts[j] !~ /^([A-Z]|(string|object|bool|char|byte|sbyte|short|ushort|int|uint|long|ulong|float|double|decimal)$)/) return ""
    ty = parts[j]
  }
  for (j++; j <= m; j++) {
    if (!nparts[ty]) return ty
    ty = member_type(ty, parts[j], 0)
    if (ty == "" || ty == "var") return ""
  }
  return ty
}

# Declarations of `method` among the members of the class named nm, or of its
# in-tree base classes when the class has none (then via_base is set).
function find_in_class(nm, method, hop,    j, p, i, r, nb, bs, b) {
  if (hop > 8) return
  for (j = 1; j <= nparts[nm]; j++) {
    p = part[nm, j]
    if (c_kind[p] == "interface") continue
    r = c_rel[p]
    for (i = c_lo[p] + 1; i <= c_hi[p]; i++)
      if (d0[r, i] == c_inner[p] && is_decl(lines[r, i], method)) {
        nhit++
        hit_rel[nhit] = r
        hit_line[nhit] = i
      }
  }
  if (nhit > 0) return
  for (j = 1; j <= nparts[nm]; j++) {
    nb = split(c_base[part[nm, j]], bs, " ")
    for (b = 1; b <= nb; b++) {
      if (bs[b] == nm || !nparts[bs[b]]) continue
      find_in_class(bs[b], method, hop + 1)
      if (nhit > 0) {
        via_base = 1
        return
      }
    }
  }
}

# Bind one call. A call is followed only when its receiver's declared type is
# a class in the tree that declares the method. Anything less is an unresolved
# hop with a mechanism and is never walked. Sets b_res, b_mech, b_file, b_line
# and b_follow. pre is the text before the call on its line.
function resolve_call(rel, decl_line, at, parts, n, pre,    method, k, ty) {
  method = parts[n]
  b_res = "unresolved"
  b_mech = ""
  b_file = ""
  b_line = ""
  b_follow = 0
  ev_rel = rel
  tv_ev = "same"
  k = class_at(rel, decl_line)
  if (pre ~ /(^|[^A-Za-z0-9_])new[[:space:]]*$/) {
    ty = method
  } else if (pre ~ /\.[[:space:]]*$/) {
    b_mech = "receiver-type-unknown"
    return
  } else if (n == 1) {
    if (!k) {
      b_mech = "callee-not-in-tree"
      return
    }
    ty = c_name[k]
  } else {
    ty = receiver_type(rel, decl_line, at, parts, n - 1, k)
    if (ty == "") {
      b_mech = "receiver-type-unknown"
      return
    }
  }
  if (!nconc[ty]) {
    b_mech = (nparts[ty] > 0 || ty ~ /^I[A-Z]/) ? "interface" : "external-call"
    return
  }
  if (nnp[ty] > 1) {
    b_mech = "ambiguous-method"
    return
  }
  nhit = 0
  via_base = 0
  find_in_class(ty, method, 0)
  if (nhit == 0) {
    b_mech = "callee-not-in-tree"
    return
  }
  if (nhit > 1) {
    b_mech = "ambiguous-method"
    return
  }
  b_file = hit_rel[1]
  b_line = hit_line[1]
  b_follow = 1
  b_res = (tv_ev == "inferred" || via_base) ? "inferred" : "statically-resolved"
}

function callee_has_call(rel, decl_line,    saved_lo, saved_hi, i, line, work) {
  saved_lo = body_lo
  saved_hi = body_hi
  if (!find_body(rel, decl_line)) {
    body_lo = saved_lo
    body_hi = saved_hi
    return 0
  }
  for (i = body_lo; i <= body_hi; i++) {
    if (i == decl_line) continue
    line = lines[rel, i]
    if (has_modifier(line) && line ~ /\(/) continue
    work = line
    sub(/\/\/.*/, "", work)
    if (match(work, /(await[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*(<[^>]*>)?[[:space:]]*\(/)) {
      body_lo = saved_lo
      body_hi = saved_hi
      return 1
    }
  }
  body_lo = saved_lo
  body_hi = saved_hi
  return 0
}

function add_hop(from_role, to_role, call, file, line, callee_file, callee_line, sync, resolution, mechanism, handoff) {
  nhops++
  h_from[nhops] = from_role
  h_to[nhops] = to_role
  h_call[nhops] = call
  h_file[nhops] = file
  h_line[nhops] = line
  h_cfile[nhops] = callee_file
  h_cline[nhops] = callee_line
  h_sync[nhops] = sync
  h_res[nhops] = resolution
  h_mech[nhops] = mechanism
  h_hand[nhops] = handoff
}

function walk(rel, decl_line, depth,    from_role, i, lo, hi, line, work, chunk, pre, method, n, parts, typearg, is_await, sync, resolution, mechanism, handoff, to_role, cfile, cline, follow) {
  if (seen[rel, decl_line]) return
  seen[rel, decl_line] = 1
  if (!find_body(rel, decl_line)) return
  lo = body_lo
  hi = body_hi
  from_role = role_of(rel)
  for (i = lo; i <= hi; i++) {
    line = lines[rel, i]
    if (i == decl_line) continue
    if (has_modifier(line) && line ~ /\(/) continue
    work = line
    sub(/\/\/.*/, "", work)
    gsub(/[?!]\./, ".", work)
    while (match(work, /(await[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*(<[^>]*>)?[[:space:]]*\(/)) {
      pre = substr(work, 1, RSTART - 1)
      chunk = substr(work, RSTART, RLENGTH)
      work = substr(work, RSTART + RLENGTH)
      is_await = (chunk ~ /^await[[:space:]]/)
      sub(/^await[[:space:]]+/, "", chunk)
      gsub(/[[:space:]]/, "", chunk)
      sub(/\($/, "", chunk)
      typearg = ""
      if (match(chunk, /<[^>]*>$/)) {
        typearg = substr(chunk, RSTART + 1, RLENGTH - 2)
        chunk = substr(chunk, 1, RSTART - 1)
      }
      n = split(chunk, parts, ".")
      method = parts[n]
      if (keyword(method)) continue
      if (method == "") continue
      sync = is_await ? "asynchronous" : "synchronous"
      resolution = ""
      mechanism = ""
      handoff = "no"
      to_role = "unresolved"
      cfile = ""
      cline = ""
      follow = 0
      if (method == "Publish" || method == "Send") {
        # The broker owns delivery: never resolved here, always a hand-off,
        # and asynchronous whether or not the call is awaited.
        handoff = "yes"
        to_role = "external"
        sync = "asynchronous"
        resolution = "unresolved"
        mechanism = (typearg == "" ? "dynamic-publish" : "broker")
      } else if (method == "GetRequiredService" || method == "GetService") {
        resolution = "unresolved"
        mechanism = "dependency-injection"
      } else if (method == "CreateInstance") {
        resolution = "unresolved"
        mechanism = "reflection"
      } else {
        resolve_call(rel, decl_line, i, parts, n, pre)
        resolution = b_res
        mechanism = b_mech
        if (b_follow) {
          cfile = b_file
          cline = b_line
          to_role = role_of(cfile)
          follow = 1
        }
      }
      add_hop(from_role, to_role, (typearg != "" ? method "<" typearg ">" : method), rel, i, cfile, cline, sync, resolution, mechanism, handoff)
      if (follow && cfile != "") {
        if (depth < depth_limit) walk(cfile, cline + 0, depth + 1)
        else if (callee_has_call(cfile, cline + 0)) truncated = 1
      }
    }
  }
}

function refuse(msg) {
  printf "%s\n", msg > status
  refused = 1
}

BEGIN {
  root = ENVIRON["FLOW_ROOT"]
  entry = ENVIRON["FLOW_ENTRY"]
  depth_limit = ENVIRON["FLOW_DEPTH"] + 0
  if (depth_limit <= 0) depth_limit = 5
  subject = ENVIRON["FLOW_SUBJECT"]
  generated = ENVIRON["FLOW_GENERATED_ON"]
  status = ENVIRON["FLOW_STATUS"]
  if (generated == "") generated = "unknown"
  forms = "Accepted entry forms: a route (/orders/{id}), an HTTP verb and a route (GET /orders/{id}), Type.Method (OrdersService.Handle), or a method name (Handle)."
  nhops = 0
  truncated = 0
  refused = 0
  nfiles = 0
  nentries = 0
}

{
  if ($0 != "") read_file($0)
}

END {
  if (refused) exit 3
  if (nfiles == 0) {
    refuse("refused: no tracked C# source. This adapter reads C# call sites only.")
    exit 3
  }
  spec = entry
  verb = ""
  if (match(spec, /^[A-Za-z]+[[:space:]]+/)) {
    v = toupper(substr(spec, 1, RLENGTH))
    gsub(/[[:space:]]/, "", v)
    if (v ~ /^(GET|POST|PUT|DELETE|PATCH)$/) {
      spec = substr(spec, RLENGTH + 1)
      verb = v
    }
  }
  route_entry = (index(spec, "/") > 0)
  dotted = (spec ~ /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$/)
  if (!route_entry && (verb != "" || (!dotted && spec !~ /^[A-Za-z_][A-Za-z0-9_]*$/))) {
    refuse("refused: the entry is not in an accepted form: " entry ". " forms)
    exit 3
  }
  if (dotted) {
    n = split(spec, dp, ".")
    for (j = 1; j <= nparts[dp[n - 1]]; j++) {
      p = part[dp[n - 1], j]
      if (c_kind[p] == "interface") continue
      for (i = c_lo[p] + 1; i <= c_hi[p]; i++)
        if (d0[c_rel[p], i] == c_inner[p] && is_decl(lines[c_rel[p], i], dp[n])) add_entry(c_rel[p], i, i)
    }
  } else {
    for (f = 1; f <= nfiles; f++) {
      rel = files[f]
      for (i = 1; i <= nlines[rel]; i++) {
        line = lines[rel, i]
        if (route_entry) {
          r = route_of(line)
          if (r == "" || r != spec) {
            continue
          } else if (line ~ /Map(Get|Post|Put|Delete|Patch)[[:space:]]*\(/) {
            if (!map_handler(rel, i)) {
              if (verb_ok(rel, i, i, verb)) unbound = rel ":" i
            } else if (verb_ok(rel, i, mh_line, verb)) {
              add_entry(mh_rel, mh_line, i)
            }
          } else {
            ml = method_after(rel, i)
            if (ml && verb_ok(rel, i, ml, verb)) add_entry(rel, ml, i)
          }
        } else if (is_decl(line, spec)) {
          add_entry(rel, i, i)
        }
      }
    }
  }
  if (nentries == 0 && unbound != "") {
    refuse("refused: the route's handler is a lambda or not exactly one method declaration in the tree; this adapter cannot bind it. Name the handler as Type.Method: " unbound)
    exit 3
  }
  if (nentries == 0) {
    refuse("refused: entry point not found in tracked C# source: " entry)
    exit 3
  }
  if (nentries > 1) {
    msg = "refused: entry point matches " nentries " sites:"
    for (i = 1; i <= nentries; i++)
      msg = msg " " ent_rel[i] ":" ent_cite[i]
    refuse(msg ". " forms " Use the form that matches one site; overloads and same-named types in different namespaces cannot be told apart.")
    exit 3
  }
  if (!find_body(ent_rel[1], ent_line[1] + 0)) {
    refuse("refused: the entry has no block body (expression-bodied or abstract); this adapter traces block-bodied methods only: " ent_rel[1] ":" ent_cite[1])
    exit 3
  }
  walk(ent_rel[1], ent_line[1] + 0, 1)
  printf "{\n"
  printf "  \"schema_version\": 1,\n"
  printf "  \"generated_on\": \"%s\",\n", jesc(generated)
  printf "  \"subject\": \"%s\",\n", jesc(subject)
  printf "  \"entry\": {\"name\":\"%s\",\"file\":\"%s\",\"line\":\"%s\"},\n", jesc(entry), jesc(ent_rel[1]), ent_cite[1]
  printf "  \"depth\": %d,\n", depth_limit
  printf "  \"truncated\": \"%s\",\n", (truncated ? "yes" : "no")
  if (nhops == 0) {
    printf "  \"hops\": []\n"
  } else {
    printf "  \"hops\": [\n"
    for (i = 1; i <= nhops; i++) {
      printf "    {\"from_role\":\"%s\",\"to_role\":\"%s\",\"call\":\"%s\",\"file\":\"%s\",\"line\":\"%s\",\"callee_file\":\"%s\",\"callee_line\":\"%s\",\"sync\":\"%s\",\"resolution\":\"%s\",\"mechanism\":\"%s\",\"handoff\":\"%s\"}%s\n",
        jesc(h_from[i]), jesc(h_to[i]), jesc(h_call[i]), jesc(h_file[i]), h_line[i],
        jesc(h_cfile[i]), h_cline[i], h_sync[i], h_res[i], jesc(h_mech[i]), h_hand[i],
        (i < nhops ? "," : "")
    }
    printf "  ]\n"
  }
  printf "}\n"
}
