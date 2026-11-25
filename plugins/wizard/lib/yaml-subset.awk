# GENERATED from lib/yaml-subset.awk by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.

function fail(msg) {
  print "error\t" NR "\t" msg
  failed = 1
  exit 1
}

function emit(path, val) { print path "\t" val }

function dupcheck(path) {
  if (path in keyseen) fail("duplicate key `" path "` (first at line " keyseen[path] ")")
  keyseen[path] = NR
}

function ch() { return substr(FS_S, FP, 1) }

function skipws() { while (FP <= length(FS_S) && ch() ~ /[ \t]/) FP++ }

function rtrim(s,   n, c) {
  for (n = length(s); n > 0; n--) {
    c = substr(s, n, 1)
    if (c != " " && c != "\t") break
  }
  return substr(s, 1, n)
}

function uncomment(s,   i, n, c, run) {
  n = length(s); run = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == " " || c == "\t") { if (!run) run = i }
    else if (c == "#" && run) return substr(s, 1, run - 1)
    else run = 0
  }
  return s
}

function qscan(s, start,   q, v, i, n, c, e) {
  q = substr(s, start, 1); v = ""; n = length(s)
  for (i = start + 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == q) {
      if (q == "'" && substr(s, i + 1, 1) == "'") { v = v "'"; i++; continue }
      QV = v; QEND = i + 1
      return 1
    }
    if (q == "\"" && c == "\\" && i < n) {
      e = substr(s, i + 1, 1)
      if (e == "\"" || e == "\\" || e == "/") v = v e
      else if (e == "t") v = v "\t"
      else if (e == "n") v = v c e
      else fail("unsupported escape \\" e " in double-quoted string")
      i++
      continue
    }
    v = v c
  }
  return 0
}

function keyat(s,   c, r) {
  c = substr(s, 1, 1)
  if (c == "\"" || c == "'") {
    if (!qscan(s, 1)) return 0
    KEY = QV
    r = substr(s, QEND)
  } else {
    if (!match(s, /^[A-Za-z0-9_-]+/)) return 0
    KEY = substr(s, 1, RLENGTH)
    r = substr(s, RLENGTH + 1)
  }
  if (!match(r, /^[ \t]*:/)) return 0
  if (KEY == "" || KEY ~ /[.\t]/) fail("a key may not be empty or hold `.` or a tab")
  return length(s) - length(r) + RLENGTH
}

function unsupported(c) {
  if (c == "{") fail("flow mapping ({...}) is outside the subset; use block style")
  if (c ~ /[&*!|>]/) fail("anchors, aliases, tags and block scalars are not part of the subset")
}

function flow(path,   c, start) {
  skipws()
  c = ch()
  if (c == "") fail("unclosed flow collection")
  if (c == "[") fail("nested flow sequences are outside the subset")
  if (c == "\"" || c == "'") {
    if (!qscan(FS_S, FP)) fail("unclosed quote")
    emit(path, QV)
    FP = QEND
    return
  }
  unsupported(c)
  start = FP
  while (FP <= length(FS_S) && ch() !~ /[],}]/) {
    if (ch() == "#" && substr(FS_S, FP - 1, 1) ~ /[ \t]/) fail("unclosed flow collection")
    FP++
  }
  c = rtrim(substr(FS_S, start, FP - start))
  if (c == "") fail("an empty flow item")
  emit(path, c)
}

function fseq(path,   i, c) {
  FP++
  for (i = 0; ; i++) {
    skipws()
    if (ch() == "]") { FP++; return }
    flow(path "." i)
    skipws()
    c = ch()
    if (c == "]") { FP++; return }
    if (c == "") fail("unclosed flow collection")
    if (c != ",") fail("expected `,` or `]` in a flow sequence")
    FP++
  }
}

function value(path, s, ind, opener,   c, rest) {
  if (s == "" || s ~ /^#/) {
    pending = 1; ppath = path; pind = ind; ptype = opener
    return
  }
  c = substr(s, 1, 1)
  if (c == "[") {
    FS_S = s; FP = 1
    fseq(path)
    rest = substr(FS_S, FP)
  } else if (c == "\"" || c == "'") {
    if (!qscan(s, 1)) fail("unclosed quote")
    emit(path, QV)
    rest = substr(s, QEND)
  } else {
    unsupported(c)
    s = rtrim(uncomment(s))
    if (s ~ /:[ \t]/) fail("a plain value may not hold `: `; quote it")
    emit(path, s)
    return
  }
  sub(/^[ \t]+/, "", rest)
  if (rest != "" && rest !~ /^#/) fail("unexpected text after a value")
}

function mapkey(rest, ind,   key, val, path, p) {
  p = keyat(rest)
  if (!p) fail("expected `key: value`")
  key = KEY
  val = substr(rest, p + 1)
  if (val != "" && val !~ /^[ \t]/) fail("expected a space after `" key ":`")
  sub(/^[ \t]+/, "", val)
  path = (paths[n] == "" ? "" : paths[n] ".") key
  dupcheck(path)
  value(path, val, ind, "map")
}

BEGIN { inblock = (BLOCK != 1) }

{
  sub(/\r$/, "")
  if (NR == 1) sub(/^\357\273\277/, "")
  line = $0
  if (BLOCK == 1) {
    if (!inblock) {
      if (other != "") {
        if (line ~ /^`+[ \t]*$/ && match(line, /^`+/) && RLENGTH >= length(other)) other = ""
        next
      }
      if (line ~ /^```yaml[ \t]+config[ \t]*$/) {
        if (seen) fail("a second ```yaml config block (the first opens at line " first "); one file holds one")
        inblock = 1; seen = 1; first = NR; print "block\t1"
      } else if (match(line, /^```+/)) {
        other = substr(line, 1, RLENGTH)
      }
      next
    }
    if (line ~ /^```[ \t]*$/) { inblock = 0; done = 1; next }
  }
  if (line ~ /^[ \t]*(#.*)?$/) next
  if (line ~ /^(---|\.\.\.)/) fail("document markers are outside the subset")
  if (line ~ /^%/) fail("directives (`%`) are outside the subset")

  match(line, /^[ \t]*/)
  if (BLOCK != 1 && substr(line, 1, RLENGTH) ~ /\t/) fail("tab indentation")
  if (!based) { base = substr(line, 1, RLENGTH); based = 1 }
  if (substr(line, 1, length(base)) != base) fail("indentation below the document's base")
  line = substr(line, length(base) + 1)
  if (line ~ /^ *\t/) fail("tab indentation")
  match(line, /^ */)
  ind = RLENGTH
  rest = substr(line, ind + 1)
  dash = (rest ~ /^-( |$)/)

  if (n == 0) {
    if (dash) fail("a root sequence is not part of the subset")
    n = 1; inds[1] = 0; types[1] = "map"; paths[1] = ""
  }
  if (pending) {
    if (ind > pind || (ind == pind && dash && ptype == "map")) {
      n++; inds[n] = ind; types[n] = dash ? "seq" : "map"; paths[n] = ppath; cnt[n] = 0
    }
    pending = 0
  }
  while (n > 1 && (ind < inds[n] || (ind == inds[n] && types[n] == "seq" && !dash))) n--
  if (ind != inds[n]) fail("unexpected indentation")

  if (types[n] == "map") { mapkey(rest, ind); next }

  if (!dash) fail("expected a `- ` sequence item")
  path = paths[n] "." cnt[n]
  cnt[n]++
  item = substr(rest, 2)
  sub(/^ +/, "", item)
  if (item ~ /^-( |$)/) fail("a sequence nested on one line is not part of the subset")
  p = keyat(item)
  if (p && substr(item, p + 1, 1) ~ /^([ \t])?$/) {
    n++; inds[n] = ind + 2; types[n] = "map"; paths[n] = path
    mapkey(item, ind + 2)
  } else {
    value(path, item, ind, "seq")
  }
}

END {
  if (failed) exit 1
  if (BLOCK == 1 && inblock && !done) { print "error\t" NR "\tunclosed ```yaml config fence"; exit 1 }
}
