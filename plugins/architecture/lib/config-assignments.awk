# Emit connection shapes from one committed config or IaC file.
#
# Prepend plugins/architecture/lib/redact-connection.awk. Set ASSIGN_MODE to
# json, yaml, env, xml, hcl, or ini. The input file is read as text and
# matched. It is never executed. Each output line is
# kind, host, port, config-key, database, scheme. The raw value is not printed.
#
# Modes:
#   json  objects and arrays, including // and /* */ comments
#   yaml  indentation-scoped key: value, plus KEY=value list items
#   env   KEY=value, optional export, quotes stripped
#   xml   connectionString and key/value attributes
#   hcl   terraform and bicep assignments, with resource type in the key
#   ini   key=value, with [section] prefixed

function consider(path, value) {
  if (path == "" || value == "") return
  if (length(value) > 4000) return
  redact_begin()
  redact_shape(path, value)
  redact_dump(path)
}

function hex_digit(c) {
  c = tolower(c)
  return c ~ /^[0-9a-f]$/ ? index("0123456789abcdef", c) - 1 : -1
}

function json_skip_ws() {
  while (pi <= plen) {
    c = substr(buf, pi, 1)
    if (c == " " || c == "\t" || c == "\n" || c == "\r") {
      pi++
      continue
    }
    if (c == "/" && substr(buf, pi + 1, 1) == "/") {
      pi += 2
      while (pi <= plen && substr(buf, pi, 1) != "\n") pi++
      continue
    }
    if (c == "/" && substr(buf, pi + 1, 1) == "*") {
      pi += 2
      while (pi < plen && substr(buf, pi, 2) != "*/") pi++
      pi += 2
      continue
    }
    return
  }
}

function json_string(    out, c, hv, d, j) {
  out = ""
  if (substr(buf, pi, 1) != "\"") return ""
  pi++
  while (pi <= plen) {
    c = substr(buf, pi, 1)
    pi++
    if (c == "\"") return out
    if (c != "\\") {
      out = out c
      continue
    }
    if (pi > plen) break
    c = substr(buf, pi, 1)
    pi++
    if (c == "n") out = out "\n"
    else if (c == "t") out = out "\t"
    else if (c == "r") out = out "\r"
    else if (c == "u") {
      hv = 0
      for (j = 0; j < 4 && hv >= 0; j++) {
        d = hex_digit(substr(buf, pi + j, 1))
        hv = d < 0 ? -1 : hv * 16 + d
      }
      pi += 4
      if (hv >= 32 && hv < 127) out = out sprintf("%c", hv)
    } else out = out c
  }
  return out
}

function json_literal() {
  while (pi <= plen) {
    c = substr(buf, pi, 1)
    if (c == "," || c == "}" || c == "]" || c == " " || c == "\n" || c == "\r" || c == "\t")
      return
    pi++
  }
}

function json_value(path,    mark) {
  json_skip_ws()
  mark = pi
  c = substr(buf, pi, 1)
  if (c == "{") json_object(path)
  else if (c == "[") json_array(path)
  else if (c == "\"") {
    s = json_string()
    if (path != "") consider(path, s)
  } else json_literal()
  if (pi <= mark) pi = mark + 1
}

function json_object(path,    k, child, mark) {
  pi++
  while (pi <= plen) {
    mark = pi
    json_skip_ws()
    c = substr(buf, pi, 1)
    if (c == "}") {
      pi++
      return
    }
    if (c != "\"") {
      if (pi <= mark) pi = mark + 1
      continue
    }
    k = json_string()
    json_skip_ws()
    if (substr(buf, pi, 1) == ":") pi++
    if (path == "") child = k
    else child = path "." k
    json_value(child)
    json_skip_ws()
    if (substr(buf, pi, 1) == ",") pi++
    if (pi <= mark) pi = mark + 1
  }
}

function json_array(path,    i, mark) {
  pi++
  i = 0
  while (pi <= plen) {
    mark = pi
    json_skip_ws()
    c = substr(buf, pi, 1)
    if (c == "]") {
      pi++
      return
    }
    json_value(path "[" i "]")
    i++
    json_skip_ws()
    if (substr(buf, pi, 1) == ",") pi++
    if (pi <= mark) pi = mark + 1
  }
}

function yaml_unquote(val,    inner) {
  gsub(/\r/, "", val)
  if (match(val, /^"([^"\\]|\\.)*"/)) {
    inner = substr(val, 2, RLENGTH - 2)
    gsub(/\\"/, "\"", inner)
    gsub(/\\\\/, "\\", inner)
    return inner
  }
  if (match(val, /^'[^']*'/)) return substr(val, 2, RLENGTH - 2)
  sub(/[[:space:]]+#.*$/, "", val)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
  return val
}

function yaml_scan(    nlines, i, line, indent, rest, k, val, path, si, item) {
  nlines = split(buf, ylines, "\n")
  ystack_n = 0
  for (i = 1; i <= nlines; i++) {
    line = ylines[i]
    gsub(/\r/, "", line)
    if (line ~ /^[[:space:]]*#/) continue
    if (line ~ /^[[:space:]]*$/) continue
    if (line ~ /^---[[:space:]]*$/) continue
    if (index(line, "\t") > 0) continue
    indent = 0
    while (substr(line, indent + 1, 1) == " ") indent++
    rest = substr(line, indent + 1)
    if (substr(rest, 1, 2) == "- ") {
      item = substr(rest, 3)
      if (match(item, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
        k = substr(item, 1, RLENGTH - 1)
        val = yaml_unquote(substr(item, RLENGTH + 1))
        path = ""
        for (si = 1; si <= ystack_n; si++) {
          if (ystack_indent[si] >= indent) break
          path = (path == "" ? ystack_key[si] : path "." ystack_key[si])
        }
        consider((path == "" ? k : path "." k), val)
        continue
      }
      rest = item
    }
    if (!match(rest, /^[A-Za-z0-9_.-]+:[[:space:]]*/)) continue
    k = substr(rest, 1, index(rest, ":") - 1)
    val = substr(rest, RLENGTH + 1)
    while (ystack_n > 0 && ystack_indent[ystack_n] >= indent) ystack_n--
    path = ""
    for (si = 1; si <= ystack_n; si++)
      path = (path == "" ? ystack_key[si] : path "." ystack_key[si])
    path = (path == "" ? k : path "." k)
    if (val == "" || val ~ /^[|>][[:space:]]*$/ || val == "{" || val == "[") {
      ystack_n++
      ystack_indent[ystack_n] = indent
      ystack_key[ystack_n] = k
      continue
    }
    consider(path, yaml_unquote(val))
  }
}

function env_scan(    nlines, i, line, k, val) {
  nlines = split(buf, elines, "\n")
  for (i = 1; i <= nlines; i++) {
    line = elines[i]
    gsub(/\r/, "", line)
    sub(/^export[[:space:]]+/, "", line)
    if (line ~ /^[[:space:]]*#/) continue
    if (!match(line, /^[A-Za-z_][A-Za-z0-9_]*=/)) continue
    k = substr(line, 1, RLENGTH - 1)
    val = substr(line, RLENGTH + 1)
    consider(k, yaml_unquote(val))
  }
}

function xml_attr(line, attr) {
  if (match(line, attr "=\"[^\"]*\"") || match(line, attr "='[^']*'"))
    return substr(line, RSTART + length(attr) + 2, RLENGTH - length(attr) - 3)
  return ""
}

function xml_scan(    nlines, i, line, name, cs, key, val) {
  nlines = split(buf, xlines, "\n")
  for (i = 1; i <= nlines; i++) {
    line = xlines[i]
    cs = xml_attr(line, "connectionString")
    if (cs != "") {
      name = xml_attr(line, "name")
      if (name == "") name = "connectionString"
      consider(name, cs)
    }
    key = xml_attr(line, "key")
    val = xml_attr(line, "value")
    if (key != "" && val != "") consider(key, val)
  }
}

function hcl_quote(line) {
  if (match(line, /"[^"]*"/) || match(line, /'[^']*'/)) return substr(line, RSTART + 1, RLENGTH - 2)
  return ""
}

function hcl_scan(    nlines, i, line, depth, start, delta, ins, esc, j, c, res_type, res_name, res_floor, chunk, leaf, path, val) {
  nlines = split(buf, hlines, "\n")
  depth = 0
  res_type = ""
  res_name = ""
  res_floor = -1
  for (i = 1; i <= nlines; i++) {
    line = hlines[i]
    gsub(/\r/, "", line)
    if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*\/\//) continue
    start = depth
    if (match(line, /resource[[:space:]]+"[^"]+"[[:space:]]+"[^"]+"/)) {
      chunk = substr(line, RSTART, RLENGTH)
      if (match(chunk, /"[^"]+"/)) {
        res_type = substr(chunk, RSTART + 1, RLENGTH - 2)
        chunk = substr(chunk, RSTART + RLENGTH)
        if (match(chunk, /"[^"]+"/)) res_name = substr(chunk, RSTART + 1, RLENGTH - 2)
      }
      res_floor = start
    } else if (match(line, /resource[[:space:]]+[A-Za-z0-9_]+[[:space:]]+'[^']+'/)) {
      res_name = substr(line, RSTART, RLENGTH)
      sub(/^resource[[:space:]]+/, "", res_name)
      sub(/[^A-Za-z0-9_].*$/, "", res_name)
      if (match(line, /'[^']+'/)) {
        res_type = substr(line, RSTART + 1, RLENGTH - 2)
        sub(/@.*$/, "", res_type)
      }
      res_floor = start
    }
    if (match(line, /[A-Za-z0-9_]+[[:space:]]*[:=][[:space:]]*["']/)) {
      leaf = substr(line, RSTART, RLENGTH)
      sub(/[[:space:]]*[:=].*$/, "", leaf)
      val = hcl_quote(substr(line, RSTART))
      if (res_type != "" && depth >= res_floor) path = res_type "." res_name "." leaf
      else path = leaf
      consider(path, val)
    }
    delta = 0
    ins = ""
    esc = 0
    for (j = 1; j <= length(line); j++) {
      c = substr(line, j, 1)
      if (ins != "") {
        if (esc) {
          esc = 0
          continue
        }
        if (c == "\\") {
          esc = 1
          continue
        }
        if (c == ins) ins = ""
        continue
      }
      if (c == "\"" || c == "'") {
        ins = c
        continue
      }
      if (c == "{") delta++
      else if (c == "}") delta--
    }
    depth += delta
    if (res_type != "" && depth <= res_floor) {
      res_type = ""
      res_name = ""
      res_floor = -1
    }
  }
}

function ini_scan(    nlines, i, line, section, k, val, eq) {
  nlines = split(buf, ilines, "\n")
  section = ""
  for (i = 1; i <= nlines; i++) {
    line = ilines[i]
    gsub(/\r/, "", line)
    if (line ~ /^[[:space:]]*[;#]/) continue
    if (match(line, /^[[:space:]]*\[[^]]+\][[:space:]]*$/)) {
      section = substr(line, index(line, "[") + 1)
      sub(/\].*$/, "", section)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", section)
      continue
    }
    eq = index(line, "=")
    if (eq == 0) eq = index(line, ":")
    if (eq == 0) continue
    k = substr(line, 1, eq - 1)
    val = substr(line, eq + 1)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
    if (k == "") continue
    if (section != "") k = section "." k
    consider(k, yaml_unquote(val))
  }
}

BEGIN {
  buf = ""
  while ((getline line) > 0) buf = buf line "\n"
  plen = length(buf)
  pi = 1
  mode = ENVIRON["ASSIGN_MODE"]
  if (mode == "json") json_value("")
  else if (mode == "yaml") yaml_scan()
  else if (mode == "env") env_scan()
  else if (mode == "xml") xml_scan()
  else if (mode == "hcl") hcl_scan()
  else if (mode == "ini") ini_scan()
}
