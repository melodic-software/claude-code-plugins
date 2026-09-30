# Shared connection-shape redaction for map-context, map-containers, and
# map-deployment.
#
# Functions only. Callers prepend this file to their own awk program, or the
# bash wrapper in redact-connection.sh feeds one key and one value through
# ENVIRON. Nothing here prints the raw value.
#
# redact_shape(key, value) records zero or more shapes. redact_dump(cfgkey)
# prints them as: kind, host, port, cfgkey, database, scheme, tab-separated.
#
# A shape is a service kind plus a hostname and an optional numeric port. A sql
# shape may also carry a database name, which identifies the store beside the
# host and port, and a scheme (mongodb, postgres, mysql) when the value was a
# URL. Both are empty when the value names none. A database name is kept only
# when it is a plain identifier that carries no credential.
# Userinfo, query strings, passwords, account keys, tokens, and secret-only
# values are dropped. A value that is only a credential produces no row.
#
# A caller that charts endpoints between its own deployables sets
# redact_local_http (awk -v redact_local_http=1). An http shape may then also
# name a bare service name, localhost, or 127.0.0.1, and for every URL shape a ;
# after the userinfo ends the authority, so a ;-separated URL list reads as one
# shape per URL. Without it a bare service name and a loopback host are
# dropped, and a ; does not end the authority. An http shape then also carries its
# URL scheme in the scheme column, so the caller can refuse a scheme that is not
# http or https.
#
# redact_secret(key, value) is 1 when the key names a credential or the value
# carries one. A caller that prints a raw value drops it when this is 1.

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

function redact_account_name(s) {
  return length(s) >= 3 && length(s) <= 24 && s ~ /^[a-z0-9]+$/
}

function redact_bus_name(s) {
  return length(s) >= 3 && length(s) <= 50 && s ~ /^[a-z][a-z0-9-]*[a-z0-9]$/
}

function redact_host_ok(h) {
  if (h == "" || index(h, ".") == 0) return 0
  if (h ~ /[^a-z0-9.-]/) return 0
  if (index(h, "..") > 0) return 0
  if (h ~ /^(localhost|127\.0\.0\.1|0\.0\.0\.0|host\.docker\.internal)$/) return 0
  return 1
}

function redact_local_http_ok(h) {
  return h ~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/ || h == "127.0.0.1"
}

function redact_db_name(s) {
  if (length(s) < 1 || length(s) > 128 || s !~ /^[A-Za-z0-9_.-]+$/) return ""
  if (redact_secret_value(s)) return ""
  return tolower(s)
}

function redact_emit(kind, host, port, db, scheme,    id, j) {
  host = tolower(host)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", host)
  sub(/\.$/, "", host)
  if (!redact_host_ok(host) && !(redact_local_http + 0 && kind == "http" && redact_local_http_ok(host))) return
  if (port != "" && port !~ /^[0-9]+$/) port = ""
  id = host SUBSEP port SUBSEP db SUBSEP scheme
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
  redact_db[redact_n] = db
  redact_scheme[redact_n] = scheme
}

function redact_dump(cfgkey,    i, k) {
  k = cfgkey
  gsub(/\t/, " ", k)
  gsub(/\r/, "", k)
  gsub(/\n/, " ", k)
  for (i = 1; i <= redact_n; i++)
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", redact_kind[i], redact_host[i], redact_port[i], k, redact_db[i], redact_scheme[i]
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

function redact_server(raw, kind, db,    port, host) {
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
  # Data Source=app.db names a local file, not a server.
  if (tolower(host) ~ /\.(db|sqlite|sqlite3|mdb|mdf)$/) return
  redact_emit(kind, host, port, db, "")
}

function redact_scan_urls(value, bias,    rest, scheme, auth, host, port, kind, hk, cut, guard, tech, db, semi, query) {
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
    if ((redact_local_http + 0) && rest != "" && substr(rest, 1, 1) != "/") {
      query = substr(rest, 2)
      if (substr(rest, 1, 1) ~ /[ \t\r\n]/) {
        sub(/^[ \t\r\n]+/, "", query)
        if (match(query, /^[A-Za-z][A-Za-z0-9+.-]*:\/\//)) query = ""
      }
      if (index(query, "@") > 0) continue
    }
    if (index(auth, "@") > 0) sub(/^.*@/, "", auth)
    if ((redact_local_http + 0) && (semi = index(auth, ";")) > 0) {
      rest = substr(auth, semi + 1) rest
      auth = substr(auth, 1, semi - 1)
    }
    port = ""
    host = auth
    if (substr(host, 1, 1) == "[") continue
    if (match(host, /:[0-9]+$/)) {
      port = substr(host, RSTART + 1)
      host = substr(host, 1, RSTART - 1)
    }
    if (index(host, ":") > 0) continue
    kind = "http"
    tech = ""
    db = ""
    if (scheme == "amqp" || scheme == "amqps") kind = "broker"
    else if (scheme == "redis" || scheme == "rediss") kind = "cache"
    else if (scheme == "mongodb" || scheme == "mongodb+srv" || scheme == "postgres" ||
             scheme == "postgresql" || scheme == "mysql") {
      kind = "sql"
      tech = scheme
      sub(/\+srv$/, "", tech)
      if (tech == "postgresql") tech = "postgres"
      if (substr(rest, 1, 1) == "/") {
        db = substr(rest, 2)
        if (match(db, /[\/?# \t\r\n]/)) db = substr(db, 1, RSTART - 1)
        db = redact_db_name(db)
      }
    }
    else if (scheme == "smtp" || scheme == "smtps") kind = "mail"
    if (bias == "authority") kind = "authority"
    hk = redact_known_kind(host)
    if (hk != "") kind = hk
    if (kind == "sql") redact_emit(kind, host, port, db, tech)
    else if (kind == "http" && (redact_local_http + 0)) redact_emit(kind, host, port, "", scheme)
    else redact_emit(kind, host, port)
  }
}

function redact_shape(key, value,    cls, account, suffix, server, kl, bare, port, host, hk, nbrok, bi, brok, db) {
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
    if (redact_account_name(account) && suffix ~ /^[a-z0-9.-]+$/)
      redact_emit("storage", account ".blob." suffix, "")
    return
  }

  if ((value ~ /Server=/ || value ~ /Data Source=/ || value ~ /[Hh]ost=/) && value ~ /;/) {
    server = redact_cs_field(value, "Server")
    if (server == "") server = redact_cs_field(value, "Data Source")
    if (server == "") server = redact_cs_field(value, "Host")
    db = ""
    if (value !~ /["']/) {
      db = redact_cs_field(value, "Initial Catalog")
      if (db == "") db = redact_cs_field(value, "Database")
      db = redact_db_name(db)
    }
    if (server != "") redact_server(server, "sql", db)
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
  if (redact_account_name(value) &&
      (kl ~ /azurerm_storage_account[.][^.]+[.]name$/ ||
       kl ~ /microsoft[.]storage\/storageaccounts[.][^.]+[.]name$/))
    redact_emit("storage", value ".blob.core.windows.net", "")
  if (redact_bus_name(value) &&
      (kl ~ /azurerm_servicebus_namespace[.][^.]+[.]name$/ ||
       kl ~ /microsoft[.]servicebus\/namespaces[.][^.]+[.]name$/))
    redact_emit("broker", value ".servicebus.windows.net", "")

  if (cls == "storage" && redact_account_name(value))
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

# A key is secret when its last segment, split into words on separators and
# camelCase boundaries, has a credential word (DB_PASS, MYSQL_PWD, REDIS_AUTH,
# ENCRYPTION_KEY, clientSecret), or when it names a credential compound.
function redact_secret_key(key,    parts, n, leaf, words, i, c, prev, t, nw) {
  n = split(key, parts, ".")
  leaf = parts[n]
  n = split(leaf, parts, "__")
  leaf = parts[n]
  words = ""
  prev = ""
  for (i = 1; i <= length(leaf); i++) {
    c = substr(leaf, i, 1)
    if (c ~ /[A-Z]/ && prev ~ /[a-z0-9]/) words = words "_"
    words = words c
    prev = c
  }
  words = tolower(words)
  nw = split(words, parts, /[^a-z0-9]+/)
  for (i = 1; i <= nw; i++) {
    t = parts[i]
    if (t ~ /^(pass|pwd|passwd|password|secret|secrets|token|tokens|key|keys|auth|sas|sig|credential|credentials|apikey)$/) return 1
  }
  gsub(/[^a-z0-9]/, "", words)
  return words ~ /password|passwd|secret|token|apikey|accountkey|accesskey|privatekey|signingkey|sharedaccess|credential/
}

# A run of 40 or more base64 characters mixing upper case, lower case, and
# digits: an AWS secret access key, a storage account key, a signing key.
function redact_long_key(v,    rest, run) {
  rest = v
  while (match(rest, /[A-Za-z0-9+\/=]+/)) {
    run = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    if (length(run) >= 40 && run ~ /[A-Z]/ && run ~ /[a-z]/ && run ~ /[0-9]/) return 1
  }
  return 0
}

function redact_secret_value(v,    l, i) {
  if (redact_aws_id_re == "") {
    redact_aws_id_re = "(AKIA|ASIA)"
    for (i = 0; i < 16; i++) redact_aws_id_re = redact_aws_id_re "[A-Z0-9]"
  }
  l = tolower(v)
  if (l ~ /(^|[^a-z0-9])(password|passwd|pwd|pass|accountkey|sharedaccesskey|sharedaccesssignature|sig|client_?secret|secret|api_?key|access_?token|token)["']?[[:space:]]*[=:]/) return 1
  if (l ~ /[a-z][a-z0-9+.-]*:\/\/[^\/@[:space:]]+@/) return 1
  if (l ~ /[a-z][a-z0-9+.-]*:\/\/[^\/@[:space:]]*:[^@[:space:]]*@/) return 1
  if (l ~ /(^|[^a-z0-9])(basic|bearer)[[:space:]]+[a-z0-9+\/=._~-]/) return 1
  if (index(l, "private key") > 0) return 1
  if (v ~ /(^|[^A-Za-z0-9])(gh[pousr]_|github_pat_)[A-Za-z0-9]/) return 1
  if (v ~ redact_aws_id_re) return 1
  return redact_long_key(v)
}

function redact_secret(key, value) {
  return redact_secret_key(key) || redact_secret_value(value)
}
