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
bash "$COLLECT" --repo "$date_repo" --out "$TEST_TMPDIR/no-such-dir/out.json" >/dev/null 2>"$TEST_TMPDIR/unwritable.err"
assert_equals "--out: an unwritable path exits 1" "$?" "1"
assert_contains "--out: an unwritable path says so" "$(cat "$TEST_TMPDIR/unwritable.err")" "cannot write --out file"

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
