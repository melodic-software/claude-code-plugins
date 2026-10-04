# adapter-load.awk: load test-framework adapter files for cant-fail-scan.
#
# Invocation: awk -f adapter-load.awk <adapter.yaml>...
#
# Output, tab-separated, adapters in argument order and keys in file order:
#   <id> <tab> <key> <tab> <value>    one record per scalar and per list item
# Nested keys come out dotted (detect.any_regex). An `extends: <id>` adapter
# inherits every field it does not set from that adapter.
#
# The input is a restricted YAML subset, and anything outside it exits 2 with
# `adapter-load: <file>:<line>: <reason>` on stderr:
#   - `key: value`, `key:` opening a block map or block list, dotted keys
#   - block list items `- value`, one-line flow lists `[a, 'b']`
#   - plain or single-quoted scalars ('' is a literal quote), # comments
# Every list field is a list of EREs except files (basename globs),
# equality.call2 (helper names matched as substrings), equality.receiver
# (<wrapper>.<matcher>, as in expect.toBe), equality.pipeline (literal
# matchers after a pipe, as in `Should -Be`; a space matches any run of blanks)
# and rules_off (rule slugs).
#
# language picks the lexer: js, cs, python, bash, pwsh or go. block_model is
# indent for python, brace or file for bash (file: the whole file is one test,
# for harnesses with no per-case marker), and brace for the rest. advisory:
# true keeps the adapter's findings out of the --check gate unless --strict.
# assertion.calls, mock.verify and assertion.fail also count in helpers: a
# test that calls a function defined in the same file whose body matches one
# (or throws, raises or rejects, or calls such a function) has an assertion (cant-fail-scan.awk,
# "Same-file helpers"). test_skip matches the start line (or a decorator or
# attribute above it);
# body_skip matches inside the body, as in t.Skip. assertion.idioms and
# delegation match RAW text, strings and comments included, over a window of
# three consecutive body lines, so `echo "FAIL"` then `exit 1` counts.
# assertion.async matches the start of a statement that asserts nothing unless
# it is awaited or returned; assertion.inert the start of a statement that
# looks like an assertion and never asserts. Both match masked code with its
# leading blanks removed (for go, an if statement joined onto one line).
# assertion.weak and snapshot match a whole assertion call (strings stand as
# `_`), bounded the way mock.strip is: a line whose only assertions they cover
# is a weak or a snapshot oracle (go: weak matches the joined if statement).
# assertion.exists matches, the same way, a call checking only that one named
# value exists or has a type; on a value the test constructed with new it
# checks only that the constructor did not throw. assertion.count matches a length or count check anywhere in a test body, and
# assertion.fail a call that fails the test outright, which is the assertion
# of the if or catch around it. property_markers match any raw line of a file
# whose tests derive expected values on purpose (property-based tests), and
# rules_off lists rule slugs (constant-restatement) the adapter never reports.
# No double quotes, flow maps, anchors, aliases, tags, block scalars or
# document markers. A trailing \r is stripped, so CRLF files load, and so is
# a UTF-8 byte-order mark at the start of a file.
#
# Every regex field must use the ERE subset gawk, mawk and BSD awk agree on:
# no \s \S \d \D \w \W \b \B \< \>, no backreferences, and no {n,m}
# intervals, which mawk 1.3.3 does not implement.
#
# -v EXTEND=<file> appends `<id> <tab> <field> <tab> <value>` lines to those
# adapters' list fields after extends is resolved; an unknown id or a field
# that is not a list exits 2.
#
# -v MODE=config parses testing config layers instead, in cascade order,
# with the same subset (keys may also hold - and /) and prints the merged
# config as `<key> <tab> <value>`: lists concatenate with the first occurrence
# kept, and a later layer's scalar overrides. A layer named *.md is a docs
# convention file: only the body of its one ```yaml config block is parsed
# (the opening line is those words at column 0, the body ends at the first line
# of three backticks, and lines inside any other fenced block never open one),
# with errors at the .md file's own line numbers. Two blocks, or a block never
# closed, is an error. Before the merged config it prints
# `block <tab> <file> <tab> <first body line> <tab> <last body line>` for each
# .md layer that holds a block; a .md layer with none contributes nothing. Keys: adapters.enable,
# adapters.disable, paths.include, paths.exclude, adapter_dirs (lists),
# extend.<adapter>.<list field> (validated as the adapter field is), and
# rules.<rule>: off | warn | error, where <rule> is testing/audit/rule-<slug>
# or rule-<slug> and prints as rules.<slug>, or is test-weaken-block, the
# test-weaken hook's deny switch. A glob starting with * must be single-quoted.

BEGIN {
  split("id extends language block_model advisory suppress_marker", t, " ")
  for (i in t) KIND[t[i]] = "s"
  split("files detect.any_regex test_start test_skip body_skip suite_skip additional_test_blocks assertion.calls assertion.idioms assertion.async assertion.inert assertion.weak assertion.exists assertion.count assertion.fail delegation mock.create mock.verify mock.strip snapshot property_markers rules_off equality.call2 equality.receiver equality.pipeline", t, " ")
  for (i in t) KIND[t[i]] = "l"
  split("detect assertion mock equality", t, " ")
  for (i in t) KIND[t[i]] = "m"
  split("detect.any_regex test_start test_skip body_skip suite_skip assertion.calls assertion.idioms assertion.async assertion.inert assertion.weak assertion.exists assertion.count assertion.fail delegation mock.create mock.verify mock.strip snapshot property_markers suppress_marker", t, " ")
  for (i in t) IS_RE[t[i]] = 1
  # Schema fields no engine code reads yet; accepting them would drop them silently.
  split("additional_test_blocks", t, " ")
  for (i in t) RESERVED[t[i]] = 1
  RULE_RE = "^(zero-assertion|recomputed-expectation|mock-only-oracle|inert-assertion|constant-restatement|source-text-read|conditional-assertion|recomputed-derived|snapshot-only|weak-oracle|throw-only-oracle|flaky-passes-suite|only-not-forbidden)$"
  KEY_RE = MODE == "config" ? "^[A-Za-z_][A-Za-z0-9_./-]*:" : "^[A-Za-z_][A-Za-z0-9_.]*:"
  nf = 0; nr = 0; nl = 0; ns = 0
}

function die(msg) {
  printf "adapter-load: %s:%d: %s\n", FILENAME, FNR, msg > "/dev/stderr"
  FAILED = 1
  exit 2
}

function die_file(fi, msg) {
  printf "adapter-load: %s: %s\n", F_NAME[fi], msg > "/dev/stderr"
  FAILED = 1
  exit 2
}

function die_ext(msg) {
  printf "adapter-load: %s: %s\n", EXTEND, msg > "/dev/stderr"
  exit 2
}

function portable_ere(v,    i, n, c, d) {
  n = length(v)
  for (i = 1; i <= n; i++) {
    c = substr(v, i, 1)
    if (c == "\\") {
      d = substr(v, i + 1, 1)
      if (index("sSdDwWbB<>123456789", d) > 0) die("non-portable regex escape \\" d " in: " v)
      i++
    } else if (c == "{" && substr(v, i + 1, 1) ~ /[0-9,]/) {
      die("regex interval {n,m} is not portable to mawk: " v)
    }
  }
}

# Parse one scalar token. Sets SCALAR and returns the unparsed remainder.
function scalar(s,    j, c, out) {
  if (s ~ /^'/) {
    out = ""
    for (j = 2; j <= length(s); j++) {
      c = substr(s, j, 1)
      if (c == "'") {
        if (substr(s, j + 1, 1) == "'") { out = out "'"; j++; continue }
        SCALAR = out
        return substr(s, j + 1)
      }
      out = out c
    }
    die("unterminated single-quoted scalar")
  }
  if (s ~ /^"/) die("double-quoted scalars are not supported; use single quotes")
  if (s ~ /^[&*!|>{%@`]/) die("unsupported YAML syntax (single-quote a value that starts with it): " s)
  SCALAR = s
  return ""
}

# A plain scalar on its own: drop a trailing comment and blanks.
function plain_value(s,    rest) {
  rest = scalar(s)
  if (s ~ /^'/) {
    if (rest !~ /^[ ]*(#.*)?$/) die("text after a quoted scalar: " rest)
    return SCALAR
  }
  sub(/[ ]+#.*$/, "", SCALAR)
  sub(/[ ]+$/, "", SCALAR)
  if (SCALAR ~ /: / || SCALAR ~ /:$/) die("nested mapping in a value; quote it: " SCALAR)
  return SCALAR
}

# m (map), l (list), s (scalar), or "" for an unknown key.
function kind_of(k,    f) {
  if (MODE != "config") return (k in KIND) ? KIND[k] : ""
  if (k ~ /^(adapters|paths|rules|extend)$/ || k ~ /^extend\.[A-Za-z0-9_-]+$/) return "m"
  if (k ~ /^(adapters\.(enable|disable)|paths\.(include|exclude)|adapter_dirs)$/) return "l"
  if (k ~ /^rules\.[^.]+$/) return "s"
  if (!match(k, /^extend\.[A-Za-z0-9_-]+\./)) return ""
  f = substr(k, RLENGTH + 1)
  return (f in KIND) && KIND[f] != "s" ? KIND[f] : ""
}

# A config record: lists keep the first occurrence of each item, scalars the
# last layer's value.
function cfg_add(key, v,    r) {
  if (index(v, "\t") > 0) die("tab in value of " key)
  if (key ~ /^rules\./) {
    r = substr(key, 7)
    sub(/^testing\/audit\//, "", r)
    if (r == "test-weaken-block" || r == "rule-test-weaken-block") r = "rule-test-weaken-block"
    else if (r !~ /^rule-/ || substr(r, 6) !~ RULE_RE) die("unknown rule: " substr(key, 7))
    if (v !~ /^(off|warn|error)$/) die(key " is off, warn or error, got: " v)
    r = "rules." substr(r, 6)
    if (!(r in SCAL)) SC_KEY[++ns] = r
    SCAL[r] = v
    return
  }
  if (match(key, /^extend\.[A-Za-z0-9_-]+\./)) check_value(substr(key, RLENGTH + 1), v)
  if ((key, v) in LSEEN) return
  LSEEN[key, v] = 1
  L_KEY[++nl] = key; L_VAL[nl] = v
}

function add(key, v) {
  if (kind_of(key) == "") die("unknown key: " key)
  if (kind_of(key) == "m") die(key " is a map, not a value")
  if (MODE == "config") { cfg_add(key, v); return }
  check_value(key, v)
  nr++; R_F[nr] = nf; R_K[nr] = key; R_V[nr] = v
  if (key == "id") F_ID[nf] = v
  if (key == "extends") F_EXT[nf] = v
}

function check_value(key, v) {
  if (index(v, "\t") > 0) die("tab in value of " key)
  if (key in RESERVED) die(key " is reserved and not implemented yet")
  if (key == "advisory" && v != "true" && v != "false") die("advisory is true or false, got: " v)
  # The config rules read a Playwright config, which no test adapter claims.
  if (key == "rules_off" && v !~ /^(zero-assertion|recomputed-expectation|mock-only-oracle|inert-assertion|constant-restatement|source-text-read|conditional-assertion|recomputed-derived|snapshot-only|weak-oracle|throw-only-oracle)$/)
    die("rules_off entries are test-body rule slugs such as recomputed-derived, got: " v)
  if (key == "equality.receiver" && v !~ /^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$/)
    die("equality.receiver entries are <wrapper>.<matcher>, got: " v)
  if (key in IS_RE) portable_ere(v)
}

# md_scan <line>: for a docs convention file, 1 when the line is inside the
# ```yaml config block, else 0. Tracks other fenced blocks so an example of the
# block sitting inside a longer fence never counts.
function md_scan(line,    t) {
  if (IN) {
    if (line ~ /^```[ \t]*$/) { IN = 0; B_TO[nf] = FNR - 1; return 0 }
    return 1
  }
  t = line
  sub(/^ ? ? ?/, "", t)
  if (FCH != "") {
    if (match(t, FCH == "`" ? "^`+" : "^~+") && RLENGTH >= FN && substr(t, RLENGTH + 1) ~ /^[ \t]*$/) FCH = ""
    return 0
  }
  if (line ~ /^```yaml config[ \t]*$/) {
    if (nf in B_FROM) md_die(FNR, "second config block (the first opens at line " (B_FROM[nf] - 1) ")")
    IN = 1; B_FROM[nf] = FNR + 1
    return 0
  }
  if (match(t, /^(```+|~~~+)/) && !(substr(t, 1, 1) == "`" && substr(t, RLENGTH + 1) ~ /`/)) {
    FCH = substr(t, 1, 1); FN = RLENGTH
  }
  return 0
}

function md_die(ln, msg) {
  printf "adapter-load: %s:%d: %s\n", F_NAME[nf], ln, msg > "/dev/stderr"
  FAILED = 1
  exit 2
}

function md_end(fi) {
  if (F_MD[fi] && IN) {
    nf = fi
    md_die(B_FROM[fi] - 1, "config block is never closed")
  }
}

function open_key(key) {
  if ((nf, key) in SEEN) die("duplicate key: " key)
  SEEN[nf, key] = 1
}

FNR == 1 {
  if (nf > 0) md_end(nf)
  nf++; F_NAME[nf] = FILENAME; sp = 0
  F_MD[nf] = MODE == "config" && FILENAME ~ /\.md$/
  IN = 0; FCH = ""
}

{
  line = $0
  sub(/\r$/, "", line)
  if (FNR == 1) sub(/^\357\273\277/, "", line)
  if (F_MD[nf] && !md_scan(line)) next
  if (line ~ /^[ ]*(#.*)?$/) next
  if (line ~ /^[ ]*\t/) die("tab in indentation")
  if (line ~ /^(---|\.\.\.)/) die("document markers are not supported")
  match(line, /^[ ]*/)
  ind = RLENGTH
  body = substr(line, ind + 1)

  if (body ~ /^-([ ]|$)/) {
    while (sp > 0 && S_IND[sp] > ind) sp--
    if (sp == 0) die("list item with no open key")
    key = S_KEY[sp]
    if (kind_of(key) != "l") die(key " does not take a list")
    v = substr(body, 2)
    sub(/^[ ]+/, "", v)
    if (v ~ /^\[/) die("nested list")
    add(key, plain_value(v))
    next
  }

  if (!match(body, KEY_RE)) die("expected `key: value` or `- item`")
  key = substr(body, 1, RLENGTH - 1)
  rest = substr(body, RLENGTH + 1)
  if (rest != "" && rest !~ /^ /) die("missing space after colon")
  sub(/^[ ]+/, "", rest)
  while (sp > 0 && S_IND[sp] >= ind) sp--
  # A key sits at column 0 or at the one child indent its open parent set.
  if (sp == 0 ? ind != 0 : ((sp in S_CHILD) && S_CHILD[sp] != ind)) die("bad indentation")
  if (sp > 0) { S_CHILD[sp] = ind; key = S_KEY[sp] "." key }
  if (kind_of(key) == "") die("unknown key: " key)
  open_key(key)

  if (rest ~ /^(#.*)?$/) {
    sp++; S_IND[sp] = ind; S_KEY[sp] = key
    delete S_CHILD[sp]
    next
  }
  if (rest ~ /^\[/) {
    if (kind_of(key) != "l") die(key " does not take a list")
    rest = substr(rest, 2)
    for (;;) {
      sub(/^[ ]+/, "", rest)
      if (rest ~ /^\]/) break
      if (rest ~ /^'/) {
        rest = scalar(rest)
        v = SCALAR
      } else {
        if (!match(rest, /^[^],'"[{]*/)) die("bad flow list item")
        v = substr(rest, 1, RLENGTH)
        rest = substr(rest, RLENGTH + 1)
        sub(/[ ]+$/, "", v)
        scalar(v)
        if (v == "") die("empty flow list item")
      }
      add(key, v)
      sub(/^[ ]+/, "", rest)
      if (rest ~ /^,/) { rest = substr(rest, 2); continue }
      if (rest !~ /^\]/) die("flow list must be one line of plain or single-quoted items")
    }
    if (substr(rest, 2) !~ /^[ ]*(#.*)?$/) die("text after a flow list")
    next
  }
  if (kind_of(key) != "s") die(key " takes a " (kind_of(key) == "l" ? "list" : "map") ", not a scalar")
  add(key, plain_value(rest))
}

function resolve(fi, depth,    p, j, n0) {
  if (fi in DONE) return
  if (depth > 16) die_file(fi, "extends cycle")
  if (fi in F_EXT) {
    p = BY_ID[F_EXT[fi]]
    if (p == "") die_file(fi, "extends unknown adapter: " F_EXT[fi])
    resolve(p, depth + 1)
    n0 = nr
    for (j = 1; j <= n0; j++)
      if (R_F[j] == p && R_K[j] != "id" && R_K[j] != "extends" && !((fi, R_K[j]) in SEEN)) {
        nr++; R_F[nr] = fi; R_K[nr] = R_K[j]; R_V[nr] = R_V[j]
      }
    for (j = 1; j <= n0; j++)
      if (R_F[j] == p) SEEN[fi, R_K[j]] = 1
  }
  DONE[fi] = 1
}

END {
  if (FAILED) exit 2
  if (nf > 0) md_end(nf)
  if (MODE == "config") {
    for (i = 1; i <= nf; i++)
      if (i in B_FROM) printf "block\t%s\t%d\t%d\n", F_NAME[i], B_FROM[i], B_TO[i]
    for (i = 1; i <= nl; i++) printf "%s\t%s\n", L_KEY[i], L_VAL[i]
    for (i = 1; i <= ns; i++) printf "%s\t%s\n", SC_KEY[i], SCAL[SC_KEY[i]]
    exit 0
  }
  for (fi = 1; fi <= nf; fi++) {
    if (!(fi in F_ID) || F_ID[fi] == "") die_file(fi, "no id")
    if (F_ID[fi] in BY_ID) die_file(fi, "duplicate adapter id: " F_ID[fi])
    BY_ID[F_ID[fi]] = fi
  }
  for (fi = 1; fi <= nf; fi++) resolve(fi, 0)
  while (EXTEND != "" && (getline ln < EXTEND) > 0) {
    split(ln, x, "\t")
    if (!(x[1] in BY_ID)) die_ext("extend names an unknown adapter: " x[1])
    if (!(x[2] in KIND) || KIND[x[2]] != "l") die_ext("extend." x[1] "." x[2] " is not a list field")
    nr++; R_F[nr] = BY_ID[x[1]]; R_K[nr] = x[2]; R_V[nr] = x[3]
  }
  for (fi = 1; fi <= nf; fi++) {
    lang = ""; bm = ""; hf = 0; hts = 0
    for (j = 1; j <= nr; j++) if (R_F[j] == fi) {
      if (R_K[j] == "language") lang = R_V[j]
      if (R_K[j] == "block_model") bm = R_V[j]
      if (R_K[j] == "files") hf = 1
      if (R_K[j] == "test_start") hts = 1
    }
    # A claimed file with no test matcher parses zero blocks and reads clean.
    # The file model makes the whole file one block, so it needs no matcher.
    if (hf && !hts && bm != "file") die_file(fi, "claims files but has no test_start")
    if (lang !~ /^(js|cs|python|bash|pwsh|go)$/) die_file(fi, "language must be js, cs, python, bash, pwsh or go, got: " lang)
    if (bm != "" && bm != (lang == "python" ? "indent" : "brace") && !(lang == "bash" && bm == "file"))
      die_file(fi, "block_model " bm " is not supported for language " lang)
  }
  for (fi = 1; fi <= nf; fi++)
    for (j = 1; j <= nr; j++)
      if (R_F[j] == fi) printf "%s\t%s\t%s\n", F_ID[fi], R_K[j], R_V[j]
}
