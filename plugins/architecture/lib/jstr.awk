# String value of one key in a one-object-per-line JSON record, shared by
# collect-containers, render-containers and render-context.
#
# Functions only. Callers prepend this file to their own awk program, either as
# an awk -f argument or as the text of the program string.
#
# jstr(line, key) returns the string value of the first "key" in line with \n
# and \t decoded and any other escaped character taken literally, or "" when
# the key is absent or its value is not a string.
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
