#!/usr/bin/env bash
# Unit tests for redact_connection_shape. The raw value must never come back.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/redact-connection.sh"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3
  actual: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3
  actual: $2" ;;
  *) pass "$1" ;;
  esac
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

shape() {
  redact_connection_shape "$1" "$2"
}

# Fixture credentials expand from variables so no committed line reads as a live credential to a secret scanner.
leak_sql="SuperSecret123"
leak_blob="abcDEF123SECRETKEY"

sql="$(shape "ConnectionStrings.Orders" "Server=tcp:orders.database.windows.net,1433;User ID=sa;Password=${leak_sql};Encrypt=true;")"
assert_equals "sql: shape is the host and port" "$sql" $'sql\torders.database.windows.net\t1433'
assert_not_contains "sql: password is absent" "$sql" "$leak_sql"

url="$(shape "Partner.BaseUrl" "https://user:s3cr3t-token@api.partner.example/v1?sig=AAAASECRET")"
assert_equals "url: userinfo and query are dropped" "$url" $'http\tapi.partner.example\t'
assert_not_contains "url: token is absent" "$url" "s3cr3t-token"
assert_not_contains "url: query sig is absent" "$url" "AAAASECRET"

auth="$(shape "Auth.Authority" "https://login.example.com/tenant")"
assert_equals "authority: kind follows the key" "$auth" $'authority\tlogin.example.com\t'

secret="$(shape "Auth.ClientSecret" "client-secret-VALUE99" || true)"
assert_equals "secret-only key emits nothing" "$secret" ""

store="$(shape "Storage.ConnectionString" "DefaultEndpointsProtocol=https;AccountName=orderblobs;AccountKey=${leak_blob}==;EndpointSuffix=core.windows.net")"
assert_equals "storage: account name becomes a blob host" "$store" $'storage\torderblobs.blob.core.windows.net\t'
assert_not_contains "storage: account key is absent" "$store" "$leak_blob"

bus="$(shape "Messaging.Namespace" "orders.servicebus.windows.net")"
assert_equals "broker: a service bus host is a broker" "$bus" $'broker\torders.servicebus.windows.net\t'

redis="$(shape "REDIS_URL" "rediss://:redis-pass-XYZ@cache.example.com:6380/0")"
assert_equals "cache: redis userinfo is dropped" "$redis" $'cache\tcache.example.com\t6380'
assert_not_contains "cache: password is absent" "$redis" "redis-pass-XYZ"

loop="$(shape "Kestrel.Url" "http://localhost:5000" || true)"
assert_equals "loopback is not an external system" "$loop" ""

acct="$(shape "azurerm_storage_account.logs.name" "logsacct")"
assert_equals "iac: storage account name becomes a blob host" "$acct" $'storage\tlogsacct.blob.core.windows.net\t'

ns="$(shape "azurerm_servicebus_namespace.bus.name" "appbus")"
assert_equals "iac: service bus namespace becomes a broker host" "$ns" $'broker\tappbus.servicebus.windows.net\t'

mail="$(shape "Smtp.Host" "https://alice:P4ss-UNIQUE-991@smtp.example.com/send")"
assert_contains "mail: host survives" "$mail" "smtp.example.com"
assert_not_contains "mail: password is absent" "$mail" "P4ss-UNIQUE-991"

bare="$(shape "Owner" "alice@example.com" || true)"
assert_equals "an email is not a connection" "$bare" ""

secret() {
  if redact_is_secret "$2" "$3"; then pass "secret: $1"; else fail "secret: $1" "not flagged: $2"; fi
}
clean() {
  if redact_is_secret "$2" "$3"; then fail "clean: $1" "flagged: $2 = $3"; else pass "clean: $1"; fi
}
# Fake placeholders. Shapes a secret scanner flags as a literal are assembled at runtime.
fake="FAKE-NOT-A-SECRET-0000"
secret "sql password" "Db" "Server=db.example.com;Password=${fake}"
secret "storage account key" "Blob" "AccountName=a;AccountKey=${fake}"
secret "shared access key" "Bus" "Endpoint=sb://b.servicebus.windows.net/;SharedAccessKey=${fake}"
secret "sas signature" "Sas" "https://a.blob.core.windows.net/c?sv=1&s""ig=${fake}"
secret "github token" "Upstream" "gh""p_$(printf 'X%.0s' {1..36})"
secret "github fine-grained token" "Upstream" "github""_pat_11$(printf 'X%.0s' {1..40})"
secret "aws access key id" "Cloud" "AK""IAFAKEFAKEFAKE0000"
secret "aws secret access key" "Cloud" "FakeNotASecret0000/FakeNotASecret0000+X1"
secret "private key header" "Pem" "-----BEGIN ""PRIVATE KEY-----MIIFAKE"
secret "url userinfo" "Partner" "https://svc:${fake}@partner.example.com"
secret "basic authorization" "Header" "Authorization: Basic ${fake}"
secret "bearer authorization" "Header" "Bearer ${fake}"
secret "signing key name" "JWT_SIGNING_KEY" "anything"
secret "access key name" "AWS_ACCESS_KEY_ID" "anything"
secret "password name" "DB_PASSWORD" "anything"
clean "log level" "LOG_LEVEL" "info"
clean "image" "Image" "ghcr.io/acme/api:1.0.0"
clean "image digest" "Image" "ghcr.io/acme/api@sha256:$(printf 'a%.0s' {1..64})"
clean "plain url" "Auth.Authority" "https://login.example.com/tenant"
clean "host and port" "Cache" "cache.example.com:6380"

exec_out="$(bash "$SCRIPT_DIR/redact-connection.sh" 2>&1)"
assert_equals "executing the wrapper exits 2" "$?" "2"
assert_contains "executing the wrapper says to source it" "$exec_out" "source this file"

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
