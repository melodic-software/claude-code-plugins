
function mask_js(s,    out, i, c, c2, n, inclass, j, w) {
  out = ""; n = length(s); i = 1
  last_sig = ""
  while (i <= n) {
    c = substr(s, i, 1); c2 = substr(s, i, 2)
    if (S_bc) { if (c2 == "*/") { S_bc = 0; out = out "  "; i += 2 } else { out = out " "; i++ }; continue }
    if (S_tpl) {
      if (c == "\\") { out = out "  "; i += 2; continue }
      if (c == "`") { S_tpl = 0; last_sig = c }
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
    if (c == "!") {
      j = i - 2
      while (j > 0 && substr(s, j, 1) ~ /[ \t]/) j--
      w = ""
      while (j > 0 && substr(s, j, 1) ~ /[A-Za-z0-9_$]/) { w = substr(s, j, 1) w; j-- }
      if (w == "" ? substr(s, j, 1) ~ /[])]/ : w !~ /^(return|typeof|case|do|else|in|of|void|delete|throw|new|yield|await|instanceof)$/) last_sig = ")"
      else last_sig = c
    } else if (c != " " && c != "\t") last_sig = c
  }
  S_str = 0
  return out
}

function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
