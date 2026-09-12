# runner-config-scan.awk: the Playwright runner-config rule engine for
# cant-fail-scan.sh. Not a standalone entry point: the driver resolves the scan
# root, walks the tree, picks one config per directory, and aggregates; this
# program judges ONE Playwright config per invocation.
#
# Invocation: awk -f mask-js.awk -f runner-config-scan.awk <file>
#
# Output, tab-separated, one record per line:
#   F <tab> <rule-slug> <tab> <line> <tab> <detail>  a finding
#   X <tab> <rule-slug> <tab> <line> <tab> <detail>  a finding exempted by a cant-fail-ok: annotation
#   D <tab> <rule-slug> <tab> <line> <tab> <reason>  a counted decline whose evidence is present in the file
#   C <tab> 1                                        a config object was examined (the denominator increment)
#   C <tab> 0 <tab> no-config-object                 enumerated, not examined: a coverage boundary, not a decline
#   E <tab> <message>                                engine error
#
# Rule slugs: flaky-passes-suite | only-not-forbidden. The driver owns the
# qualified rule-id form and the thresholds' prose.
#
# The Playwright facts this engine encodes, each with the record it rests on
# (the topic's verification records, verified against Playwright v1.63.0 as of
# 2026-09-11):
#
#   Filenames and probe order (VR-8). The runner probes playwright.config with
#   .ts, .js, .mts, .mjs, .cts, .cjs in ONE directory and takes the first match,
#   with no parent-directory walk. The driver owns that walk; this engine reads
#   whatever single file it is handed.
#
#   failOnFlakyTests (VR-1). A top-level TestConfig boolean, default false. When
#   it is true, a run containing a flaky test is reported failed and exits 1.
#   Absent or false, a test that fails and passes on a retry leaves the run
#   green, which is the shape rule 1 reports.
#
#   forbidOnly (VR-6). A top-level TestConfig boolean, default false. When it is
#   true, a committed test.only fails the run instead of silently shrinking the
#   suite to that one passing test, which is the shape rule 2 reports.
#
#   retries (VR-3). Defaults to 0. An absent key resolves to 0 and a literal 0
#   is honoured at whichever level it is written, so a provable zero is proof
#   the flaky shape is out of reach.
#
#   Where each key counts (VR-10). retries is both a TestConfig and a
#   TestProject option, so it is read at depth 1 and inside projects[] entries,
#   and nowhere else: a retries key in reporter or plugin options is not a
#   runner retry setting. forbidOnly and failOnFlakyTests are TestConfig-only,
#   so only a depth-1 occurrence is read as set. Deeper, the engine reports the
#   placement as a counted decline naming the line and makes no claim about what
#   the run does.
#
# The asymmetry between the three keys is deliberate. retries is safe only when
# provably zero, so an expression fires (VR-3): the engine cannot evaluate
# process.env.CI ? 2 : 0, and CI is exactly where retries turn on. The two
# boolean guards are safe when provably set, so an expression passes (VR-7):
# forbidOnly: !!process.env.CI is the documented scaffold idiom, and firing on
# it would cost the detector its audience.
#
# Design bias, load-bearing: every heuristic errs toward NOT firing. A token
# that may override whatever was read (a depth-1 spread, a second defineConfig
# argument) declines both rules for the whole config, and the token itself is
# the evidence. A config whose object literal cannot be anchored is reported as
# enumerated and not examined, never judged and never declined.

BEGIN {
  nlines = 0
  exempt = 0
  EXEMPT_ERE = "cant-fail-ok:"
  # Anchor priority, in three passes (find_anchor). A defineConfig( call on a
  # line that also carries an export token wins, because that is the object the
  # runner loads and a helper defineConfig assigned to a local name above it is
  # not. Any defineConfig( comes next, because export default defineConfig({
  # carries both anchors and reading "export default" first would see the
  # identifier defineConfig as the next token and wrongly report no config
  # object. An export token alone is last.
  #
  # The generic argument is matched as <[^(]*> rather than <[^<>]*>, so a nested
  # type argument (defineConfig<Options<Extra>>) still anchors; the call's own
  # paren is what bounds the match.
  DEFINE_ERE = "defineConfig[[:space:]]*(<[^(]*>)?[[:space:]]*\\("
  ALT_ERE = "export[[:space:]]+default|module[[:space:]]*\\.[[:space:]]*exports[[:space:]]*=|[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*:[[:space:]]*PlaywrightTestConfig[[:space:]]*="
}

# The engine strips its own \r: a Windows checkout must read the same keys and
# values as a POSIX one, and the shared masker never sees a carriage return.
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

# ---------------------------------------------------------------------------
# Anchoring
# ---------------------------------------------------------------------------

function find_anchor(   i) {
  # The exported defineConfig call, when one is on an export line. The ~ test
  # runs first and leaves RSTART alone, so the match() that follows is the one
  # that sets the anchor column.
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

# The config object's { must be the NEXT non-blank token after the anchor, on
# the anchor's line or the next non-blank line. Any other token (an identifier
# in defineConfig(baseConfig), a re-exported name in export default config)
# means there is no object literal to read, and a later unrelated { is never
# adopted as one.
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

# ---------------------------------------------------------------------------
# Body scan. Depth 0 before the config {; { and [ increment, } and ] decrement;
# parentheses and angle brackets do not count, so a call or a generic argument
# never moves a key's level. Config keys sit at depth 1 and a projects[] entry's
# keys at depth 3.
# ---------------------------------------------------------------------------

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
        # Back at depth 1 means the depth-1 entry's value has closed, so the
        # projects context it opened ends with it. Without this, a key the
        # engine cannot read (its colon on another line) would leave the stale
        # context in place and a deeper retries under the NEXT key would count
        # as a per-project one.
        if (d == 1) d1_key = ""
        continue
      }
      if (c == ",") {
        seg_start = j + 1; seg_colon = 0
        if (d == 1) d1_key = ""
        continue
      }
      # A spread counts only at depth 1: there it may override any key read,
      # while deeper it belongs to one option's value (the scaffold's
      # use: { ...devices[...] }) and decides nothing about the two guards.
      if (d == 1 && substr(s, j, 3) == "...") { spread = 1; j += 2; continue }
      if (c == ":" && !seg_colon) {
        seg_colon = 1
        # The masker blanks a quoted key entirely, so the key is LOCATED by the
        # masked colon and READ from the raw line at the same columns.
        key = substr(rawline, seg_start, j - seg_start)
        gsub(/[[:space:]]/, "", key)
        gsub(/['"`]/, "", key)
        ve = value_end(s, j + 1)
        val = substr(rawline, j + 1, ve - j)
        sub(/^[[:space:]]+/, "", val)
        sub(/[[:space:]]+$/, "", val)
        # A colon separates a key from its value only when what sits left of it
        # is an identifier (a quoted key is one once the quotes are stripped).
        # A value continued onto the next line leaves its ternary colon behind,
        # and reading that as a key would invent an option and inflate the
        # depth-1 key count the absent-guard detail reports.
        if (key ~ /^[A-Za-z_$][A-Za-z0-9_$]*$/) record_key(key, val, d, i)
      }
    }
  }
  if (A_kind == "defineConfig" && C_line > 0) check_variadic()
}

# End of the value that starts at s[from]: the next , } or ] at the value's own
# depth, else end of line. A trailing } or ] belongs to the enclosing object, so
# module.exports = { retries: 2 }; reads the value 2, not "2 };".
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

# A second defineConfig argument may override anything the first object said, so
# it declines both rules. Scanning stops at the call's closing paren, and a
# trailing comma with nothing after it is not a second argument.
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
    else if (key == "failOnFlakyTests") { if (!guard_seen) { guard_seen = 1; guard_val = val; guard_line = line } }
    else if (key == "forbidOnly") { if (!only_seen) { only_seen = 1; only_val = val; only_line = line } }
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

# ---------------------------------------------------------------------------
# Rule decisions. Made here so the driver stays an aggregator.
# ---------------------------------------------------------------------------

function decide(   kind, detail) {
  kind = exempt ? "X" : "F"
  if (spread) {
    emit("D", "flaky-passes-suite", A_line, "spread-undecidable")
    emit("D", "only-not-forbidden", A_line, "spread-undecidable")
    return
  }
  if (variadic) {
    emit("D", "flaky-passes-suite", A_line, "variadic-undecidable")
    emit("D", "only-not-forbidden", A_line, "variadic-undecidable")
    return
  }
  if (!ret_fire) {
    emit("D", "flaky-passes-suite", A_line, "retries-not-configured")
  } else if (guard_seen && val_class(guard_val) != "false") {
    emit("D", "flaky-passes-suite", guard_line, "key-set")
  } else if (!guard_seen && below_guard) {
    # The key has no runtime effect where it sits, and the misplacement is not
    # itself a claim about the run, so the rule declines rather than fires.
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
