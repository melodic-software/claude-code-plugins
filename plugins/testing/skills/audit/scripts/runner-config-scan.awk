BEGIN {
  nlines = 0
  exempt = 0
  EXEMPT_ERE = "cant-fail-ok:"
  DEFINE_ERE = "defineConfig[[:space:]]*(<[^(]*>)?[[:space:]]*\\("
  ALT_ERE = "export[[:space:]]+default|module[[:space:]]*\\.[[:space:]]*exports[[:space:]]*=|[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*:[[:space:]]*PlaywrightTestConfig[[:space:]]*="
}

{
  raw = $0
  sub(/\r$/, "", raw)
  nlines++
  RAWL[nlines] = raw
  MASKL[nlines] = mask_js(raw)
  if (raw ~ EXEMPT_ERE) exempt = 1
}

END {
  if (!find_anchor() || !find_brace()) {
    printf "C\t0\tno-config-object\n"
    exit 0
  }
  scan_body()
  decide()
  printf "C\t1\n"
}


function find_anchor(   i) {
  for (i = 1; i <= nlines; i++) {
    if (MASKL[i] ~ ALT_ERE && match(MASKL[i], DEFINE_ERE) > 0) {
      A_line = i; A_col = RSTART + RLENGTH; A_kind = "defineConfig"
      return 1
    }
  }
  for (i = 1; i <= nlines; i++) {
    if (match(MASKL[i], DEFINE_ERE) > 0) {
      A_line = i; A_col = RSTART + RLENGTH; A_kind = "defineConfig"
      return 1
    }
  }
  for (i = 1; i <= nlines; i++) {
    if (match(MASKL[i], ALT_ERE) > 0) {
      A_line = i; A_col = RSTART + RLENGTH; A_kind = "other"
      return 1
    }
  }
  return 0
}

function find_brace(   i, j, s, c) {
  i = A_line; j = A_col
  while (i <= nlines) {
    s = MASKL[i]
    while (j <= length(s)) {
      c = substr(s, j, 1)
      if (c != " " && c != "\t") {
        if (c == "{") { B_line = i; B_col = j; return 1 }
        return 0
      }
      j++
    }
    i++
    j = 1
  }
  return 0
}


function scan_body(   i, j, s, rawline, c, d, seg_start, seg_colon, key, val, ve, done) {
  d = 0
  spread = 0
  variadic = 0
  n_d1 = 0
  ret_n = 0
  ret_fire = 0
  ret_line = 0
  ret_val = ""
  guard_seen = 0; guard_val = ""; guard_line = 0
  only_seen = 0; only_val = ""; only_line = 0
  below_only = 0; below_guard = 0
  d1_key = ""
  C_line = 0; C_col = 0
  done = 0
  for (i = B_line; i <= nlines && !done; i++) {
    s = MASKL[i]
    rawline = RAWL[i]
    j = (i == B_line) ? B_col : 1
    seg_start = j
    seg_colon = 0
    for (; j <= length(s); j++) {
      c = substr(s, j, 1)
      if (c == "{" || c == "[") { d++; seg_start = j + 1; seg_colon = 0; continue }
      if (c == "}" || c == "]") {
        d--
        seg_start = j + 1; seg_colon = 0
        if (d <= 0) { C_line = i; C_col = j; done = 1; break }
        if (d == 1) d1_key = ""
        continue
      }
      if (c == ",") {
        seg_start = j + 1; seg_colon = 0
        if (d == 1) d1_key = ""
        continue
      }
      if (d == 1 && substr(s, j, 3) == "...") { spread = 1; j += 2; continue }
      if (c == ":" && !seg_colon) {
        seg_colon = 1
        key = substr(rawline, seg_start, j - seg_start)
        gsub(/[[:space:]]/, "", key)
        gsub(/['"`]/, "", key)
        ve = value_end(s, j + 1)
        val = trim(substr(rawline, j + 1, ve - j))
        if (key ~ /^[A-Za-z_$][A-Za-z0-9_$]*$/) {
          if (val == "") val = continued_value(i)
          record_key(key, val, d, i)
        }
      }
    }
  }
  if (A_kind == "defineConfig" && C_line > 0) check_variadic()
}

function continued_value(i,   k, ve) {
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
    if (c == "{" || c == "[") { ld++; continue }
    if (c == "}" || c == "]") { if (ld == 0) return k - 1; ld--; continue }
    if (c == "," && ld == 0) return k - 1
  }
  return n
}

function check_variadic(   i, j, s, c, seen_comma) {
  seen_comma = 0
  i = C_line; j = C_col + 1
  while (i <= nlines) {
    s = MASKL[i]
    while (j <= length(s)) {
      c = substr(s, j, 1)
      if (c != " " && c != "\t") {
        if (c == ")") return
        if (c == ",") {
          if (seen_comma) { variadic = 1; return }
          seen_comma = 1
        } else {
          if (seen_comma) variadic = 1
          return
        }
      }
      j++
    }
    i++
    j = 1
  }
}

function record_key(key, val, d, line) {
  if (d == 1) {
    n_d1++
    d1_key = key
    if (key == "retries") count_retries(val, line)
    else if (key == "failOnFlakyTests") { guard_seen = 1; guard_val = val; guard_line = line }
    else if (key == "forbidOnly") { only_seen = 1; only_val = val; only_line = line }
    return
  }
  if (key == "retries") {
    if (d == 3 && d1_key == "projects") count_retries(val, line)
    return
  }
  if (key == "failOnFlakyTests") { if (!below_guard) below_guard = line; return }
  if (key == "forbidOnly") { if (!below_only) below_only = line }
}

function count_retries(val, line) {
  ret_n++
  if (ret_line == 0) { ret_line = line; ret_val = val }
  if (val_class(val) != "int" || val + 0 > 0) ret_fire = 1
}

function val_class(v) {
  if (v == "true") return "true"
  if (v == "false") return "false"
  if (v ~ /^[0-9]+$/) return "int"
  return "expr"
}

function emit(kind, slug, line, detail) {
  gsub(/\t/, " ", detail)
  printf "%s\t%s\t%d\t%s\n", kind, slug, line, detail
}


function decide(   kind, detail) {
  kind = exempt ? "X" : "F"
  if (spread || variadic) {
    detail = spread ? "spread-undecidable" : "variadic-undecidable"
    emit("D", "flaky-passes-suite", A_line, detail)
    emit("D", "only-not-forbidden", A_line, detail)
    return
  }
  if (!ret_fire) {
    emit("D", "flaky-passes-suite", A_line, "retries-not-configured")
  } else if (guard_seen && val_class(guard_val) != "false") {
    emit("D", "flaky-passes-suite", guard_line, "key-set")
  } else if (!guard_seen && below_guard) {
    emit("D", "flaky-passes-suite", below_guard, "key-below-top-level")
  } else {
    detail = "retries: " ret_val " at line " ret_line
    if (guard_seen) detail = detail " with failOnFlakyTests: false at line " guard_line
    else detail = detail " with failOnFlakyTests absent (" n_d1 " depth-1 keys read)"
    if (ret_n > 1) detail = detail "; " ret_n " retries occurrence(s)"
    emit(kind, "flaky-passes-suite", ret_line, detail)
  }
  if (only_seen) {
    if (val_class(only_val) == "false") emit(kind, "only-not-forbidden", only_line, "forbidOnly: false at line " only_line)
    else emit("D", "only-not-forbidden", only_line, "key-set")
  } else if (below_only) {
    emit("D", "only-not-forbidden", below_only, "key-below-top-level")
  } else {
    emit(kind, "only-not-forbidden", A_line, "forbidOnly absent from the config object anchored at line " A_line " (" n_d1 " depth-1 keys read)")
  }
}
