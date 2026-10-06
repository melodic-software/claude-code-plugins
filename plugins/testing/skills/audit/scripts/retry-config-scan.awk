# retry-config-scan.awk: the pytest, Vitest and Jest retry-setting rule engine
# for cant-fail-scan.sh, the same shape runner-config-scan.awk reports for
# Playwright: a runner told to retry a failing test reports a test that fails
# and then passes as passed, so the run stays green whatever it caught. Not a
# standalone entry point: the driver walks the tree, picks one config per
# directory in each runner's probe order, and aggregates; this program judges
# ONE file per invocation.
#
# Invocation: awk -v KIND=<pytest|vitest|jest> -v NAME=<basename> -f mask-js.awk -f retry-config-scan.awk <file>
#
# Output, tab-separated, one record per line (runner-config-scan.awk's records):
#   F <tab> flaky-passes-suite <tab> <line> <tab> <detail>  a finding
#   X <tab> flaky-passes-suite <tab> <line> <tab> <detail>  a finding exempted by a cant-fail-ok: annotation
#   D <tab> flaky-passes-suite <tab> <line> <tab> <reason>  a counted decline
#   C <tab> 1                                               the file was examined
#
# The runner facts encoded here, each with its pointer (as of 2026-10-06; recheck
# when the pointed page or changelog changes the option or its default):
#
#   pytest (KIND=pytest). pytest-rerunfailures reruns a failing test when
#   --reruns N (or --force-reruns N) is on the command line, which addopts
#   prepends, or when the ini option reruns is set; the command line wins over
#   the ini value (README "Priority"). --fail-on-flaky fails the run when a
#   test passed only on a rerun (CHANGES.rst 15.0; 15.1 fixed it to fire only
#   when reruns happened) and is a command-line option only, so addopts is the
#   one place a config file can set it (src/pytest_rerunfailures.py, the
#   addoption and addini calls). -p no:rerunfailures in addopts unloads the
#   plugin. Pointers: https://github.com/pytest-dev/pytest-rerunfailures
#   (README.rst, CHANGES.rst). The section a file holds pytest's settings in is
#   pytest's (https://docs.pytest.org/en/stable/reference/customize.html):
#   [pytest] in pytest.toml, .pytest.toml, pytest.ini, .pytest.ini and tox.ini,
#   [tool:pytest] in setup.cfg, [tool.pytest] or [tool.pytest.ini_options] in
#   pyproject.toml. The driver owns the per-directory probe order.
#
#   Vitest (KIND=vitest). test.retry is a number, or since 4.1 an object whose
#   count is the number, default 0, and Vitest has no option that fails a run
#   on a retry-earned pass (https://vitest.dev/config/retry, read 2026-10-06).
#   retry counts wherever a test key holds it: test itself, a projects[] entry's
#   test, or a tag under test.tags. A literal 0 is honored; any other value
#   fires, the Playwright engine's asymmetry: process.env.CI ? 2 : 0 cannot be
#   evaluated here and CI is where retries turn on.
#
#   Jest (KIND=jest). jest.retryTimes(n) in a test or setup file retries that
#   file's failing tests, and Jest has no option that fails a run on a
#   retry-earned pass (https://jestjs.io/docs/jest-object#jestretrytimesnumretries-options,
#   read 2026-10-06). One record per call; a literal 0 declines.
#
# Exemptions: cant-fail-ok: anywhere in a pytest or Vitest config suppresses
# its finding, the Playwright config's file scope; in a Jest file the
# annotation must sit on the call's line or the line above, because the same
# file holds test-level annotations.
#
# Design bias, load-bearing: every heuristic errs toward NOT firing. A spread
# after a Vitest retry key in the same object may override it, so that config
# declines.

BEGIN {
  nlines = 0
  exempt = 0
  EXEMPT_ERE = "cant-fail-ok:"
}

{
  raw = $0
  sub(/\r$/, "", raw)
  nlines++
  RAWL[nlines] = raw
  MASKL[nlines] = KIND == "pytest" ? raw : mask_js(raw)
  if (raw ~ EXEMPT_ERE) exempt = 1
}

END {
  if (KIND == "pytest") pytest_scan()
  else if (KIND == "vitest") vitest_scan()
  else if (KIND == "jest") jest_scan()
  else { printf "E\tunknown KIND '%s'\n", KIND; exit 2 }
  printf "C\t1\n"
}

function emit(kind, line, detail) {
  gsub(/\t/, " ", detail)
  printf "%s\tflaky-passes-suite\t%d\t%s\n", kind, line, detail
}

function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }

function is_int(v) { return v ~ /^-?[0-9]+$/ }

# ---------------------------------------------------------------------------
# pytest: INI (pytest.ini, tox.ini, setup.cfg, [tool.pytest.ini_options]) and
# native TOML ([pytest] in pytest.toml, [tool.pytest]). Both read the same two
# keys, addopts and reruns; a TOML value may be a string or an array, and may
# continue over lines (an array, a ''' or """ string); an INI value continues
# on indented lines.
# ---------------------------------------------------------------------------

function pytest_sections() {
  if (NAME == "setup.cfg") return "|tool:pytest|"
  if (NAME == "pyproject.toml") return "|tool.pytest|tool.pytest.ini_options|"
  return "|pytest|"
}

function pytest_scan(    want, i, s, in_sec, sec, key, val, kl, j, toml, n, m, t, k, vl, part, tok, tl, nt, rv, rl, fv, fl, pv, pl, src) {
  want = pytest_sections()
  toml = NAME ~ /\.toml$/
  in_sec = 0
  rv = ""; rl = 0; src = ""
  fl = 0; pl = 0
  for (i = 1; i <= nlines; i++) {
    s = RAWL[i]
    if (s ~ /^[[:space:]]*\[[^]]*\][[:space:]]*(#.*)?$/) {
      sec = s
      sub(/^[[:space:]]*\[[[:space:]]*/, "", sec)
      sub(/[[:space:]]*\].*$/, "", sec)
      gsub(/["']/, "", sec)
      in_sec = index(want, "|" sec "|") > 0
      continue
    }
    if (!in_sec) continue
    if (s ~ /^[[:space:]]*([#;]|$)/) continue
    # A key line: a name at the line start, then = (or : in an INI file).
    if (!match(s, toml ? "^[[:space:]]*[A-Za-z_][A-Za-z0-9_.-]*[[:space:]]*=" : "^[A-Za-z_][A-Za-z0-9_.-]*[[:space:]]*[=:]")) continue
    key = substr(s, 1, RLENGTH - 1)
    key = trim(key)
    val = substr(s, RLENGTH + 1)
    kl = i
    if (key != "addopts" && key != "reruns") continue
    # The value's continuation lines.
    if (toml) {
      j = i
      while (!toml_closed(val) && j < nlines) { j++; val = val "\n" RAWL[j] }
      i = j
    } else {
      while (i < nlines && RAWL[i + 1] ~ /^[[:space:]]+[^[:space:]]/ && RAWL[i + 1] !~ /^[[:space:]]*[#;]/) { i++; val = val "\n" RAWL[i] }
    }
    if (key == "reruns") {
      # The command line, which addopts extends, wins over the ini value.
      t = val
      sub(/[[:space:]]*[#;].*$/, "", t)
      t = trim(t)
      gsub(/^["']|["']$/, "", t)
      if (src != "addopts") { rv = t; rl = kl; src = "ini" }
      continue
    }
    # addopts: its tokens, with quotes, brackets and commas dropped, each
    # tagged with the line it sits on so a finding names that line.
    n = split(val, vl, "\n")
    nt = 0
    for (j = 1; j <= n; j++) {
      t = vl[j]
      if (toml) sub(/#[^"']*$/, "", t)
      gsub(/[][",']/, " ", t)
      m = split(t, part, /[[:space:]]+/)
      for (k = 1; k <= m; k++) if (part[k] != "") { nt++; tok[nt] = part[k]; tl[nt] = kl + j - 1 }
    }
    for (k = 1; k <= nt; k++) {
      if (tok[k] == "--fail-on-flaky") { fv = 1; fl = tl[k] }
      else if (tok[k] == "-pno:rerunfailures" || (tok[k] == "no:rerunfailures" && k > 1 && tok[k - 1] == "-p")) { pv = 1; pl = tl[k] }
      else if (tok[k] ~ /^--(force-)?reruns=/) { rv = tok[k]; sub(/^[^=]*=/, "", rv); rl = tl[k]; src = "addopts"; RFLAG = tok[k]; sub(/=.*/, "", RFLAG) }
      else if ((tok[k] == "--reruns" || tok[k] == "--force-reruns") && k < nt) { rv = tok[k + 1]; rl = tl[k]; src = "addopts"; RFLAG = tok[k] }
    }
  }
  if (pv) { emit("D", pl, "plugin-disabled"); return }
  if (rl == 0 || (is_int(rv) && rv + 0 <= 0)) { emit("D", rl ? rl : 1, "retries-not-configured"); return }
  if (fv) { emit("D", fl, "key-set"); return }
  if (src == "addopts") t = RFLAG " " rv " in addopts at line " rl
  else t = "reruns = " rv " at line " rl
  emit(exempt ? "X" : "F", rl, t " with --fail-on-flaky absent from addopts")
}

# A TOML value is complete when its brackets balance and no ''' or """ string
# is left open. Quoted text is skipped so a bracket inside a string is not one.
function toml_closed(v,    i, n, c, d, q, c3) {
  d = 0; q = ""; n = length(v)
  for (i = 1; i <= n; i++) {
    c = substr(v, i, 1); c3 = substr(v, i, 3)
    if (q != "") {
      if (length(q) == 3 && c3 == q) { q = ""; i += 2 }
      else if (length(q) == 1 && c == "\\" && q == "\"") i++
      else if (length(q) == 1 && c == q) q = ""
      continue
    }
    if (c3 == "'''" || c3 == "\"\"\"") { q = c3; i += 2; continue }
    if (c == "\"" || c == "'") { q = c; continue }
    if (c == "#") { while (i <= n && substr(v, i, 1) != "\n") i++; continue }
    if (c == "[" || c == "{") d++
    else if (c == "]" || c == "}") d--
  }
  return d <= 0 && q == ""
}

# ---------------------------------------------------------------------------
# Vitest: the whole file is walked, since a config may be built by
# mergeConfig or a function; { and [ open a level, and each level remembers the
# key whose value opened it, so a key's path is known. A retry key with a test
# key above it is the runner setting.
# ---------------------------------------------------------------------------

function vitest_scan(    i, j, s, rawline, c, d, seg_start, seg_colon, key, val, ve, obj, k, under, ret_n, ret_line, ret_val, ret_key, ret_obj, ret_d, fire, spread, pending) {
  d = 0; obj = 0
  ret_n = 0; ret_line = 0; ret_val = ""; fire = 0; spread = 0
  pending = ""
  OBJ[0] = 0; PARENT[0] = ""
  for (i = 1; i <= nlines; i++) {
    s = MASKL[i]
    rawline = RAWL[i]
    seg_start = 1; seg_colon = 0
    for (j = 1; j <= length(s); j++) {
      c = substr(s, j, 1)
      if (c == "{" || c == "[") {
        d++; obj++; OBJ[d] = obj; PARENT[d] = pending; pending = ""
        seg_start = j + 1; seg_colon = 0
        continue
      }
      if (c == "}" || c == "]") {
        if (d > 0) d--
        pending = ""
        seg_start = j + 1; seg_colon = 0
        continue
      }
      if (c == "," || c == ";") { pending = ""; seg_start = j + 1; seg_colon = 0; continue }
      if (substr(s, j, 3) == "...") {
        if (ret_n && d == ret_d && OBJ[d] == ret_obj) spread = 1
        j += 2; continue
      }
      if (c == ":" && !seg_colon) {
        seg_colon = 1
        key = substr(rawline, seg_start, j - seg_start)
        gsub(/[[:space:]]/, "", key)
        gsub(/['"`]/, "", key)
        if (key !~ /^[A-Za-z_$][A-Za-z0-9_$]*$/) continue
        pending = key
        under = 0
        for (k = d; k >= 1; k--) if (PARENT[k] == "test") { under = 1; break }
        if (!under) continue
        if (key == "retry" || (key == "count" && PARENT[d] == "retry")) {
          ve = value_end(s, j + 1)
          val = trim(substr(rawline, j + 1, ve - j))
          if (val == "") val = continued_value(i)
          # The object form names its count one level down.
          if (key == "retry" && val ~ /^\{/) continue
          ret_n++
          if (ret_line == 0) { ret_line = i; ret_val = val; ret_key = key == "count" ? "retry.count" : "retry" }
          ret_obj = OBJ[d]; ret_d = d
          if (!is_int(val) || val + 0 > 0) fire = 1
        }
      }
    }
  }
  if (!ret_n || !fire) { emit("D", ret_line ? ret_line : 1, "retries-not-configured"); return }
  if (spread) { emit("D", ret_line, "spread-undecidable"); return }
  val = ret_key ": " ret_val " at line " ret_line
  if (ret_n > 1) val = val "; " ret_n " retry occurrence(s)"
  emit(exempt ? "X" : "F", ret_line, val " under a test key; Vitest has no option that fails a run on a retry-earned pass")
}

function continued_value(i,   k, ve, v) {
  for (k = i + 1; k <= nlines; k++) {
    if (MASKL[k] ~ /^[[:space:]]*$/) continue
    ve = value_end(MASKL[k], 1)
    return trim(substr(RAWL[k], 1, ve))
  }
  return ""
}

function value_end(s, from,   k, n, c, ld) {
  ld = 0; n = length(s)
  for (k = from; k <= n; k++) {
    c = substr(s, k, 1)
    if (c == "{" || c == "[" || c == "(") { ld++; continue }
    if (c == "}" || c == "]" || c == ")") { if (ld == 0) return k - 1; ld--; continue }
    if (c == "," && ld == 0) return k - 1
  }
  return n
}

# ---------------------------------------------------------------------------
# Jest: each jest.retryTimes( call outside a string or comment, judged by its
# first argument.
# ---------------------------------------------------------------------------

function jest_scan(    i, s, r, ve, arg, seen, kind) {
  seen = 0
  for (i = 1; i <= nlines; i++) {
    # The masked and raw copies are cut at the same columns, so the argument is
    # located in the masked text and read from the raw one.
    s = MASKL[i]; r = RAWL[i]
    while (match(s, /(^|[^A-Za-z0-9_$.])jest[[:space:]]*\.[[:space:]]*retryTimes[[:space:]]*\(/)) {
      s = substr(s, RSTART + RLENGTH); r = substr(r, RSTART + RLENGTH)
      ve = value_end(s, 1)
      arg = trim(substr(r, 1, ve))
      seen = 1
      if (is_int(arg) && arg + 0 <= 0) { emit("D", i, "retries-not-configured"); continue }
      kind = (RAWL[i] ~ EXEMPT_ERE || (i > 1 && RAWL[i - 1] ~ EXEMPT_ERE)) ? "X" : "F"
      emit(kind, i, "jest.retryTimes(" arg ") at line " i "; Jest has no option that fails a run on a retry-earned pass")
    }
  }
  if (!seen) emit("D", 1, "retries-not-configured")
}
