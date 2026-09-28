# Shared connection-shape redaction for map-context, and for map-containers and
# map-deployment when those skills land.
#
# Functions only. Callers prepend this file to their own awk program, or the
# bash wrapper in redact-connection.sh feeds one key and one value through
# ENVIRON. Nothing here prints the raw value.
#
# redact_shape(key, value) records zero or more shapes. redact_dump(cfgkey)
# prints them as: kind, host, port, cfgkey, tab-separated.
#
# A shape is a service kind plus a hostname and an optional numeric port.
# Userinfo, query strings, passwords, account keys, tokens, and secret-only
# values are dropped. A value that is only a credential produces no row.

function redact_rank(k) {
  if (k == "authority") return 7
  if (k == "storage") return 6
  if (k == "broker") return 5
  if (k == "sql") return 4
  if (k == "cache") return 3
  if (k == "mail") return 2
  return 1
}

function redact_begin(    id) {
  redact_n = 0
  for (id in redact_at) delete redact_at[id]
}

function redact_host_ok(h) {
  if (h == "" || index(h, ".") == 0) return 0
  if (h ~ /[^a-z0-9.-]/) return 0
  if (index(h, "..") > 0) return 0
  if (h ~ /^(localhost|127\.0\.0\.1|0\.0\.0\.0|host\.docker\.internal)$/) return 0
  return 1
}

function redact_emit(kind, host, port,    id, j) {
  host = tolower(host)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", host)
  sub(/\.$/, "", host)
  if (!redact_host_ok(host)) return
  if (port != "" && port !~ /^[0-9]+$/) port = ""
  id = host SUBSEP port
  if (id in redact_at) {
    j = redact_at[id]
    if (redact_rank(kind) > redact_rank(redact_kind[j])) redact_kind[j] = kind
    return
  }
  redact_n++
  redact_at[id] = redact_n
  redact_kind[redact_n] = kind
  redact_host[redact_n] = host
  redact_port[redact_n] = port
}

function redact_dump(cfgkey,    i, k) {
  k = cfgkey
  gsub(/\t/, " ", k)
  gsub(/\r/, "", k)
  gsub(/\n/, " ", k)
  for (i = 1; i <= redact_n; i++)
    printf "%s\t%s\t%s\t%s\n", redact_kind[i], redact_host[i], redact_port[i], k
}

function redact_last_segment(key,    n, parts, leaf) {
  n = split(tolower(key), parts, ".")
  leaf = parts[n]
  n = split(leaf, parts, "__")
  return parts[n]
}

function redact_key_class(key,    last, norm) {
  last = redact_last_segment(key)
  norm = last
  gsub(/[^a-z0-9]/, "", norm)
  if (last == "$schema" || last == "$id" || last == "schema" || last == "license") return "skip"
  if (norm == "password" || norm == "pwd" || norm == "secret" || norm == "clientsecret" ||
      norm == "apikey" || norm == "apitoken" || norm == "accesstoken" || norm == "token" ||
      norm == "accountkey" || norm == "sharedaccesskey" || norm == "sharedaccesssignature" ||
      norm == "sas" || norm == "privatekey") return "secret"
  if (norm == "authority" || norm == "metadataaddress" || norm == "issuer" ||
      norm == "openidconnect" || norm == "authorizationurl" || norm ~ /authority$/)
    return "authority"
  if (norm == "bootstrapservers" || norm == "servicebus" || norm == "servicebusnamespace")
    return "broker"
  if (norm == "storageaccount" || norm == "storageaccountname") return "storage"
  return ""
}

function redact_cs_field(value, want,    n, i, seg, eq, k, v) {
  want = tolower(want)
  n = split(value, seg, ";")
  for (i = 1; i <= n; i++) {
    eq = index(seg[i], "=")
    if (eq == 0) continue
    k = tolower(substr(seg[i], 1, eq - 1))
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
    if (k == want) {
      v = substr(seg[i], eq + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
  }
  return ""
}

function redact_known_kind(host,    h) {
  h = tolower(host)
  if (h ~ /(^|\.)servicebus\.windows\.net$/) return "broker"
  if (h ~ /(^|\.)(blob|queue|table|file)\.core\.windows\.net$/) return "storage"
  if (h ~ /(^|\.)database\.windows\.net$/) return "sql"
  if (h ~ /(^|\.)redis\.cache\.windows\.net$/) return "cache"
  return ""
}

function redact_server(raw, kind,    port, host) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw)
  if (tolower(substr(raw, 1, 4)) == "tcp:") raw = substr(raw, 5)
  port = ""
  if (match(raw, /,[0-9]+$/)) {
    port = substr(raw, RSTART + 1)
    host = substr(raw, 1, RSTART - 1)
  } else if (match(raw, /:[0-9]+$/)) {
    port = substr(raw, RSTART + 1)
    host = substr(raw, 1, RSTART - 1)
    if (index(host, ":") > 0) return
  } else host = raw
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", host)
  redact_emit(kind, host, port)
}

function redact_scan_urls(value, bias,    rest, scheme, auth, host, port, kind, hk, cut, guard) {
  rest = value
  guard = 0
  while (match(rest, /[A-Za-z][A-Za-z0-9+.-]*:\/\//)) {
    guard++
    if (guard > 20) return
    scheme = tolower(substr(rest, RSTART, RLENGTH - 3))
    rest = substr(rest, RSTART + RLENGTH)
    if (match(rest, /[\/?# \t\r\n]/)) cut = RSTART
    else cut = length(rest) + 1
    if (cut <= 1) {
      if (length(rest) > 0) rest = substr(rest, 2)
      else return
      continue
    }
    auth = substr(rest, 1, cut - 1)
    rest = substr(rest, cut)
    if (index(auth, "@") > 0) sub(/^.*@/, "", auth)
    port = ""
    host = auth
    if (substr(host, 1, 1) == "[") continue
    if (match(host, /:[0-9]+$/)) {
      port = substr(host, RSTART + 1)
      host = substr(host, 1, RSTART - 1)
    }
    if (index(host, ":") > 0) continue
    kind = "http"
    if (scheme == "amqp" || scheme == "amqps") kind = "broker"
    else if (scheme == "redis" || scheme == "rediss") kind = "cache"
    else if (scheme == "mongodb" || scheme == "mongodb+srv" || scheme == "postgres" ||
             scheme == "postgresql" || scheme == "mysql") kind = "sql"
    else if (scheme == "smtp" || scheme == "smtps") kind = "mail"
    if (bias == "authority") kind = "authority"
    hk = redact_known_kind(host)
    if (hk != "") kind = hk
    redact_emit(kind, host, port)
  }
}

function redact_shape(key, value,    cls, account, suffix, server, kl, bare, port, host, hk, nbrok, bi, brok) {
  gsub(/\r/, "", value)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
  if (length(value) > 4000) return
  cls = redact_key_class(key)
  if (cls == "skip" || cls == "secret") return

  if (value ~ /AccountName=/ &&
      (value ~ /AccountKey=/ || value ~ /EndpointSuffix=/ || value ~ /DefaultEndpointsProtocol=/)) {
    account = redact_cs_field(value, "AccountName")
    suffix = redact_cs_field(value, "EndpointSuffix")
    account = tolower(account)
    suffix = tolower(suffix)
    if (suffix == "") suffix = "core.windows.net"
    if (account ~ /^[a-z0-9]{3,24}$/ && suffix ~ /^[a-z0-9.-]+$/)
      redact_emit("storage", account ".blob." suffix, "")
    return
  }

  if ((value ~ /Server=/ || value ~ /Data Source=/ || value ~ /[Hh]ost=/) && value ~ /;/) {
    server = redact_cs_field(value, "Server")
    if (server == "") server = redact_cs_field(value, "Data Source")
    if (server == "") server = redact_cs_field(value, "Host")
    if (server != "") redact_server(server, "sql")
    return
  }

  redact_scan_urls(value, cls)

  bare = value
  gsub(/^["']|["']$/, "", bare)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", bare)
  port = ""
  host = bare
  if (match(host, /:[0-9]+$/)) {
    port = substr(host, RSTART + 1)
    host = substr(host, 1, RSTART - 1)
  }
  if (index(host, "://") == 0 && index(host, "@") == 0 && index(host, "/") == 0 &&
      index(host, "?") == 0 && index(host, "=") == 0) {
    hk = redact_known_kind(host)
    if (hk != "") redact_emit(hk, host, port)
  }

  kl = tolower(key)
  if (value ~ /^[a-z0-9]{3,24}$/ &&
      (kl ~ /azurerm_storage_account[.][^.]+[.]name$/ ||
       kl ~ /microsoft[.]storage\/storageaccounts[.][^.]+[.]name$/))
    redact_emit("storage", value ".blob.core.windows.net", "")
  if (value ~ /^[a-z][a-z0-9-]{1,48}[a-z0-9]$/ &&
      (kl ~ /azurerm_servicebus_namespace[.][^.]+[.]name$/ ||
       kl ~ /microsoft[.]servicebus\/namespaces[.][^.]+[.]name$/))
    redact_emit("broker", value ".servicebus.windows.net", "")

  if (cls == "storage" && value ~ /^[a-z0-9]{3,24}$/)
    redact_emit("storage", value ".blob.core.windows.net", "")
  if (cls == "broker") {
    nbrok = split(value, brok, ",")
    for (bi = 1; bi <= nbrok; bi++) {
      host = brok[bi]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", host)
      port = ""
      if (match(host, /:[0-9]+$/)) {
        port = substr(host, RSTART + 1)
        host = substr(host, 1, RSTART - 1)
      }
      if (index(host, "://") == 0) redact_emit("broker", host, port)
    }
  }
}
