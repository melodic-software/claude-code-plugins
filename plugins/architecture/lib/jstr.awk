function jstr(line, key,    pat, i, rest, out, c, n) {
  pat = "\"" key "\""
  i = index(line, pat)
  if (i == 0) return ""
  rest = substr(line, i + length(pat))
  if (!sub(/^[[:space:]]*:[[:space:]]*"/, "", rest)) return ""
  out = ""
  n = length(rest)
  i = 1
  while (i <= n) {
    c = substr(rest, i, 1)
    if (c == "\\") {
      i++
      c = substr(rest, i, 1)
      if (c == "n") out = out "\n"
      else if (c == "t") out = out "\t"
      else out = out c
      i++
      continue
    }
    if (c == "\"") return out
    out = out c
    i++
  }
  return out
}
