# One JSON string value per "key": "value" on a line. Prepend redact-connection.awk.
# The raw value is passed only into redact_shape, which prints the host shape.
{
  s = $0
  while (match(s, /"[A-Za-z_][A-Za-z0-9_.-]*"[[:space:]]*:[[:space:]]*"/)) {
    key = substr(s, RSTART + 1)
    key = substr(key, 1, index(key, "\"") - 1)
    rest = substr(s, RSTART + RLENGTH)
    val = ""
    i = 1
    n = length(rest)
    while (i <= n) {
      c = substr(rest, i, 1)
      if (c == "\\") {
        i += 2
        continue
      }
      if (c == "\"") break
      val = val c
      i++
    }
    redact_begin()
    redact_shape(key, val)
    redact_dump(key)
    if (i >= n) break
    s = substr(rest, i + 1)
  }
}
