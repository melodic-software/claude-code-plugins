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
# test_skip matches the start line (or a decorator or attribute above it);
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
# assertion.count matches a length or count check anywhere in a test body, and
# assertion.fail a call that fails the test outright, which is the assertion
# of the if or catch around it. property_markers match any raw line of a file
# whose tests derive expected values on purpose (property-based tests), and
# rules_off lists rule slugs (constant-restatement) the adapter never reports.
# No double quotes, flow maps, anchors, aliases, tags, block scalars or
# document markers. A trailing \r is stripped, so CRLF files load.
#
# Every regex field must use the ERE subset gawk, mawk and BSD awk agree on:
# no \s \S \d \D \w \W \b \B \< \>, no backreferences, and no {n,m}
# intervals, which mawk 1.3.3 does not implement.

BEGIN {
  split("id extends language block_model advisory suppress_marker", t, " ")
  for (i in t) KIND[t[i]] = "s"
  split("files detect.any_regex test_start test_skip body_skip suite_skip additional_test_blocks assertion.calls assertion.idioms assertion.async assertion.inert assertion.weak assertion.count assertion.fail delegation mock.create mock.verify mock.strip snapshot property_markers rules_off equality.call2 equality.receiver equality.pipeline", t, " ")
  for (i in t) KIND[t[i]] = "l"
  split("detect assertion mock equality", t, " ")
  for (i in t) KIND[t[i]] = "m"
  split("detect.any_regex test_start test_skip body_skip suite_skip assertion.calls assertion.idioms assertion.async assertion.inert assertion.weak assertion.count assertion.fail delegation mock.create mock.verify mock.strip snapshot property_markers suppress_marker", t, " ")
  for (i in t) IS_RE[t[i]] = 1
  # Schema fields no engine code reads yet; accepting them would drop them silently.
  split("additional_test_blocks", t, " ")
  for (i in t) RESERVED[t[i]] = 1
  nf = 0; nr = 0
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
  if (s ~ /^[&*!|>{%@`]/) die("unsupported YAML syntax: " s)
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

function add(key, v) {
  if (!(key in KIND)) die("unknown key: " key)
  if (KIND[key] == "m") die(key " is a map, not a value")
  if (index(v, "\t") > 0) die("tab in value of " key)
  if (key in RESERVED) die(key " is reserved and not implemented yet")
  if (key == "advisory" && v != "true" && v != "false") die("advisory is true or false, got: " v)
  # The config rules read a Playwright config, which no test adapter claims.
  if (key == "rules_off" && v !~ /^(zero-assertion|recomputed-expectation|mock-only-oracle|inert-assertion|constant-restatement|source-text-read|conditional-assertion|recomputed-derived|snapshot-only|weak-oracle)$/)
    die("rules_off entries are test-body rule slugs such as recomputed-derived, got: " v)
  if (key == "equality.receiver" && v !~ /^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$/)
    die("equality.receiver entries are <wrapper>.<matcher>, got: " v)
  if (key in IS_RE) portable_ere(v)
  nr++; R_F[nr] = nf; R_K[nr] = key; R_V[nr] = v
  if (key == "id") F_ID[nf] = v
  if (key == "extends") F_EXT[nf] = v
}

function open_key(key) {
  if ((nf, key) in SEEN) die("duplicate key: " key)
  SEEN[nf, key] = 1
}

FNR == 1 { nf++; F_NAME[nf] = FILENAME; sp = 0 }

{
  line = $0
  sub(/\r$/, "", line)
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
    if (KIND[key] != "l") die(key " does not take a list")
    v = substr(body, 2)
    sub(/^[ ]+/, "", v)
    if (v ~ /^\[/) die("nested list")
    add(key, plain_value(v))
    next
  }

  if (!match(body, /^[A-Za-z_][A-Za-z0-9_.]*:/)) die("expected `key: value` or `- item`")
  key = substr(body, 1, RLENGTH - 1)
  rest = substr(body, RLENGTH + 1)
  if (rest != "" && rest !~ /^ /) die("missing space after colon")
  sub(/^[ ]+/, "", rest)
  while (sp > 0 && S_IND[sp] >= ind) sp--
  # A key sits at column 0 or at the one child indent its open parent set.
  if (sp == 0 ? ind != 0 : ((sp in S_CHILD) && S_CHILD[sp] != ind)) die("bad indentation")
  if (sp > 0) { S_CHILD[sp] = ind; key = S_KEY[sp] "." key }
  if (!(key in KIND)) die("unknown key: " key)
  open_key(key)

  if (rest ~ /^(#.*)?$/) {
    sp++; S_IND[sp] = ind; S_KEY[sp] = key
    delete S_CHILD[sp]
    next
  }
  if (rest ~ /^\[/) {
    if (KIND[key] != "l") die(key " does not take a list")
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
  if (KIND[key] != "s") die(key " takes a " (KIND[key] == "l" ? "list" : "map") ", not a scalar")
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
  for (fi = 1; fi <= nf; fi++) {
    if (!(fi in F_ID) || F_ID[fi] == "") die_file(fi, "no id")
    if (F_ID[fi] in BY_ID) die_file(fi, "duplicate adapter id: " F_ID[fi])
    BY_ID[F_ID[fi]] = fi
  }
  for (fi = 1; fi <= nf; fi++) resolve(fi, 0)
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
