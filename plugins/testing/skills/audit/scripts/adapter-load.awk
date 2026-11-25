
function set_kind(names, kind,    t, i, n) {
  n = split(names, t, " ")
  for (i = 1; i <= n; i++) KIND[t[i]] = kind
}

BEGIN {
  set_kind("id extends language block_model advisory suppress_marker", "s")
  set_kind("files claim_by_content.files claim_by_content.any_regex detect.any_regex test_start test_skip body_skip suite_skip additional_test_blocks assertion.calls assertion.idioms assertion.async assertion.inert assertion.weak assertion.exists assertion.count assertion.fail delegation mock.create mock.verify mock.strip snapshot property_markers rules_off equality.call2 equality.receiver equality.pipeline", "l")
  set_kind("claim_by_content detect assertion mock equality", "m")
  for (k in KIND)
    if (KIND[k] == "l" && k !~ /^(files|claim_by_content\.files|rules_off|equality\..+)$/) IS_RE[k] = 1
  IS_RE["suppress_marker"] = 1
  RESERVED["additional_test_blocks"] = 1
  BODY_RULES = "zero-assertion|recomputed-expectation|mock-only-oracle|inert-assertion|constant-restatement|source-text-read|conditional-assertion|recomputed-derived|snapshot-only|weak-oracle|throw-only-oracle"
  RULE_RE = "^(" BODY_RULES "|flaky-passes-suite|only-not-forbidden)$"
  RULES_OFF_RE = "^(" BODY_RULES ")$"
  KEY_RE = MODE == "config" ? "^[A-Za-z_][A-Za-z0-9_./-]*:" : "^[A-Za-z_][A-Za-z0-9_.]*:"
  nf = 0; nr = 0; nl = 0; ns = 0
}

function fail(where, msg) {
  printf "adapter-load: %s: %s\n", where, msg > "/dev/stderr"
  FAILED = 1
  exit 2
}

function die(msg) { fail(FILENAME ":" FNR, msg) }
function die_file(fi, msg) { fail(F_NAME[fi], msg) }
function die_ext(msg) { fail(EXTEND, msg) }
function md_die(ln, msg) { fail(F_NAME[nf] ":" ln, msg) }

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

function plain_value(s,    rest) {
  rest = scalar(s)
  if (s ~ /^'/) {
    if (rest !~ /^[ ]*(#.*)?$/) die("text after a quoted scalar: " rest)
    return SCALAR
  }
  sub(/[ ]+#.*$/, "", SCALAR)
  sub(/[ ]+$/, "", SCALAR)
  if (SCALAR ~ /:( |$)/) die("nested mapping in a value; quote it: " SCALAR)
  return SCALAR
}

function kind_of(k,    f) {
  if (MODE != "config") return (k in KIND) ? KIND[k] : ""
  if (k ~ /^(adapters|paths|rules|extend)$/ || k ~ /^extend\.[A-Za-z0-9_-]+$/) return "m"
  if (k ~ /^(adapters\.(enable|disable)|paths\.(include|exclude)|adapter_dirs|project_kinds)$/) return "l"
  if (k ~ /^rules\.[^.]+$/) return "s"
  if (!match(k, /^extend\.[A-Za-z0-9_-]+\./)) return ""
  f = substr(k, RLENGTH + 1)
  return (f in KIND) && KIND[f] != "s" ? KIND[f] : ""
}

function cfg_add(key, v,    r) {
  if (index(v, "\t") > 0) die("tab in value of " key)
  if (key ~ /^rules\./) {
    r = substr(key, 7)
    sub(/^testing\/audit\//, "", r)
    if (r ~ /^(rule-)?test-weaken-block$/) r = "rule-test-weaken-block"
    else if (r !~ /^rule-/ || substr(r, 6) !~ RULE_RE) die("unknown rule: " substr(key, 7))
    if (v !~ /^(off|warn|error)$/) die(key " is off, warn or error, got: " v)
    r = "rules." substr(r, 6)
    if (!(r in SCAL)) SC_KEY[++ns] = r
    SCAL[r] = v
    return
  }
  if (key == "project_kinds" && v !~ /^[^=]+=(unit|integration|functional|architecture|live|operational)$/)
    die("project_kinds entries are <glob>=<kind> with kind unit, integration, functional, architecture, live or operational, got: " v)
  if (match(key, /^extend\.[A-Za-z0-9_-]+\./)) check_value(substr(key, RLENGTH + 1), v)
  if ((key, v) in LSEEN) return
  LSEEN[key, v] = 1
  L_KEY[++nl] = key; L_VAL[nl] = v
}

function add(key, v,    k) {
  k = kind_of(key)
  if (k == "") die("unknown key: " key)
  if (k == "m") die(key " is a map, not a value")
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
  if (key == "claim_by_content.any_regex" && v == "") die("empty claim_by_content.any_regex item")
  if (key == "rules_off" && v !~ RULES_OFF_RE)
    die("rules_off entries are test-body rule slugs such as recomputed-derived, got: " v)
  if (key == "equality.receiver" && v !~ /^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$/)
    die("equality.receiver entries are <wrapper>.<matcher>, got: " v)
  if (key in IS_RE) portable_ere(v)
}

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

function md_end(fi) {
  if (F_MD[fi] && IN) fail(F_NAME[fi] ":" (B_FROM[fi] - 1), "config block is never closed")
}

function open_key(key) {
  if ((nf, key) in SEEN) die("duplicate key: " key)
  SEEN[nf, key] = 1
}

FNR == 1 {
  if (nf > 0) md_end(nf)
  nf++; F_NAME[nf] = FILENAME; sp = 0; E2E_KEY = ""
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

  if (E2E_KEY != "") {
    if (ind > 0 || body ~ /^-([ ]|$)/) {
      if (!E2E_WARNED) {
        printf "adapter-load: %s:%d: warning: %s holds a nested value; the scan skips it\n", F_NAME[nf], FNR, E2E_KEY > "/dev/stderr"
        E2E_WARNED = 1
      }
      next
    }
    E2E_KEY = ""
  }

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
  if (MODE == "config" && ind == 0 && key ~ /^(e2e_driver|reuse_running_instance|feature_map_dir|browser_driver|map_unit|map_entry_points|map_report_order|file_findings|file_findings_floor|tdd_refactor_step|first_test|pixel_tolerance|verification|verification_skills)$/) {
    sp = 0
    E2E_KEY = key; E2E_WARNED = (key == "pixel_tolerance" || key == "verification_skills")
    next
  }
  rest = substr(body, RLENGTH + 1)
  if (rest != "" && rest !~ /^ /) die("missing space after colon")
  sub(/^[ ]+/, "", rest)
  while (sp > 0 && S_IND[sp] >= ind) sp--
  if (sp == 0 ? ind != 0 : ((sp in S_CHILD) && S_CHILD[sp] != ind)) die("bad indentation")
  if (sp > 0) { S_CHILD[sp] = ind; key = S_KEY[sp] "." key }
  kind = kind_of(key)
  if (kind == "") die("unknown key: " key)
  open_key(key)

  if (rest ~ /^(#.*)?$/) {
    sp++; S_IND[sp] = ind; S_KEY[sp] = key
    delete S_CHILD[sp]
    next
  }
  if (rest ~ /^\[/) {
    if (kind != "l") die(key " does not take a list")
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
  if (kind != "s") die(key " takes a " (kind == "l" ? "list" : "map") ", not a scalar")
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
    lang = ""; bm = ""; hf = 0; hts = 0; hcf = 0; hcr = 0
    for (j = 1; j <= nr; j++) if (R_F[j] == fi) {
      if (R_K[j] == "language") lang = R_V[j]
      if (R_K[j] == "block_model") bm = R_V[j]
      if (R_K[j] == "files") hf = 1
      if (R_K[j] == "claim_by_content.files") hf = hcf = 1
      if (R_K[j] == "claim_by_content.any_regex") hcr = 1
      if (R_K[j] == "test_start") hts = 1
    }
    if (hcf != hcr) die_file(fi, "claim_by_content needs both files and any_regex")
    if (hf && !hts && bm != "file") die_file(fi, "claims files but has no test_start")
    if (lang !~ /^(js|cs|python|bash|pwsh|go)$/) die_file(fi, "language must be js, cs, python, bash, pwsh or go, got: " lang)
    if (bm != "" && bm != (lang == "python" ? "indent" : "brace") && !(lang == "bash" && bm == "file"))
      die_file(fi, "block_model " bm " is not supported for language " lang)
  }
  for (fi = 1; fi <= nf; fi++)
    for (j = 1; j <= nr; j++)
      if (R_F[j] == fi) printf "%s\t%s\t%s\n", F_ID[fi], R_K[j], R_V[j]
}
