#!/usr/bin/env bash
# Tests for collect-context.sh: cited config, redaction, actors, thin results.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-context.sh"
RENDER="$SCRIPT_DIR/render-context.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

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

init_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email "fixture@example.invalid"
  git -C "$dir" config user.name "Fixture"
  git -C "$dir" config commit.gpgsign false
  printf '%s' "$dir"
}

# Fixture credentials expand from variables so no committed line reads as a live credential to a secret scanner.
leak_sql="SuperSecret123"
leak_blob="abcDEF123SECRETKEY"
SECRETS="$leak_sql s3cr3t-token $leak_blob client-secret-VALUE99 AAAASECRET redis-pass-XYZ P4ss-UNIQUE-991"
assert_clean() {
  local label="$1" blob="$2" word
  for word in $SECRETS; do
    assert_not_contains "$label: no $word" "$blob" "$word"
  done
}

help_out="$(bash "$COLLECT" --help)"
assert_equals "usage: --help exits 0" "$?" "0"
assert_contains "usage: describes schema_version" "$help_out" "schema_version"
bad="$(bash "$COLLECT" --nope 2>&1)"
assert_equals "usage: unknown argument exits 2" "$?" "2"
assert_contains "usage: names the argument" "$bad" "unknown argument"

repo="$(init_repo "$TEST_TMPDIR/checkout-dir")"
git -C "$repo" remote add origin "https://github.com/acme/billing.git"
mkdir -p "$repo/src"
cat >"$repo/src/appsettings.json" <<JSON
{
  "\$schema": "https://json.schemastore.org/appsettings.json",
  "ConnectionStrings": {
    "Orders": "Server=tcp:orders.database.windows.net,1433;User ID=sa;Password=${leak_sql};Encrypt=true;"
  },
  "Partner": {
    "BaseUrl": "https://user:s3cr3t-token@api.partner.example/v1?sig=AAAASECRET"
  },
  "Auth": {
    "Authority": "https://login.example.com/tenant",
    "ClientSecret": "client-secret-VALUE99"
  },
  "Storage": {
    "ConnectionString": "DefaultEndpointsProtocol=https;AccountName=orderblobs;AccountKey=${leak_blob}==;EndpointSuffix=core.windows.net"
  },
  "Messaging": {
    "Namespace": "orders.servicebus.windows.net"
  },
  "Owner": "alice@example.com"
}
JSON
cat >"$repo/src/main.tf" <<'TF'
resource "azurerm_storage_account" "logs" {
  name = "logsacct"
}
resource "azurerm_servicebus_namespace" "bus" {
  name = "appbus"
}
TF
cat >"$repo/src/compose.yml" <<'YAML'
services:
  api:
    environment:
      OIDC_AUTHORITY: https://login.example.com/realms/app
      SMTP_URL: https://alice:P4ss-UNIQUE-991@smtp.example.com/send
YAML
printf 'REDIS_URL=rediss://:redis-pass-XYZ@cache.example.com:6380/0\n' >"$repo/src/runtime.env"
cat >"$repo/src/web.config" <<XML
<configuration>
  <connectionStrings>
    <add name="Legacy" connectionString="Server=legacy.database.windows.net;User ID=sa;Password=${leak_sql};" />
  </connectionStrings>
  <appSettings>
    <add key="Hooks.BaseUrl" value="https://hooks.example.com/\$(touch SHOULD_NOT_RUN)" />
  </appSettings>
</configuration>
XML
printf '{ "homepage": "https://homepage.example.com", "token": "client-secret-VALUE99" }\n' >"$repo/package.json"
printf '* @alice\n' >"$repo/CODEOWNERS"
printf 'Maintained by Bob the person.\n' >"$repo/README.md"
mkdir -p "$repo/docs/architecture"
printf '{"host":"should-not-rescan.example.com"}\n' >"$repo/docs/architecture/context.json"
printf '.env\n' >"$repo/.gitignore"
printf 'IGNORED_URL=https://user:SHOULD_NOT_LEAK_IGNORED@ignored-secret-host.example/v1\n' >"$repo/.env"
git -C "$repo" add -A
git -C "$repo" commit --quiet -m "fixture"
printf '{ "Extra": { "BaseUrl": "https://untracked-host.example/v1" } }\n' >"$repo/src/untracked.json"

collect_out="$(bash "$COLLECT" --repo "$repo" --generated-on 2026-09-28 --out "$TEST_TMPDIR/context.json" 2>"$TEST_TMPDIR/collect.err")"
assert_equals "collect: exits 0" "$?" "0"
record="$(cat "$TEST_TMPDIR/context.json")"
stderr="$(cat "$TEST_TMPDIR/collect.err")"
blob="$collect_out$stderr$record"
assert_clean "collect output" "$blob"
assert_contains "collect: subject is the github.com repository name" "$record" '"subject": "billing"'
assert_contains "collect: focal is derived" "$record" '"focal": {"name":"billing","origin":"derived"}'
assert_contains "collect: sql cites the config key and file" "$record" '"file":"src/appsettings.json","key":"ConnectionStrings.Orders"'
assert_contains "collect: sql host is the server" "$record" '"host":"orders.database.windows.net"'
assert_contains "collect: partner host cites Partner.BaseUrl" "$record" '"key":"Partner.BaseUrl"'
assert_contains "collect: authority cites Auth.Authority" "$record" '"key":"Auth.Authority"'
assert_contains "collect: storage host keeps the account shape" "$record" '"host":"orderblobs.blob.core.windows.net"'
assert_contains "collect: broker cites Messaging.Namespace" "$record" '"key":"Messaging.Namespace"'
assert_contains "collect: terraform storage account is a blob host" "$record" '"host":"logsacct.blob.core.windows.net"'
assert_contains "collect: terraform storage cites the resource name" "$record" '"key":"azurerm_storage_account.logs.name"'
assert_contains "collect: terraform bus is a broker host" "$record" '"host":"appbus.servicebus.windows.net"'
assert_contains "collect: yaml authority is recorded" "$record" '"host":"login.example.com"'
assert_contains "collect: redis host is recorded" "$record" '"host":"cache.example.com"'
assert_contains "collect: xml connection cites its name" "$record" '"key":"Legacy"'
assert_contains "collect: xml base url host is recorded" "$record" '"host":"hooks.example.com"'
assert_not_contains "collect: package.json homepage is not an external system" "$record" "homepage.example.com"
assert_not_contains "collect: a gitignored env file is not a source" "$record" "ignored-secret-host.example"
assert_not_contains "collect: an untracked config file is not a source" "$record" "untracked-host.example"
assert_not_contains "collect: gitignored secret material is absent" "$blob" "SHOULD_NOT_LEAK_IGNORED"
assert_not_contains "collect: a previous context.json is not re-read" "$record" "should-not-rescan.example.com"
assert_not_contains "collect: actors are absent without --actors" "$record" '"origin":"operator"'
assert_not_contains "collect: CODEOWNERS people are not actors" "$record" "alice"
assert_not_contains "collect: README people are not actors" "$record" "Bob"
assert_equals "collect: the command in a config value was not executed" "$(find "$repo" -name SHOULD_NOT_RUN | wc -l | tr -d ' ')" "0"
assert_equals "collect: stdout is empty when --out is set" "$collect_out" ""

mkdir -p "$TEST_TMPDIR/render-full"
render_out="$(bash "$RENDER" --record "$TEST_TMPDIR/context.json" --out "$TEST_TMPDIR/render-full" --dialect c4-plantuml 2>"$TEST_TMPDIR/render.err")"
assert_equals "render: c4-plantuml exits 0" "$?" "0"
md="$(cat "$TEST_TMPDIR/render-full/context.md")"
render_blob="$render_out$(cat "$TEST_TMPDIR/render.err")$md"
assert_clean "render output" "$render_blob"
assert_contains "render: summary counts externals" "$render_out" "externals="
assert_contains "render: summary has no actors" "$render_out" "actors=0"
assert_contains "render: summary is not thin" "$render_out" "thin=no"
assert_contains "render: evidence table cites the sql file" "$md" "src/appsettings.json"
assert_contains "render: evidence table cites the sql key" "$md" "ConnectionStrings.Orders"
assert_not_contains "render: non-interactive diagram has no Person" "$md" "Person("

printf 'Clerk\tFiles a claim\n' >"$TEST_TMPDIR/actors.tsv"
actor_out="$(bash "$COLLECT" --repo "$repo" --generated-on 2026-09-28 --actors "$TEST_TMPDIR/actors.tsv" --out "$TEST_TMPDIR/with-actors.json" 2>"$TEST_TMPDIR/actors.err")"
assert_equals "actors: collect exits 0" "$?" "0"
arec="$(cat "$TEST_TMPDIR/with-actors.json")"
assert_contains "actors: operator origin is recorded" "$arec" '"name":"Clerk","description":"Files a claim","origin":"operator"'
assert_not_contains "actors: still no repo people" "$arec" "alice"
mkdir -p "$TEST_TMPDIR/render-actors" "$TEST_TMPDIR/render-dsl"
bash "$RENDER" --record "$TEST_TMPDIR/with-actors.json" --out "$TEST_TMPDIR/render-actors" --dialect c4-plantuml >"$TEST_TMPDIR/actors-render.out"
amd="$(cat "$TEST_TMPDIR/render-actors/context.md")"
assert_contains "actors: c4-plantuml draws a person" "$amd" "Person("
assert_contains "actors: c4-plantuml draws derived systems differently" "$amd" "System_Ext("
assert_contains "actors: the table says operator-stated" "$amd" "operator-stated"
assert_contains "actors: the table says derived" "$amd" "derived"
assert_clean "actor render" "$amd$actor_out$(cat "$TEST_TMPDIR/actors.err")$(cat "$TEST_TMPDIR/actors-render.out")"
bash "$RENDER" --record "$TEST_TMPDIR/with-actors.json" --out "$TEST_TMPDIR/render-dsl" --dialect likec4 >"$TEST_TMPDIR/dsl.out"
dsl="$(cat "$TEST_TMPDIR/render-dsl/context.md")"
assert_contains "actors: likec4 draws a person" "$dsl" "= person "
assert_contains "actors: likec4 marks externals" "$dsl" "= externalSystem "
assert_contains "actors: likec4 has a view" "$dsl" "view context {"
assert_contains "actors: likec4 gives people a person shape" "$dsl" "shape person"
assert_clean "likec4" "$dsl"

thin_repo="$(init_repo "$TEST_TMPDIR/thin-checkout")"
mkdir -p "$thin_repo/src"
cat >"$thin_repo/src/appsettings.json" <<'JSON'
{
  "Logging": { "LogLevel": { "Default": "Information" } },
  "Kestrel": { "Endpoints": { "Http": { "Url": "http://localhost:5000" } } }
}
JSON
git -C "$thin_repo" add -A
git -C "$thin_repo" commit --quiet -m "fixture"
bash "$COLLECT" --repo "$thin_repo" --generated-on 2026-09-28 --out "$TEST_TMPDIR/thin.json" >"$TEST_TMPDIR/thin-collect.out"
thin_rec="$(cat "$TEST_TMPDIR/thin.json")"
assert_contains "thin: externals array is empty" "$thin_rec" '"externals": []'
assert_contains "thin: actors array is empty" "$thin_rec" '"actors": []'
mkdir -p "$TEST_TMPDIR/render-thin"
thin_sum="$(bash "$RENDER" --record "$TEST_TMPDIR/thin.json" --out "$TEST_TMPDIR/render-thin" --dialect likec4)"
assert_contains "thin: summary says yes" "$thin_sum" "thin=yes"
assert_contains "thin: summary has no externals" "$thin_sum" "externals=0"
thin_md="$(cat "$TEST_TMPDIR/render-thin/context.md")"
assert_contains "thin: the artifact says none were found" "$thin_md" "No external systems were found in committed configuration."
assert_contains "thin: the artifact names the landscape rung" "$thin_md" "/architecture:map-landscape"
assert_contains "thin: the artifact names the container rung" "$thin_md" "containers (the deployables inside this system)"
assert_contains "thin: the focal system is still drawn" "$thin_md" "= softwareSystem \"thin-checkout\""

link_repo="$(init_repo "$TEST_TMPDIR/link-checkout")"
mkdir -p "$link_repo/src"
printf 'outside.json\n' >"$link_repo/.gitignore"
printf '{ "Partner": { "BaseUrl": "https://leak.partner.example/api" } }\n' >"$link_repo/outside.json"
ln -s ../outside.json "$link_repo/src/appsettings.json"
git -C "$link_repo" add -A
git -C "$link_repo" commit --quiet -m "fixture"
bash "$COLLECT" --repo "$link_repo" --generated-on 2026-09-28 --out "$TEST_TMPDIR/link.json" >/dev/null 2>&1
assert_not_contains "symlink: a tracked link to an untracked file is not a source" "$(cat "$TEST_TMPDIR/link.json")" "leak.partner.example"

date_repo="$(init_repo "$TEST_TMPDIR/date-checkout")"
mkdir -p "$date_repo/src"
printf '{ "Partner": { "BaseUrl": "https://date.partner.example/api" } }\n' >"$date_repo/src/appsettings.json"
git -C "$date_repo" add -A
GIT_COMMITTER_DATE="2024-03-05T12:00:00Z" git -C "$date_repo" commit --quiet -m "fixture"
bash "$COLLECT" --repo "$date_repo" >"$TEST_TMPDIR/date-1.json"
bash "$COLLECT" --repo "$date_repo" >"$TEST_TMPDIR/date-2.json"
if cmp -s "$TEST_TMPDIR/date-1.json" "$TEST_TMPDIR/date-2.json"; then
  pass "generated_on: a second run on the same commit is byte-identical"
else
  fail "generated_on: a second run on the same commit is byte-identical" "outputs differ"
fi
assert_contains "generated_on: defaults to the HEAD commit date" "$(cat "$TEST_TMPDIR/date-1.json")" '"generated_on": "2024-03-05"'
assert_contains "generated_on: --generated-on overrides the default" "$(bash "$COLLECT" --repo "$date_repo" --generated-on 2020-01-02)" '"generated_on": "2020-01-02"'
empty_repo="$(init_repo "$TEST_TMPDIR/empty-checkout")"
assert_contains "generated_on: a repo with no commits is unknown" "$(bash "$COLLECT" --repo "$empty_repo")" '"generated_on": "unknown"'
printf 'a file, not a directory\n' >"$TEST_TMPDIR/blocker"
bash "$COLLECT" --repo "$date_repo" --out "$TEST_TMPDIR/blocker/out.json" >/dev/null 2>"$TEST_TMPDIR/unwritable.err"
assert_equals "--out: a parent that is a file exits 1" "$?" "1"
assert_contains "--out: a parent that is a file says so" "$(cat "$TEST_TMPDIR/unwritable.err")" "cannot write --out file"
mkdir -p "$TEST_TMPDIR/out-is-a-dir"
bash "$COLLECT" --repo "$date_repo" --out "$TEST_TMPDIR/out-is-a-dir" >/dev/null 2>"$TEST_TMPDIR/unwritable-dir.err"
assert_equals "--out: a path that is a directory exits 1" "$?" "1"
assert_contains "--out: a path that is a directory says so" "$(cat "$TEST_TMPDIR/unwritable-dir.err")" "cannot write --out file"
bash "$COLLECT" --repo "$date_repo" --generated-on 2026-09-28 --out "$TEST_TMPDIR/new-home/architecture/context.json" >/dev/null 2>"$TEST_TMPDIR/new-home.err"
assert_equals "--out: a directory that does not exist yet is created" "$?" "0"
assert_contains "--out: the record lands in the created directory" "$(cat "$TEST_TMPDIR/new-home/architecture/context.json")" "date.partner.example"
bash "$RENDER" --record "$TEST_TMPDIR/new-home/architecture/context.json" --out "$TEST_TMPDIR/new-home/architecture" --dialect none >/dev/null 2>&1
assert_equals "--out: the render step reads the record written into the created directory" "$?" "0"

# An http URL is an external system only under a key that names an integration.
http_repo="$(init_repo "$TEST_TMPDIR/http-checkout")"
mkdir -p "$http_repo/src"
cat >"$http_repo/src/appsettings.json" <<'JSON'
{
  "ApiBaseUrl": "https://apibase.integration.example/v1",
  "Authority": "https://authority.integration.example/tenant",
  "Backup": { "Host": "https://host.integration.example" },
  "homepage": "https://homepage.docs.example",
  "repository": "https://repository.docs.example",
  "bugs": { "url": "https://bugs.docs.example" },
  "license": { "url": "https://license.docs.example" },
  "contact": { "url": "https://contact.docs.example" },
  "externalDocs": { "url": "https://externaldocs.docs.example" },
  "servers": [{ "url": "https://servers.docs.example/v1" }],
  "Partner": "https://unkeyed.docs.example"
}
JSON
cat >"$http_repo/src/openapi.yaml" <<'YAML'
openapi: 3.0.0
info:
  license:
    url: https://yamllicense.docs.example
servers:
  - url: https://yamlservers.docs.example/v1
externalDocs:
  url: https://yamlexternaldocs.docs.example
YAML
cat >"$http_repo/mkdocs.yml" <<'YAML'
site_url: https://siteurl.docs.example/
repo_url: https://repourl.docs.example/acme/billing
YAML
git -C "$http_repo" add -A
git -C "$http_repo" commit --quiet -m "fixture"
bash "$COLLECT" --repo "$http_repo" --generated-on 2026-09-28 --out "$TEST_TMPDIR/http.json" >/dev/null 2>&1
http_rec="$(cat "$TEST_TMPDIR/http.json")"
assert_contains "http: ApiBaseUrl names an integration" "$http_rec" '"host":"apibase.integration.example"'
assert_contains "http: Authority names an integration" "$http_rec" '"host":"authority.integration.example"'
assert_contains "http: a Host key names an integration" "$http_rec" '"host":"host.integration.example"'
assert_not_contains "http: a homepage is not an external system" "$http_rec" "homepage.docs.example"
assert_not_contains "http: a repository is not an external system" "$http_rec" "repository.docs.example"
assert_not_contains "http: bugs.url is not an external system" "$http_rec" "bugs.docs.example"
assert_not_contains "http: license.url is not an external system" "$http_rec" "license.docs.example"
assert_not_contains "http: contact.url is not an external system" "$http_rec" "contact.docs.example"
assert_not_contains "http: an OpenAPI externalDocs url is not an external system" "$http_rec" "externaldocs.docs.example"
assert_not_contains "http: an OpenAPI servers entry is not an external system" "$http_rec" "servers.docs.example"
assert_not_contains "http: a URL under a key with no integration name is not an external system" "$http_rec" "unkeyed.docs.example"
assert_not_contains "http: a yaml license url is not an external system" "$http_rec" "yamllicense.docs.example"
assert_not_contains "http: a yaml OpenAPI servers entry is not an external system" "$http_rec" "yamlservers.docs.example"
assert_not_contains "http: a yaml externalDocs url is not an external system" "$http_rec" "yamlexternaldocs.docs.example"
assert_not_contains "http: mkdocs site_url is not an external system" "$http_rec" "siteurl.docs.example"
assert_not_contains "http: mkdocs repo_url is not an external system" "$http_rec" "repourl.docs.example"

# A Data Source that names a file is not a server.
lite_repo="$(init_repo "$TEST_TMPDIR/lite-checkout")"
mkdir -p "$lite_repo/src"
cat >"$lite_repo/src/appsettings.json" <<JSON
{
  "ConnectionStrings": {
    "Lite": "Data Source=app.db;Foreign Keys=True",
    "Legacy": "Data Source=northwind.mdf;Integrated Security=True",
    "Access": "Data Source=ledger.mdb;Persist Security Info=False",
    "Cache": "Data Source=cache.sqlite3;Mode=ReadWrite;",
    "Plain": "Data Source=state.sqlite;Version=3;",
    "Real": "Data Source=sql.lite-control.example;Initial Catalog=Orders;User ID=sa;Password=${leak_sql}"
  }
}
JSON
git -C "$lite_repo" add -A
git -C "$lite_repo" commit --quiet -m "fixture"
lite_out="$(bash "$COLLECT" --repo "$lite_repo" --generated-on 2026-09-28 2>&1)"
for lite_file in app.db northwind.mdf ledger.mdb cache.sqlite3 state.sqlite; do
  assert_not_contains "sqlite: Data Source=$lite_file is not a host" "$lite_out" "$lite_file"
done
assert_contains "sqlite: a real Data Source server is still recorded" "$lite_out" '"host":"sql.lite-control.example"'
assert_not_contains "sqlite: the real server's password is absent" "$lite_out" "$leak_sql"

# An actor line carrying credential material is skipped whatever shape the credential takes.
act_token="Tok""en=actor-tkn-7731"
act_client="Client""Secret=actor-cs-8842"
act_bearer="Bea""rer actor-bearer-9953"
act_aws="AK""IA""FAKEFAKEFAKE0000"
printf 'Clerk\tFiles a claim\nOps bot\tCalls with %s\nSvc\t%s\nGate\tsends %s\nCloud\tholds %s\n' \
  "$act_token" "$act_client" "$act_bearer" "$act_aws" >"$TEST_TMPDIR/secret-actors.tsv"
sact_out="$(bash "$COLLECT" --repo "$date_repo" --generated-on 2026-09-28 --actors "$TEST_TMPDIR/secret-actors.tsv" --out "$TEST_TMPDIR/secret-actors.json" 2>&1)"
assert_equals "actors: a secret-bearing line does not fail the run" "$?" "0"
mkdir -p "$TEST_TMPDIR/render-secret-actors"
bash "$RENDER" --record "$TEST_TMPDIR/secret-actors.json" --out "$TEST_TMPDIR/render-secret-actors" --dialect c4-plantuml >/dev/null 2>&1
sact_blob="$sact_out$(cat "$TEST_TMPDIR/secret-actors.json" "$TEST_TMPDIR/render-secret-actors/context.md")"
assert_contains "actors: the clean line is kept" "$sact_blob" '"name":"Clerk"'
for actor_secret in actor-tkn-7731 actor-cs-8842 actor-bearer-9953 "$act_aws"; do
  assert_not_contains "actors: $actor_secret is in neither the record nor context.md" "$sact_blob" "$actor_secret"
done
for actor_name in "Ops bot" "Svc" "Gate" "Cloud"; do
  assert_not_contains "actors: the $actor_name line is skipped" "$(cat "$TEST_TMPDIR/secret-actors.json")" "\"name\":\"$actor_name\""
done
assert_contains "actors: the skip is reported" "$sact_out" "skipped an actor line"

rec_repo="$(init_repo "$TEST_TMPDIR/records-checkout")"
mkdir -p "$rec_repo/src" "$rec_repo/docs/architecture"
printf '{ "Partner": { "BaseUrl": "https://real.partner.example/api" } }\n' >"$rec_repo/src/appsettings.json"
for rec in deployment containers events; do
  printf '{ "Partner": { "BaseUrl": "https://%s.record.example/api", "Host": "%s.record.example" } }\n' "$rec" "$rec" >"$rec_repo/docs/architecture/$rec.json"
done
git -C "$rec_repo" add -A
git -C "$rec_repo" commit --quiet -m "fixture"
bash "$COLLECT" --repo "$rec_repo" --generated-on 2026-09-28 --out "$TEST_TMPDIR/records.json" >/dev/null 2>&1
rec_text="$(cat "$TEST_TMPDIR/records.json")"
assert_contains "family records: a real config file still yields a row" "$rec_text" "real.partner.example"
assert_not_contains "family records: tracked deployment, containers and events records are not sources" "$rec_text" "record.example"

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
