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
}

function route_of(line,    s) {
  if (!match(line, /(Http(Get|Post|Put|Delete|Patch)|Route|Map(Get|Post|Put|Delete|Patch))[[:space:]]*\([[:space:]]*"/))
    return ""
  s = substr(line, RSTART + RLENGTH)
  if (match(s, /^[^"]*/)) return substr(s, 1, RLENGTH)
  return ""
}

function is_decl(line, name) {
  if (line !~ /(public|private|protected|internal)/) return 0
  return match(line, "(^|[^A-Za-z0-9_])" name "[[:space:]]*\\(")
}

function method_after(rel, attr_line,    i, line) {
  for (i = attr_line; i <= attr_line + 12 && i <= nlines[rel]; i++) {
    line = lines[rel, i]
    if (line ~ /(public|private|protected|internal)/ && line ~ /\(/) return i
  }
  return attr_line
}

function find_body(rel, start_line,    i, n, depth, started, line, stripped, c, j) {
  n = nlines[rel]
  depth = 0
  started = 0
  body_lo = 0
  body_hi = 0
  for (i = start_line; i <= n; i++) {
    line = lines[rel, i]
    stripped = line
    sub(/\/\/.*/, "", stripped)
    gsub(/"[^"]*"/, "\"\"", stripped)
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
  return method ~ /^(if|for|while|switch|catch|foreach|lock|using|return|sizeof|typeof|nameof|else|do|throw|try|get|set)$/
}

function recv_is_interface(rel, recv,    i, line) {
  if (recv == "") return 0
  for (i = 1; i <= nlines[rel]; i++) {
    line = lines[rel, i]
    if (index(line, recv) == 0) continue
    if (match(line, "I[A-Z][A-Za-z0-9_]*[[:space:]]+" recv "([^A-Za-z0-9_]|$)")) return 1
  }
  return 0
}

function find_methods(name,    f, rel, i, line, hits) {
  hits = 0
  for (f = 1; f <= nfiles; f++) {
    rel = files[f]
    for (i = 1; i <= nlines[rel]; i++) {
      line = lines[rel, i]
      if (is_decl(line, name)) {
        hits++
        hit_rel[hits] = rel
        hit_line[hits] = i
      }
    }
  }
  return hits
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
    if (line ~ /(public|private|protected|internal)/ && line ~ /\(/) continue
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

function walk(rel, decl_line, depth,    from_role, i, lo, hi, line, work, chunk, method, recv, typearg, n, parts, is_await, sync, resolution, mechanism, handoff, to_role, cfile, cline, hits, follow, base, saved, k) {
  if (seen[rel, decl_line]) return
  seen[rel, decl_line] = 1
  if (!find_body(rel, decl_line)) return
  lo = body_lo
  hi = body_hi
  from_role = role_of(rel)
  base = nfollow
  for (i = lo; i <= hi; i++) {
    line = lines[rel, i]
    if (i == decl_line) continue
    if (line ~ /(public|private|protected|internal)/ && line ~ /\(/) continue
    work = line
    sub(/\/\/.*/, "", work)
    while (match(work, /(await[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*(<[^>]*>)?[[:space:]]*\(/)) {
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
      recv = (n > 1 ? parts[n - 1] : "")
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
        handoff = "yes"
        to_role = "external"
        if (typearg == "") {
          resolution = "unresolved"
          mechanism = "dynamic-publish"
        } else {
          resolution = "statically-resolved"
          mechanism = "message"
        }
      } else if (method == "GetRequiredService" || method == "GetService") {
        resolution = "unresolved"
        mechanism = "dependency-injection"
      } else if (method == "CreateInstance") {
        resolution = "unresolved"
        mechanism = "reflection"
      } else if (recv_is_interface(rel, recv)) {
        resolution = "unresolved"
        mechanism = "dependency-injection"
      } else {
        hits = find_methods(method)
        if (hits == 1) {
          cfile = hit_rel[1]
          cline = hit_line[1]
          to_role = role_of(cfile)
          if (cfile == rel) resolution = "statically-resolved"
          else resolution = "inferred"
          follow = 1
        } else if (hits > 1) {
          resolution = "unresolved"
          mechanism = "ambiguous-method"
        } else {
          resolution = "unresolved"
          mechanism = "callee-not-in-tree"
        }
      }
      add_hop(from_role, to_role, (typearg != "" ? method "<" typearg ">" : method), rel, i, cfile, cline, sync, resolution, mechanism, handoff)
      if (follow && cfile != "") {
        if (depth < depth_limit) {
          nfollow++
          ffile[nfollow] = cfile
          fline[nfollow] = cline
        } else if (callee_has_call(cfile, cline + 0)) {
          truncated = 1
        }
      }
    }
  }
  saved = nfollow
  for (k = base + 1; k <= saved; k++) {
    if (!seen[ffile[k], fline[k]])
      walk(ffile[k], fline[k] + 0, depth + 1)
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
  nhops = 0
  nfollow = 0
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
  route_entry = (index(entry, "/") > 0)
  for (f = 1; f <= nfiles; f++) {
    rel = files[f]
    for (i = 1; i <= nlines[rel]; i++) {
      line = lines[rel, i]
      r = route_of(line)
      if (r != "" && r == entry) {
        nentries++
        ent_rel[nentries] = rel
        ent_line[nentries] = method_after(rel, i)
        ent_cite[nentries] = i
      } else if (!route_entry && is_decl(line, entry)) {
        nentries++
        ent_rel[nentries] = rel
        ent_line[nentries] = i
        ent_cite[nentries] = i
      }
    }
  }
  if (nentries == 0) {
    refuse("refused: entry point not found in tracked C# source: " entry)
    exit 3
  }
  if (nentries > 1) {
    msg = "refused: entry point matches " nentries " sites; name one file with a narrower entry."
    for (i = 1; i <= nentries; i++)
      msg = msg " " ent_rel[i] ":" ent_cite[i]
    refuse(msg)
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
