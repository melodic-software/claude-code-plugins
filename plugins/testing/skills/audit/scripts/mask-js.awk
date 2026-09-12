# mask-js.awk: the shared length-preserving JavaScript/TypeScript masker.
# Function only. No BEGIN block, no main block, no helpers, so it composes with
# any engine that loads it.
#
# Invocation: awk -f mask-js.awk -f <engine>.awk <file>. POSIX awk concatenates
# repeated -f programs, and this file is listed first so the engine's own
# BEGIN and main blocks stay in charge.
#
# Both engines beside it need the same masker. cant-fail-scan.awk masks test
# bodies; runner-config-scan.awk masks Playwright configs whose string values
# carry braces (testMatch: '**/*.{spec,test}.ts', snapshotPathTemplate). One
# copy, because drifting copies of a regex-vs-division heuristic are a defect
# neither engine can see.
#
# Masking replaces string and comment interiors with spaces and preserves
# LENGTH, so a token match or brace count over the masked text indexes the raw
# line at the same columns.
#
# State: S_bc (block comment), S_tpl (template literal), S_str with S_q (quoted
# string), and last_sig (last significant code character, the regex-vs-division
# context) are file-scoped awk globals. The function resets last_sig on every
# line, because neither a regex literal nor the operator before it spans lines,
# and clears S_str at the end of every line, because ' and " never span lines.
# S_bc and S_tpl deliberately persist across lines: those two constructs do.
#
# The caller strips a trailing \r before calling, so the masker never sees one.

function mask_js(s,    out, i, c, c2, n, inclass) {
  out = ""; n = length(s); i = 1
  last_sig = ""  # per line: a regex literal cannot span lines, nor can the operator before it
  while (i <= n) {
    c = substr(s, i, 1); c2 = substr(s, i, 2)
    if (S_bc) { if (c2 == "*/") { S_bc = 0; out = out "  "; i += 2 } else { out = out " "; i++ }; continue }
    if (S_tpl) {
      if (c == "\\") { out = out "  "; i += 2; continue }
      if (c == "`") { S_tpl = 0; out = out " "; i++; last_sig = "`"; continue }
      out = out " "; i++; continue
    }
    if (S_str) {
      if (c == "\\") { out = out "  "; i += 2; continue }
      if (c == S_q) { S_str = 0; last_sig = c }
      out = out " "; i++; continue
    }
    if (c2 == "//") { while (i <= n) { out = out " "; i++ }; continue }
    if (c2 == "/*") { S_bc = 1; out = out "  "; i += 2; continue }
    if (c == "'" || c == "\"") { S_str = 1; S_q = c; out = out " "; i++; continue }
    if (c == "`") { S_tpl = 1; out = out " "; i++; continue }
    if (c == "/") {
      # Regex literal, decided by what precedes it: after an operator or opening
      # delimiter a '/' cannot be division. Mask through the closing '/', where
      # '/' inside a [...] class is literal and '\' escapes; flags follow. An
      # unterminated candidate masks to end of line — a string-ish context
      # either way. Wrongly reading division as a regex would mask real code,
      # so the trigger set stays narrow (no '>', no keyword heuristics).
      if (last_sig == "" || index("(,=:[!&?;{|", last_sig) > 0) {
        out = out " "; i++
        inclass = 0
        while (i <= n) {
          c = substr(s, i, 1)
          if (c == "\\") { out = out "  "; i += 2; continue }
          if (c == "[") inclass = 1
          else if (c == "]") inclass = 0
          else if (c == "/" && !inclass) {
            out = out " "; i++
            while (i <= n && substr(s, i, 1) ~ /[a-z]/) { out = out " "; i++ }
            break
          }
          out = out " "; i++
        }
        last_sig = "/"
        continue
      }
    }
    out = out c; i++
    if (c != " " && c != "\t") last_sig = c
  }
  S_str = 0  # ' and " never span lines
  return out
}
