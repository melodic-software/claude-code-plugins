#!/usr/bin/env bash
# Tests for collect-deployment.sh and render-deployment.sh.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export AWS_SECRET_ACCESS_KEY="SuperSecretFromEnv"
export LEAK="SuperSecretFromEnv"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-deployment.sh"
RENDER="$SCRIPT_DIR/render-deployment.sh"
source "$SCRIPT_DIR/../../../lib/likec4-golden.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
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
}
commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -q -m fixture
}

help_out="$(bash "$COLLECT" --help)"
assert_equals "usage exits 0" "$?" "0"
assert_contains "usage mentions schema" "$help_out" "schema_version"
bad="$(bash "$COLLECT" --nope 2>&1)"
assert_equals "unknown argument exits 2" "$?" "2"
assert_contains "unknown argument names it" "$bad" "unknown argument"

# Fixture credentials expand from variables so no committed line reads as a live credential to a secret scanner.
leak_staging="SuperSecret123"
leak_prod="SuperSecret999"
repo="$TEST_TMPDIR/compose"
init_repo "$repo"
mkdir -p "$repo/deploy/staging" "$repo/deploy/prod"
cat >"$repo/deploy/staging/compose.yaml" <<EOF
services:
  api:
    image: ghcr.io/acme/api:1.0.0
    ports:
      - "8080:8080"
    networks:
      - app
    environment:
      LOG_LEVEL: info
      PASSWORD: ${leak_staging}
    deploy:
      replicas: 1
  worker:
    image: ghcr.io/acme/worker:1.0.0
networks:
  app:
    driver: bridge
EOF
cat >"$repo/deploy/prod/compose.yaml" <<EOF
services:
  api:
    image: ghcr.io/acme/api:1.4.0
    ports:
      - "8080:8080"
    networks:
      - app
    environment:
      LOG_LEVEL: info
      PASSWORD: ${leak_prod}
    deploy:
      replicas: 3
  worker:
    image: ghcr.io/acme/worker:1.0.0
  cron:
    image: ghcr.io/acme/cron:1.0.0
networks:
  app:
    driver: bridge
EOF
commit_all "$repo"
bash "$COLLECT" --repo "$repo" --out "$TEST_TMPDIR/dep.json" --generated-on 2026-09-28
assert_equals "compose collect exits 0" "$?" "0"
rec="$(cat "$TEST_TMPDIR/dep.json")"
assert_contains "compose status drawn" "$rec" '"status": "drawn"'
assert_contains "compose tool" "$rec" '"name":"compose"'
assert_not_contains "no staging secret" "$rec" "$leak_staging"
assert_not_contains "no prod secret" "$rec" "$leak_prod"
assert_not_contains "no env secret" "$rec" "SuperSecretFromEnv"
assert_contains "secret differs" "$rec" "secret parameter PASSWORD differs"
assert_contains "secret differs is its own kind" "$rec" '"change":"secret-differs"'
assert_contains "image differs" "$rec" "ghcr.io/acme/api:1.4.0 -> ghcr.io/acme/api:1.0.0"
assert_contains "replicas differ" "$rec" '"change":"replicas"'
assert_contains "cron added" "$rec" "present only in prod"
sum="$(bash "$RENDER" --record "$TEST_TMPDIR/dep.json" --out "$TEST_TMPDIR/dep-out" --dialect c4-plantuml --diff staging prod)"
assert_equals "render exits 0" "$?" "0"
md="$(cat "$TEST_TMPDIR/dep-out/deployment.md")"
assert_contains "plantuml fence" "$md" '```plantuml'
assert_contains "plantuml include" "$md" "!include <C4/C4_Deployment>"
assert_contains "plantuml environment node" "$md" 'Deployment_Node(env1_prod, "prod", "environment") {'
assert_contains "plantuml container" "$md" '"api", "ghcr.io/acme/api:1.4.0", "replicas 3")'
assert_contains "plantuml runs the container inside its compute node" "$md" $'"compute", "ghcr.io/acme/api:1.4.0") {\n    Container(c1_api, "api", "ghcr.io/acme/api:1.4.0", "replicas 3")\n  }'
assert_contains "the compose placement names its compute node" "$rec" '"node":"app","compute":"prod/api"'
assert_contains "plantuml network relationship" "$md" '"joins")'
assert_contains "plantuml ends" "$md" "@enduml"
assert_not_contains "no mermaid" "$md" "C4Deployment"
assert_contains "names compose" "$md" "compose"
assert_contains "diff table has the image" "$md" "1.4.0 ->"
assert_not_contains "diagram has no secret" "$md" "SuperSecret"
assert_contains "catalog absent note" "$md" "map-containers output was not present"
assert_contains "summary" "$sum" "status=drawn"
assert_contains "summary names the dialect" "$sum" "dialect=c4-plantuml"

bash "$RENDER" --record "$TEST_TMPDIR/dep.json" --out "$TEST_TMPDIR/dep-l" --dialect likec4 >/dev/null
lmd="$(cat "$TEST_TMPDIR/dep-l/deployment.md")"
assert_contains "likec4 fence" "$lmd" '```likec4'
assert_contains "likec4 deployment node kind" "$lmd" "deploymentNode environment"
assert_contains "likec4 environment" "$lmd" "= environment 'prod' {"
assert_contains "likec4 instance" "$lmd" "instanceOf c"
assert_contains "likec4 runs the container inside its compute node" "$lmd" $'= node \'api\' \'compute ghcr.io/acme/api:1.4.0\' {\n      instanceOf c1_api\n    }'
assert_contains "likec4 deployment view" "$lmd" "deployment view view"
assert_equals "likec4 writes one fenced block" "$(grep -c '^```' "$TEST_TMPDIR/dep-l/deployment.md")" "2"
assert_likec4_golden "deployment-compose.c4" "$TEST_TMPDIR/dep-l/deployment.md"

nsum="$(bash "$RENDER" --record "$TEST_TMPDIR/dep.json" --out "$TEST_TMPDIR/dep-n" --diff staging prod)"
assert_equals "dialect none exits 0" "$?" "0"
assert_contains "dialect none is the default" "$nsum" "dialect=none"
assert_contains "dialect none still counts placements" "$nsum" "placements=5"
nmd="$(cat "$TEST_TMPDIR/dep-n/deployment.md")"
assert_contains "dialect none says no view was emitted" "$nmd" "unset (no C4 view emitted)"
assert_contains "dialect none still shows the diff table" "$nmd" "| Change | Environments | Tool | Container | Detail |"
assert_equals "dialect none draws no fence" "$(grep -c '^```' "$TEST_TMPDIR/dep-n/deployment.md")" "0"

for bad_dialect in mermaid structurizr; do
  bash "$RENDER" --record "$TEST_TMPDIR/dep.json" --out "$TEST_TMPDIR/dep-bad" --dialect "$bad_dialect" >/dev/null 2>&1
  assert_equals "--dialect $bad_dialect is a usage error" "$?" "2"
done

# Every emitted value goes through the shared redactor. Each fixture value is a
# fake placeholder. Shapes a secret scanner flags as a literal are assembled at
# runtime so the flagged literal never lands in the repository.
fake="FAKE-NOT-A-SECRET-0000"
sas_sig="s""ig"
gh_tok() { printf 'gh''p_%s' "$(printf "$1%.0s" {1..36})"; }
gh_pat() { printf 'github''_pat_11%s_%s' "$1" "$(printf "$1%.0s" {1..40})"; }
aws_id() { printf 'AK''IAFAKEFAKEFAKE%s' "$1"; }
aws_secret() { printf 'FakeNotASecret0000/FakeNotASecret0000+%s0' "$1"; }
pem() { printf -- '-----BEGIN ''PRIVATE KEY-----MIIFAKE%s-----END PRIVATE KEY-----' "$1"; }
leak_env() {
  local s="$1"
  cat <<EOF
      CS_SQL: "Server=db.example.com;User ID=app;Password=${fake}-SQL${s}"
      CS_BLOB: "DefaultEndpointsProtocol=https;AccountName=fakeacct;AccountKey=${fake}-KEY${s};EndpointSuffix=core.windows.net"
      CS_BUS: "Endpoint=sb://fakebus.servicebus.windows.net/;SharedAccessKeyName=root;SharedAccessKey=${fake}-SAK${s}"
      BLOB_SAS: "https://fakeacct.blob.core.windows.net/c?sv=2022-11-02&${sas_sig}=${fake}-SIG${s}"
      UPSTREAM_A: "$(gh_tok "$s")"
      UPSTREAM_B: "$(gh_pat "$s")"
      AWS_ACCESS_KEY_ID: "$(aws_id "$s")"
      CLOUD_B: "$(aws_secret "$s")"
      SIGNING_KEY: "${fake}-SIGN${s}"
      PEM_BLOB: "$(pem "$s")"
      PARTNER_URL: "https://svc:${fake}-URL${s}@partner.example.com/api"
      AUTH_HEADER: "Authorization: Basic ${fake}-BASIC${s}"
      LOG_LEVEL: level${s}
EOF
}
leak_keys="CS_SQL CS_BLOB CS_BUS BLOB_SAS UPSTREAM_A UPSTREAM_B AWS_ACCESS_KEY_ID CLOUD_B SIGNING_KEY PEM_BLOB PARTNER_URL AUTH_HEADER"
leak_needles=("$fake" "$(gh_tok S)" "$(gh_tok P)" "$(gh_pat S)" "$(gh_pat P)" "$(aws_id S)" "$(aws_id P)"
  "$(aws_secret S)" "$(aws_secret P)" "PRIVATE KEY" "MIIFAKE" "Basic " "${sas_sig}=")
assert_no_leak() {
  local label="$1" text="$2" needle
  for needle in "${leak_needles[@]}"; do
    assert_not_contains "$label has no ${needle:0:12}" "$text" "$needle"
  done
}
repo5="$TEST_TMPDIR/leaks"
init_repo "$repo5"
mkdir -p "$repo5/deploy/staging" "$repo5/deploy/prod" "$repo5/deploy/k8s"
for s in S P; do
  [[ "$s" == S ]] && d=staging || d=prod
  {
    printf 'services:\n  api:\n    image: ghcr.io/acme/api:1.0.0\n    environment:\n'
    leak_env "$s"
  } >"$repo5/deploy/$d/compose.yaml"
done
{
  printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: api\n  namespace: qa\nspec:\n  template:\n    spec:\n      containers:\n        - name: api\n          image: ghcr.io/acme/api:2\n          env:\n'
  printf '            - name: UPSTREAM_A\n              value: "%s"\n' "$(gh_tok K)"
  printf '            - name: CS_BUS\n              value: "Endpoint=sb://fakebus.servicebus.windows.net/;SharedAccessKey=%s-SAKK"\n' "$fake"
  printf '            - name: SIGNING_KEY\n              value: "%s-SIGNK"\n' "$fake"
} >"$repo5/deploy/k8s/app.yaml"
leak_needles+=("$(gh_tok K)")
commit_all "$repo5"
bash "$COLLECT" --repo "$repo5" --out "$TEST_TMPDIR/leaks.json" --generated-on 2026-09-28
assert_equals "leak fixture collect exits 0" "$?" "0"
leakrec="$(cat "$TEST_TMPDIR/leaks.json")"
assert_contains "leak fixture is drawn" "$leakrec" '"status": "drawn"'
for k in $leak_keys; do
  assert_contains "leak fixture records $k" "$leakrec" "\"parameter\":\"$k\""
done
assert_contains "leak fixture keeps a plain value" "$leakrec" '"value":"levelS"'
assert_contains "leak fixture diffs the plain value" "$leakrec" "LOG_LEVEL levelP -> levelS"
assert_no_leak "record" "$leakrec"
leaksum="$(bash "$RENDER" --record "$TEST_TMPDIR/leaks.json" --out "$TEST_TMPDIR/leaks-out" --dialect c4-plantuml --diff staging prod)"
assert_equals "leak fixture render exits 0" "$?" "0"
leakmd="$(cat "$TEST_TMPDIR/leaks-out/deployment.md")"
assert_contains "leak diff table is present" "$leakmd" "LOG_LEVEL levelP -> levelS"
assert_no_leak "diff output" "$leakmd"
assert_no_leak "render summary" "$leaksum"

# The renderer redacts on its own, for a record written by anything else.
cat >"$TEST_TMPDIR/hostile.json" <<EOF
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "subject": "hostile",
  "status": "drawn",
  "reason": "",
  "tools": [
    {"name":"compose","shipped":"yes","evidence":"compose.yaml"}
  ],
  "environments": [
    {"environment":"a","tool":"compose","evidence":"compose.yaml"},
    {"environment":"b","tool":"compose","evidence":"compose.yaml"}
  ],
  "nodes": [
    {"id":"a/api","env":"a","tool":"compose","kind":"compute","name":"h\`\`\`}@enduml'\"","detail":"$(gh_tok S)","evidence":"compose.yaml"},
    {"id":"a/svc-x","env":"a","tool":"kubernetes","kind":"network","name":"svc","detail":"","evidence":"compose.yaml"}
  ],
  "placements": [
    {"container":"api","env":"a","tool":"compose","node":"default","compute":"a/api","image":"https://u:${fake}-IMG@reg.example.com/api:1","replicas":"1","ports":"","networks":"default","evidence":"compose.yaml"},
    {"container":"x\`\`\`}@enduml'\"","env":"a","tool":"compose","node":"default","image":"i\`\`\`'\\\\","replicas":"1","ports":"","networks":"default","evidence":"compose.yaml"}
  ],
  "relationships": [
    {"from":"a/svc-x","to":"api","to_compute":"a/api","env":"a","tool":"kubernetes","label":"routes \`\`\`}@enduml $(gh_tok P)","evidence":"compose.yaml"}
  ],
  "parameters": [],
  "diffs": [
    {"change":"parameter","left":"a","right":"b","tool":"compose","container":"api","detail":"UPSTREAM_A $(gh_tok S) -> $(gh_tok P)"}
  ],
  "catalog": []
}
EOF
for d in likec4 c4-plantuml; do
  hsum="$(bash "$RENDER" --record "$TEST_TMPDIR/hostile.json" --out "$TEST_TMPDIR/hostile-$d" --dialect "$d" --diff a b)"
  assert_equals "hostile record $d render exits 0" "$?" "0"
  hmd="$(cat "$TEST_TMPDIR/hostile-$d/deployment.md")"
  assert_contains "hostile record $d diff row is present" "$hmd" "| parameter |"
  assert_contains "hostile record $d draws the relationship" "$hmd" "$([[ $d == c4-plantuml ]] && echo 'Rel(n2_svc, c1_api, "[redacted]")' || echo '.n2_svc -> env1_a.cn1_')"
  assert_no_leak "hostile $d render" "$hmd$hsum"
  assert_equals "hostile $d name stays inside one fenced block" "$(grep -c '```' "$TEST_TMPDIR/hostile-$d/deployment.md")" "2"
  assert_equals "hostile $d name adds no @enduml" "$(grep -c '@enduml' "$TEST_TMPDIR/hostile-$d/deployment.md")" "$([[ $d == c4-plantuml ]] && echo 1 || echo 0)"
done

# containers catalog
printf '{\n  "schema_version": 1,\n  "containers": [\n    {"name":"api"},\n    {"name":"batch"}\n  ]\n}\n' >"$TEST_TMPDIR/containers.json"
bash "$COLLECT" --repo "$repo" --out "$TEST_TMPDIR/cat.json" --generated-on 2026-09-28 --containers "$TEST_TMPDIR/containers.json"
catrec="$(cat "$TEST_TMPDIR/cat.json")"
assert_contains "api placed" "$catrec" '"catalog":"api","placed":"yes"'
assert_contains "batch unplaced" "$catrec" '"catalog":"batch","placed":"no"'

# bicep plus compose is read, since both are shipped
repo2="$TEST_TMPDIR/both"
init_repo "$repo2"
mkdir -p "$repo2/deploy"
printf 'services:\n  api:\n    image: ghcr.io/acme/api:1\n' >"$repo2/deploy/compose.yaml"
printf "resource web 'Microsoft.Web/sites@2022-03-01' = {\n  name: 'api'\n}\n" >"$repo2/main.bicep"
commit_all "$repo2"
bash "$COLLECT" --repo "$repo2" --out "$TEST_TMPDIR/both.json" --generated-on 2026-09-28
both="$(cat "$TEST_TMPDIR/both.json")"
assert_contains "bicep beside compose is drawn" "$both" '"status": "drawn"'
assert_contains "bicep is a shipped tool" "$both" '"name":"bicep","shipped":"yes"'

# pulumi plus compose is a partial read
printf 'name: web\nruntime: nodejs\n' >"$repo2/Pulumi.yaml"
git -C "$repo2" rm -q main.bicep
commit_all "$repo2"
bash "$COLLECT" --repo "$repo2" --out "$TEST_TMPDIR/both.json" --generated-on 2026-09-28
both="$(cat "$TEST_TMPDIR/both.json")"
assert_contains "partial read" "$both" '"reason": "partial-read"'
assert_contains "names pulumi" "$both" '"name":"pulumi"'
assert_contains "names compose" "$both" '"name":"compose"'
bash "$RENDER" --record "$TEST_TMPDIR/both.json" --out "$TEST_TMPDIR/both-out" --dialect likec4 >/dev/null
bothmd="$(cat "$TEST_TMPDIR/both-out/deployment.md")"
assert_not_contains "partial read draws nothing" "$bothmd" '```'
assert_contains "partial read prose" "$bothmd" "partial read"

# terraform only
repo3="$TEST_TMPDIR/tf"
init_repo "$repo3"
printf 'resource "azurerm_virtual_network" "vnet" {\n  name = "vnet"\n}\n' >"$repo3/net.tf"
commit_all "$repo3"
bash "$COLLECT" --repo "$repo3" --out "$TEST_TMPDIR/tf.json" --generated-on 2026-09-28
tf="$(cat "$TEST_TMPDIR/tf.json")"
assert_contains "terraform with no container resource is drawn" "$tf" '"status": "drawn"'
assert_contains "terraform is a shipped tool" "$tf" '"name":"terraform","shipped":"yes"'
assert_not_contains "no invented node" "$tf" "vnet"

# live
bash "$COLLECT" --repo "$repo" --out "$TEST_TMPDIR/live.json" --live --generated-on 2026-09-28
live="$(cat "$TEST_TMPDIR/live.json")"
assert_contains "live refused" "$live" '"reason": "live-state-requested"'
assert_not_contains "live did not read compose" "$live" "ghcr.io"

# kubernetes and compose both read
repo4="$TEST_TMPDIR/k8s"
init_repo "$repo4"
mkdir -p "$repo4/deploy"
printf 'services:\n  api:\n    image: ghcr.io/acme/api:1\n' >"$repo4/deploy/compose.yaml"
cat >"$repo4/deploy/api.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: prod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: ghcr.io/acme/api:2
          env:
            - name: PASSWORD
              value: SuperSecret123
---
apiVersion: v1
kind: Service
metadata:
  name: api-svc
  namespace: prod
spec:
  selector:
    app: api
  ports:
    - port: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
  namespace: prod
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port:
                  number: 80
EOF
commit_all "$repo4"
bash "$COLLECT" --repo "$repo4" --out "$TEST_TMPDIR/k8s.json" --generated-on 2026-09-28
k8s="$(cat "$TEST_TMPDIR/k8s.json")"
assert_contains "k8s drawn" "$k8s" '"status": "drawn"'
assert_contains "k8s tool" "$k8s" '"name":"kubernetes"'
assert_contains "compose still read" "$k8s" '"name":"compose"'
assert_contains "ingress host" "$k8s" "api.example.com"
assert_not_contains "k8s secret dropped" "$k8s" "SuperSecret123"
bash "$RENDER" --record "$TEST_TMPDIR/k8s.json" --out "$TEST_TMPDIR/k8s-l" --dialect likec4 --env prod >/dev/null
kl="$(cat "$TEST_TMPDIR/k8s-l/deployment.md")"
assert_contains "likec4 ingress node" "$kl" "= node 'api' 'ingress api.example.com'"
assert_contains "likec4 view includes the environment" "$kl" ".**"
assert_likec4_golden "deployment-kubernetes.c4" "$TEST_TMPDIR/k8s-l/deployment.md"
assert_contains "likec4 runs the container inside its workload node" "$kl" $'compute Deployment\' {\n      instanceOf c2_api\n    }'
assert_contains "likec4 draws the Service selector as a relationship" "$kl" "-> env2_prod.cn4_api.c2_api 'selects app=api'"
assert_contains "likec4 draws the Ingress backend as a relationship" "$kl" "-> env2_prod.cn4_api.c2_api 'routes api.example.com'"
assert_contains "the placement names its compute node" "$k8s" '"compute":"prod/wl-api"'
assert_contains "the Service edge is in the record" "$k8s" '{"from":"prod/svc-api-svc","to":"api","to_compute":"prod/wl-api","env":"prod","tool":"kubernetes","label":"selects app=api"'
assert_contains "the Ingress edge is in the record" "$k8s" '{"from":"prod/ing-api","to":"api","to_compute":"prod/wl-api","env":"prod","tool":"kubernetes","label":"routes api.example.com"'
bash "$RENDER" --record "$TEST_TMPDIR/k8s.json" --out "$TEST_TMPDIR/k8s-p" --dialect c4-plantuml --env prod >/dev/null
kp="$(cat "$TEST_TMPDIR/k8s-p/deployment.md")"
assert_contains "plantuml runs the container inside its workload node" "$kp" $'"compute", "Deployment") {\n    Container(c2_api, "api", "ghcr.io/acme/api:2", "replicas 2")\n  }'
assert_contains "plantuml draws the Service selector as Rel" "$kp" 'Rel(n3_api_svc, c2_api, "selects app=api")'
assert_contains "plantuml draws the Ingress backend as Rel" "$kp" 'Rel(n2_api, c2_api, "routes api.example.com")'

# A workload's containers share one node, a Service needs its whole selector to match, an Ingress
# reaches the containers behind each backend once, and nothing crosses a namespace.
repoE="$TEST_TMPDIR/edges"
init_repo "$repoE"
mkdir -p "$repoE/deploy/k8s"
cat >"$repoE/deploy/k8s/web.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: stage
  labels:
    name: ignored
spec:
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
        tier: front
    spec:
      containers:
        - name: app
          image: ghcr.io/acme/app:1
        - name: sidecar
          image: ghcr.io/acme/proxy:1
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: stage
spec:
  selector:
    app: web
---
apiVersion: v1
kind: Service
metadata:
  name: partial
  namespace: stage
spec:
  selector:
    app: web
    tier: back
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: elsewhere
spec:
  selector:
    app: web
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: stage
spec:
  rules:
    - host: web.example.com
      http:
        paths:
          - path: /a
            backend:
              service:
                name: web
                port:
                  number: 80
          - path: /b
            backend:
              service:
                name: web
                port:
                  number: 80
          - path: /c
            backend:
              service:
                name: partial
                port:
                  number: 80
EOF
commit_all "$repoE"
bash "$COLLECT" --repo "$repoE" --out "$TEST_TMPDIR/edges.json" --generated-on 2026-09-28
erec="$(cat "$TEST_TMPDIR/edges.json")"
assert_equals "both containers of a workload run on the one workload node" "$(grep -c '"compute":"stage/wl-web"' <<<"$erec")" "2"
assert_equals "a workload is one compute node" "$(grep -c '"kind":"compute"' <<<"$erec")" "1"
assert_equals "edges: the Service and the Ingress each reach both containers, once" "$(grep -c '^    {"from":' <<<"$erec")" "4"
assert_contains "edges: the Service selects the sidecar" "$erec" '{"from":"stage/svc-web","to":"sidecar"'
assert_contains "edges: the Ingress routes to the app container" "$erec" '{"from":"stage/ing-web","to":"app"'
assert_not_contains "edges: a partial selector match draws nothing" "$erec" '"from":"stage/svc-partial"'
assert_not_contains "edges: a Service in another namespace draws nothing" "$erec" '"from":"elsewhere/'
for d in likec4 c4-plantuml; do
  bash "$RENDER" --record "$TEST_TMPDIR/edges.json" --out "$TEST_TMPDIR/edges-$d" --dialect "$d" >/dev/null
done
assert_contains "likec4: the workload node holds both instances" "$(cat "$TEST_TMPDIR/edges-likec4/deployment.md")" $'{\n      instanceOf c1_app\n      instanceOf c2_sidecar\n    }'
assert_equals "likec4: four relationships" "$(grep -c -- '^  env[0-9]*_stage\.' "$TEST_TMPDIR/edges-likec4/deployment.md")" "4"
assert_equals "plantuml: four Rel lines" "$(grep -c '^Rel(' "$TEST_TMPDIR/edges-c4-plantuml/deployment.md")" "4"
assert_contains "plantuml: both containers sit in the workload node" "$(cat "$TEST_TMPDIR/edges-c4-plantuml/deployment.md")" $'"compute", "Deployment") {\n    Container(c1_app,'

# flat record
printf '%s\n' '{"schema_version":1}' >"$TEST_TMPDIR/flat.json"
set +e
bash "$RENDER" --record "$TEST_TMPDIR/flat.json" --out "$TEST_TMPDIR/flat-out" >/dev/null 2>"$TEST_TMPDIR/flat-err"
frc=$?
set +e
assert_equals "flat record exits 1" "$frc" "1"
assert_not_contains "flat writes nothing" "$(ls "$TEST_TMPDIR/flat-out" 2>/dev/null || true)" "deployment.md"

# A sidecar is its own placement; standalone credential words redact; a tracked
# symlink to an untracked file is not a source.
repo6="$TEST_TMPDIR/sidecar"
init_repo "$repo6"
mkdir -p "$repo6/deploy/k8s" "$repo6/deploy/prod"
{
  printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: web\n  namespace: prod\nspec:\n  template:\n    spec:\n      containers:\n'
  printf '        - name: app\n          image: ghcr.io/acme/app:1\n          env:\n'
  printf '            - name: RABBITMQ_DEFAULT_PASS\n              value: "%s-PASS6"\n' "$fake"
  printf '            - name: MAPS_KEY\n              value: "%s-MAPS6"\n' "$fake"
  printf '        - name: sidecar\n          image: ghcr.io/acme/proxy:1\n          env:\n'
  pw="pass""word"
  printf '            - name: SPRING_APPLICATION_JSON\n              value: '"'"'{"spring.datasource.%s":"%s-JSON6"}'"'"'\n' "$pw" "$fake"
} >"$repo6/deploy/k8s/web.yaml"
printf 'outside.yaml\n' >"$repo6/.gitignore"
printf 'services:\n  leak:\n    image: leak.example/linked:1\n' >"$repo6/outside.yaml"
ln -s ../../outside.yaml "$repo6/deploy/prod/compose.yaml"
commit_all "$repo6"
bash "$COLLECT" --repo "$repo6" --out "$TEST_TMPDIR/sidecar.json" --generated-on 2026-09-28 >/dev/null
side="$(cat "$TEST_TMPDIR/sidecar.json")"
assert_contains "sidecar: the app container is placed" "$side" '{"container":"app","env":"prod"'
assert_contains "sidecar: the sidecar container is placed" "$side" '{"container":"sidecar","env":"prod"'
assert_contains "sidecar: the sidecar keeps its own image" "$side" '{"container":"sidecar","env":"prod","tool":"kubernetes","node":"prod","compute":"prod/wl-web","image":"ghcr.io/acme/proxy:1"'
for needle in PASS6 MAPS6 JSON6; do
  assert_not_contains "sidecar: $needle is redacted in the record" "$side" "$needle"
done
assert_not_contains "symlink: a tracked link to an untracked file is not a source" "$side" "leak.example"
bash "$RENDER" --record "$TEST_TMPDIR/sidecar.json" --out "$TEST_TMPDIR/sidecar-out" >/dev/null
for needle in PASS6 MAPS6 JSON6; do
  assert_not_contains "sidecar: $needle is redacted in the markdown" "$(cat "$TEST_TMPDIR/sidecar-out/deployment.md")" "$needle"
done

# Structural Helm detection: a double-brace marker alone is not Helm.
tmpl='{{.State.Health.Status}}'
gha="$(printf '%s{{ secrets.TOKEN }}' '$')"
repo7="$TEST_TMPDIR/tmpl"
init_repo "$repo7"
mkdir -p "$repo7/deploy" "$repo7/.github/workflows"
cat >"$repo7/deploy/compose.yaml" <<EOF
services:
  api:
    image: ghcr.io/acme/api:1
    healthcheck:
      test: ["CMD", "sh", "-c", "test \"${tmpl}\" = healthy"]
EOF
printf 'jobs:\n  b:\n    steps:\n      - run: echo %s\n' "$gha" >"$repo7/.github/workflows/ci.yml"
commit_all "$repo7"
bash "$COLLECT" --repo "$repo7" --out "$TEST_TMPDIR/tmpl.json" --generated-on 2026-09-28
tmplrec="$(cat "$TEST_TMPDIR/tmpl.json")"
assert_contains "compose beside a workflow with a template expression draws" "$tmplrec" '"status": "drawn"'
assert_not_contains "a template expression alone is not helm" "$tmplrec" '"name":"helm"'
assert_contains "compose with a Go-template healthcheck places the service" "$tmplrec" '"container":"api"'

repo8="$TEST_TMPDIR/helm"
init_repo "$repo8"
mkdir -p "$repo8/chart/templates"
printf 'apiVersion: v2\nname: web\nversion: 0.1.0\n' >"$repo8/chart/Chart.yaml"
printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: {{ .Release.Name }}\n' >"$repo8/chart/templates/deploy.yaml"
commit_all "$repo8"
bash "$COLLECT" --repo "$repo8" --out "$TEST_TMPDIR/helm.json" --generated-on 2026-09-28
helmrec="$(cat "$TEST_TMPDIR/helm.json")"
assert_contains "a real helm chart declines" "$helmrec" '"reason": "adapter-not-shipped"'
assert_contains "a real helm chart names helm" "$helmrec" '"name":"helm"'

repo9="$TEST_TMPDIR/tmpl-name"
init_repo "$repo9"
mkdir -p "$repo9/deploy"
printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: {{ .Release.Name }}\n' >"$repo9/deploy/web.yaml"
commit_all "$repo9"
bash "$COLLECT" --repo "$repo9" --out "$TEST_TMPDIR/tmpl-name.json" --generated-on 2026-09-28
assert_contains "a templated manifest name is refused, not half-read" "$(cat "$TEST_TMPDIR/tmpl-name.json")" '"reason": "kubernetes-unreadable"'

# A base file and its override merge into one environment named for the directory.
leak_override="OverrideSecret555"
repoL="$TEST_TMPDIR/layered"
init_repo "$repoL"
mkdir -p "$repoL/deploy/prod"
cat >"$repoL/deploy/prod/compose.yaml" <<EOF
services:
  api:
    image: ghcr.io/acme/api:1.0.0
    ports:
      - "8080:8080"
    networks:
      - app
    environment:
      LOG_LEVEL: info
      REGION: eu
    deploy:
      replicas: 1
  worker:
    image: ghcr.io/acme/worker:1.0.0
networks:
  app:
    driver: bridge
EOF
cat >"$repoL/deploy/prod/compose.override.yaml" <<EOF
services:
  api:
    image: ghcr.io/acme/api:2.0.0
    ports:
      - "8080:8080"
      - "9090:9090"
    environment:
      - LOG_LEVEL=debug
      - PASSWORD=${leak_override}
    deploy:
      replicas: 3
  cron:
    image: ghcr.io/acme/cron:1.0.0
networks:
  app:
    internal: true
EOF
commit_all "$repoL"
bash "$COLLECT" --repo "$repoL" --out "$TEST_TMPDIR/layered.json" --generated-on 2026-09-28
layerrec="$(cat "$TEST_TMPDIR/layered.json")"
assert_contains "base plus override draws" "$layerrec" '"status": "drawn"'
assert_contains "base plus override is one environment named for the directory" "$layerrec" '{"environment":"prod","tool":"compose","evidence":"deploy/prod/compose.yaml, deploy/prod/compose.override.yaml"}'
assert_equals "no environment is named override" "$(grep -c '"environment":"' "$TEST_TMPDIR/layered.json")" "1"
assert_contains "the override image wins" "$layerrec" '"container":"api","env":"prod","tool":"compose","node":"app","compute":"prod/api","image":"ghcr.io/acme/api:2.0.0","replicas":"3","ports":"8080:8080,9090:9090"'
assert_contains "a service only in the base stays" "$layerrec" '"container":"worker","env":"prod"'
assert_contains "a service only in the override is added" "$layerrec" '"container":"cron","env":"prod"'
assert_contains "an environment key set in both takes the override value" "$layerrec" '"parameter":"LOG_LEVEL","env":"prod","tool":"compose","container":"api","value":"debug"'
assert_equals "an environment key set in both is one parameter" "$(grep -c '"parameter":"LOG_LEVEL"' "$TEST_TMPDIR/layered.json")" "1"
assert_contains "a base-only environment key is kept" "$layerrec" '"parameter":"REGION","env":"prod","tool":"compose","container":"api","value":"eu"'
assert_contains "an override-only secret parameter is redacted" "$layerrec" '"parameter":"PASSWORD","env":"prod","tool":"compose","container":"api","value":"","redacted":"yes"'
assert_not_contains "a secret set only in the override does not leak" "$layerrec" "$leak_override"
assert_contains "the override network exposure wins" "$layerrec" '"kind":"network","name":"app","detail":"internal"'
bash "$RENDER" --record "$TEST_TMPDIR/layered.json" --out "$TEST_TMPDIR/layered-out" --dialect c4-plantuml >/dev/null
layermd="$(cat "$TEST_TMPDIR/layered-out/deployment.md")"
assert_not_contains "a secret set only in the override is not rendered" "$layermd" "$leak_override"

# A file with no declared place in the merge is refused by name, never guessed.
refuse_layers() {
  local label="$1" want="$2" env_line="$3" f
  shift 3
  rm -rf "$repoL"
  init_repo "$repoL"
  for f in "$@"; do
    printf 'services:\n  api:\n    image: ghcr.io/acme/api:1\n' >"$repoL/$f"
  done
  [[ -z "$env_line" ]] || printf '%s\n' "$env_line" >"$repoL/.env"
  commit_all "$repoL"
  bash "$COLLECT" --repo "$repoL" --out "$TEST_TMPDIR/layered.json" --generated-on 2026-09-28
  layerrec="$(cat "$TEST_TMPDIR/layered.json")"
  assert_contains "$label is refused by name" "$layerrec" "\"reason\": \"compose-not-mergeable:$want\""
  assert_not_contains "$label draws no environment" "$layerrec" '"environment":"'
}
refuse_layers "a variant beside a base with no listed order" "docker-compose.prod.yml" "" docker-compose.yml docker-compose.prod.yml
refuse_layers "a variant beside a base and override" "compose.prod.yaml" "" compose.yaml compose.override.yaml compose.prod.yaml
refuse_layers "an override with no base" "compose.override.yaml" "" compose.override.yaml
refuse_layers "a second base file" "docker-compose.yml" "" compose.yaml docker-compose.yml
refuse_layers "a COMPOSE_FILE entry that is not tracked" "compose.gone.yaml" "COMPOSE_FILE=compose.yaml:compose.gone.yaml" compose.yaml
refuse_layers "a variant the COMPOSE_FILE list leaves out" "compose.prod.yaml" "COMPOSE_FILE=compose.yaml" compose.yaml compose.prod.yaml

# Variant files a tracked .env COMPOSE_FILE lists merge in that order.
rm -rf "$repoL"
init_repo "$repoL"
printf 'services:\n  api:\n    image: ghcr.io/acme/api:1\n    environment:\n      MODE: base\n' >"$repoL/compose.yaml"
printf 'services:\n  api:\n    image: ghcr.io/acme/api:2\n    environment:\n      MODE: prod\n' >"$repoL/compose.prod.yaml"
printf 'services:\n  api:\n    image: ghcr.io/acme/api:3\n' >"$repoL/compose.hotfix.yaml"
printf 'COMPOSE_FILE=compose.yaml:compose.prod.yaml:compose.hotfix.yaml\n' >"$repoL/.env"
commit_all "$repoL"
bash "$COLLECT" --repo "$repoL" --out "$TEST_TMPDIR/listed.json" --generated-on 2026-09-28
listedrec="$(cat "$TEST_TMPDIR/listed.json")"
assert_equals "listed variants are one environment" "$(grep -c '"environment":"' "$TEST_TMPDIR/listed.json")" "1"
assert_contains "listed variants merge in the listed order" "$listedrec" '"image":"ghcr.io/acme/api:3"'
assert_contains "a listed variant overrides an environment key" "$listedrec" '"parameter":"MODE","env":"default","tool":"compose","container":"api","value":"prod"'

# A reset or override tag cannot be merged by this reader, so the file is refused by name.
rm -rf "$repoL"
init_repo "$repoL"
printf 'services:\n  api:\n    image: x:1\n    ports:\n      - "80:80"\n' >"$repoL/compose.yaml"
printf 'services:\n  api:\n    ports: !reset []\n' >"$repoL/compose.override.yaml"
commit_all "$repoL"
bash "$COLLECT" --repo "$repoL" --out "$TEST_TMPDIR/layered.json" --generated-on 2026-09-28
assert_contains "a !reset tag is refused by file name" "$(cat "$TEST_TMPDIR/layered.json")" '"reason": "compose-not-mergeable:compose.override.yaml"'
repoV="$TEST_TMPDIR/variants"
init_repo "$repoV"
printf 'services:\n  api:\n    image: ghcr.io/acme/api:1\n' >"$repoV/compose.staging.yaml"
printf 'services:\n  api:\n    image: ghcr.io/acme/api:2\n' >"$repoV/compose.prod.yaml"
commit_all "$repoV"
bash "$COLLECT" --repo "$repoV" --out "$TEST_TMPDIR/variants.json" --generated-on 2026-09-28
assert_contains "standalone variants without a base are environments" "$(cat "$TEST_TMPDIR/variants.json")" '"environment":"prod"'

# Declining tools: each shape is recognized, so a two-tool repository is never half-read.
arm_schema='https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
declining_fixture() {
  local dir="$1" file="$2" content="$3"
  rm -rf "$dir"
  init_repo "$dir"
  mkdir -p "$dir/$(dirname "$file")"
  printf '%s\n' "$content" >"$dir/$file"
  commit_all "$dir"
}
check_declines() {
  local label="$1" tool="$2" file="$3" content="$4" dir="$TEST_TMPDIR/decl" rec
  declining_fixture "$dir" "$file" "$content"
  bash "$COLLECT" --repo "$dir" --out "$TEST_TMPDIR/decl.json" --generated-on 2026-09-28
  rec="$(cat "$TEST_TMPDIR/decl.json")"
  assert_contains "$label declines" "$rec" '"reason": "adapter-not-shipped"'
  assert_contains "$label names $tool" "$rec" "\"name\":\"$tool\""
  declining_fixture "$dir" "$file" "$content"
  printf 'services:\n  api:\n    image: ghcr.io/acme/api:1\n' >"$dir/compose.yaml"
  git -C "$dir" add -A && git -C "$dir" commit -q -m compose
  bash "$COLLECT" --repo "$dir" --out "$TEST_TMPDIR/decl.json" --generated-on 2026-09-28
  assert_contains "$label beside compose is a partial read" "$(cat "$TEST_TMPDIR/decl.json")" '"reason": "partial-read"'
}
check_declines "a Pulumi project" pulumi Pulumi.yaml "name: web"
check_declines "a Kustomize overlay" kustomize deploy/kustomization.yaml "resources: []"
declining_fixture "$TEST_TMPDIR/notarm" package.json "$(printf '{"%sschema": "https://json.schemastore.org/package.json"}' '$')"
bash "$COLLECT" --repo "$TEST_TMPDIR/notarm" --out "$TEST_TMPDIR/notarm.json" --generated-on 2026-09-28
assert_contains "an unrelated json schema is not ARM" "$(cat "$TEST_TMPDIR/notarm.json")" '"reason": "no-declared-iac"'

declining_fixture "$TEST_TMPDIR/cfn-word" tool.sh "grep -q AWSTemplateFormatVersion \"\$1\""
bash "$COLLECT" --repo "$TEST_TMPDIR/cfn-word" --out "$TEST_TMPDIR/cfn-word.json" --generated-on 2026-09-28
assert_contains "a script that names the CloudFormation key is not a template" "$(cat "$TEST_TMPDIR/cfn-word.json")" '"reason": "no-declared-iac"'
declining_fixture "$TEST_TMPDIR/cfn" stack.yaml "AWSTemplateFormatVersion: '2010-09-09'"
bash "$COLLECT" --repo "$TEST_TMPDIR/cfn" --out "$TEST_TMPDIR/cfn.json" --generated-on 2026-09-28
assert_contains "a CloudFormation template declines" "$(cat "$TEST_TMPDIR/cfn.json")" '"name":"cloudformation"'

# --diff names are validated like --env.
bash "$RENDER" --record "$TEST_TMPDIR/dep.json" --out "$TEST_TMPDIR/dep-bad-diff" --diff staging prdo >/dev/null
assert_equals "--diff with an unknown environment exits 3" "$?" "3"
assert_contains "--diff refusal lists the environments" "$(cat "$TEST_TMPDIR/dep-bad-diff/deployment.md")" "- prod"
bash "$RENDER" --record "$TEST_TMPDIR/dep.json" --out "$TEST_TMPDIR/dep-good-diff" --diff staging prod >/dev/null
assert_equals "--diff with known environments exits 0" "$?" "0"

# Kubernetes namespaces are environments. Every difference kind is reported,
# a parameter in one namespace only is added or removed, and a secret-shaped
# value never prints.
ns_pw_a="NsStagePw-4471"
ns_pw_b="NsProdPw-9082"
ns_pw_only="NsOnlyProdPw-5530"
repo7="$TEST_TMPDIR/k8s-ns"
init_repo "$repo7"
mkdir -p "$repo7/deploy"
k8s_ns_manifest() {
  local ns="$1" image="$2" replicas="$3" port="$4" level="$5" pw="$6"
  shift 6
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: ${ns}
spec:
  replicas: ${replicas}
  template:
    spec:
      containers:
        - name: api
          image: ${image}
          ports:
            - containerPort: ${port}
          env:
            - name: LOG_LEVEL
              value: ${level}
            - name: PASSWORD
              value: ${pw}
$*
EOF
}
k8s_ns_manifest staging ghcr.io/acme/api:1.0.0 1 8080 info "$ns_pw_a" "            - name: STAGING_ONLY
              value: yes" >"$repo7/deploy/staging.yaml"
k8s_ns_manifest prod ghcr.io/acme/api:1.4.0 3 9090 warn "$ns_pw_b" "            - name: SIGNING_KEY
              value: ${ns_pw_only}
            - name: FEATURE_X
              value: on
            - name: DB_URL
              valueFrom:
                secretKeyRef:
                  name: db-creds
                  key: url" >"$repo7/deploy/prod.yaml"
commit_all "$repo7"
bash "$COLLECT" --repo "$repo7" --out "$TEST_TMPDIR/k8s-ns.json" --generated-on 2026-09-28
assert_equals "k8s namespace collect exits 0" "$?" "0"
nsrec="$(cat "$TEST_TMPDIR/k8s-ns.json")"
assert_contains "k8s namespace record is drawn" "$nsrec" '"status": "drawn"'
assert_contains "k8s ports are captured" "$nsrec" '"ports":"8080"'
assert_contains "k8s image differs" "$nsrec" "ghcr.io/acme/api:1.4.0 -> ghcr.io/acme/api:1.0.0"
assert_contains "k8s replicas differ" "$nsrec" '"change":"replicas"'
assert_contains "k8s replicas detail" "$nsrec" "3 -> 1"
assert_contains "k8s ports differ" "$nsrec" '"detail":"9090 -> 8080"'
assert_contains "k8s plain parameter differs" "$nsrec" "LOG_LEVEL warn -> info"
assert_contains "k8s parameter only in prod is removed" "$nsrec" '"change":"parameter-removed"'
assert_contains "k8s removed parameter names it" "$nsrec" "FEATURE_X on present only in prod"
assert_contains "k8s parameter only in staging is added" "$nsrec" "STAGING_ONLY yes present only in staging"
assert_contains "k8s secret differs" "$nsrec" "secret parameter PASSWORD differs"
assert_contains "k8s secret differs is its own kind" "$nsrec" '"change":"secret-differs"'
assert_contains "k8s valueFrom reference in one namespace is reported" "$nsrec" "secret parameter DB_URL present only in prod"
assert_not_contains "k8s valueFrom secret name is not read as a parameter" "$nsrec" "\"parameter\":\"db-creds\""
assert_contains "k8s secret only in one namespace is removed" "$nsrec" "secret parameter SIGNING_KEY present only in prod"
for v in "$ns_pw_a" "$ns_pw_b" "$ns_pw_only"; do
  assert_not_contains "k8s record has no secret value" "$nsrec" "$v"
done
bash "$RENDER" --record "$TEST_TMPDIR/k8s-ns.json" --out "$TEST_TMPDIR/k8s-ns-out" --diff staging prod >/dev/null
nsmd="$(cat "$TEST_TMPDIR/k8s-ns-out/deployment.md")"
assert_contains "diff section names the compared kinds" "$nsmd" "Kinds compared: container added or removed, image, replicas, ports, network or Ingress added or removed"
assert_contains "diff section names network and Ingress kinds" "$nsmd" "network or Ingress added or removed"
for v in "$ns_pw_a" "$ns_pw_b" "$ns_pw_only"; do
  assert_not_contains "k8s diff table has no secret value" "$nsmd" "$v"
done

# Compose parameter presence, and an empty diff that names what it looked for.
repo8="$TEST_TMPDIR/compose-presence"
init_repo "$repo8"
mkdir -p "$repo8/deploy/a" "$repo8/deploy/b" "$repo8/deploy/c"
printf 'services:\n  api:\n    image: x:1\n    environment:\n      ONLY_A: one\n      KEEP: same\n' >"$repo8/deploy/a/compose.yaml"
printf 'services:\n  api:\n    image: x:1\n    ports:\n      - "80:80"\n    environment:\n      ONLY_B: two\n      KEEP: same\n' >"$repo8/deploy/b/compose.yaml"
printf 'services:\n  api:\n    image: x:1\n    environment:\n      ONLY_A: one\n      KEEP: same\n' >"$repo8/deploy/c/compose.yaml"
commit_all "$repo8"
bash "$COLLECT" --repo "$repo8" --out "$TEST_TMPDIR/presence.json" --generated-on 2026-09-28
prec="$(cat "$TEST_TMPDIR/presence.json")"
assert_contains "compose parameter only in a is removed" "$prec" "ONLY_A one present only in a"
assert_contains "compose parameter only in b is added" "$prec" "ONLY_B two present only in b"
assert_contains "compose port declared in one environment differs" "$prec" '"detail":"none -> 80:80"'
assert_not_contains "a shared parameter is not a difference" "$prec" "KEEP same present"
bash "$RENDER" --record "$TEST_TMPDIR/presence.json" --out "$TEST_TMPDIR/presence-out" --diff a c >/dev/null
pmd="$(cat "$TEST_TMPDIR/presence-out/deployment.md")"
assert_contains "an empty diff names the kinds it looked for" "$pmd" "No differences of these kinds: container added or removed, image,"
assert_not_contains "an empty diff prints no bare none row" "$pmd" "| none |"

# Two environments that differ only in networks and Ingress hosts.
repo9="$TEST_TMPDIR/nodes-only"
init_repo "$repo9"
mkdir -p "$repo9/deploy/a" "$repo9/deploy/b"
printf 'services:\n  api:\n    image: x:1\nnetworks:\n  front:\n  shared:\n' >"$repo9/deploy/a/compose.yaml"
printf 'services:\n  api:\n    image: x:1\nnetworks:\n  back:\n    internal: true\n  shared:\n' >"$repo9/deploy/b/compose.yaml"
commit_all "$repo9"
bash "$COLLECT" --repo "$repo9" --out "$TEST_TMPDIR/nodes-compose.json" --generated-on 2026-09-28
ncrec="$(cat "$TEST_TMPDIR/nodes-compose.json")"
assert_contains "compose network only in a is removed" "$ncrec" '"change":"network-removed"'
assert_contains "compose removed network names it" "$ncrec" '"container":"front","detail":"network present only in a"'
assert_contains "compose network only in b is added" "$ncrec" '"container":"back","detail":"network present only in b"'
assert_not_contains "a shared network is not a difference" "$ncrec" '"container":"shared"'

k8s_nodes_manifest() {
  local ns="$1" host="$2" extra="$3"
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: ${ns}
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: api
          image: x:1
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
  namespace: ${ns}
spec:
  rules:
    - host: ${host}
${extra}
EOF
}
repo10="$TEST_TMPDIR/k8s-nodes-only"
init_repo "$repo10"
mkdir -p "$repo10/deploy"
k8s_nodes_manifest stage stage.example.com "" >"$repo10/deploy/stage.yaml"
k8s_nodes_manifest prod prod.example.com "" >"$repo10/deploy/prod.yaml"
printf -- '---\napiVersion: v1\nkind: Service\nmetadata:\n  name: cache\n  namespace: prod\nspec:\n  ports:\n    - port: 6379\n' >>"$repo10/deploy/prod.yaml"
commit_all "$repo10"
bash "$COLLECT" --repo "$repo10" --out "$TEST_TMPDIR/nodes-k8s.json" --generated-on 2026-09-28
nkrec="$(cat "$TEST_TMPDIR/nodes-k8s.json")"
assert_contains "k8s Ingress host differs" "$nkrec" '"change":"ingress","left":"prod","right":"stage","tool":"kubernetes","container":"api","detail":"prod.example.com -> stage.example.com"'
assert_contains "k8s Service only in prod is a network removed" "$nkrec" '"container":"cache","detail":"network present only in prod"'
bash "$RENDER" --record "$TEST_TMPDIR/nodes-k8s.json" --out "$TEST_TMPDIR/nodes-k8s-out" --diff prod stage >/dev/null
nkmd="$(cat "$TEST_TMPDIR/nodes-k8s-out/deployment.md")"
assert_contains "rendered diff lists the Ingress row" "$nkmd" "prod.example.com -> stage.example.com"
assert_contains "rendered diff lists the network row" "$nkmd" "network present only in prod"
assert_not_contains "a node diff is not an empty diff" "$nkmd" "No differences of these kinds"

# Terraform: <env>.tfvars environments over one root, .tf and .tf.json alike.
repoT="$TEST_TMPDIR/tf-envs"
init_repo "$repoT"
mkdir -p "$repoT/infra"
cat >"$repoT/infra/variables.tf" <<'EOF'
variable "api_tag" {
  type    = string
  default = "1.0.0"
}
variable "replicas" {
  default = 1
}
EOF
cat >"$repoT/infra/main.tf" <<'EOF'
# The cluster the service runs on.
resource "aws_ecs_cluster" "main" {
  name = "acme"
}

resource "aws_ecs_task_definition" "api" {
  family = "api"
  container_definitions = jsonencode([
    {
      name         = "api"
      image        = "ghcr.io/acme/api:${var.api_tag}"
      portMappings = [{ containerPort = 8080 }]
      environment = [
        { name = "LOG_LEVEL", value = "info" },
        { name = "REGION", value = local.region }
      ]
    },
    {
      name  = "sidecar"
      image = "ghcr.io/acme/proxy:2"
    }
  ])
}

resource "aws_ecs_service" "api" {
  name            = "api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.replicas
}

resource "aws_ecs_service" "legacy" {
  name            = "legacy"
  task_definition = "arn:aws:ecs:eu-west-1:000000000000:task-definition/legacy:3"
}

resource "aws_ecs_task_definition" "batch" {
  family                = "batch"
  container_definitions = <<DEFS
[
  {"name": "batch", "image": "ghcr.io/acme/batch:1", "environment": [{"name": "MODE", "value": "nightly"}]}
]
DEFS
}
EOF
cat >"$repoT/infra/k8s.tf" <<'EOF'
resource "kubernetes_deployment" "web" {
  metadata {
    name = "web"
  }
  spec {
    replicas = 2
    template {
      metadata {
        labels = { app = "web" }
      }
      spec {
        container {
          name  = "web"
          image = var.web_image
        }
      }
    }
  }
}
EOF
cat >"$repoT/infra/run.tf.json" <<'EOF'
{
  "resource": {
    "google_cloud_run_v2_service": {
      "worker": {
        "name": "worker",
        "template": {
          "containers": [
            {"image": "ghcr.io/acme/worker:${var.api_tag}", "ports": {"container_port": 9090}}
          ],
          "scaling": {"min_instance_count": 2}
        }
      }
    }
  }
}
EOF
# An auto-loaded file outranks terraform.tfvars, and neither is an environment.
printf 'api_tag = "0.1.0"\n' >"$repoT/infra/terraform.tfvars"
printf 'api_tag = "1.0.0"\n' >"$repoT/infra/common.auto.tfvars"
printf 'replicas = 1\n' >"$repoT/infra/staging.tfvars"
printf 'api_tag  = "1.4.0"\nreplicas = 3\n' >"$repoT/infra/prod.tfvars"
commit_all "$repoT"
bash "$COLLECT" --repo "$repoT" --out "$TEST_TMPDIR/tf-envs.json" --generated-on 2026-09-28
assert_equals "terraform collect exits 0" "$?" "0"
tfrec="$(cat "$TEST_TMPDIR/tf-envs.json")"
assert_contains "terraform record is drawn" "$tfrec" '"status": "drawn"'
assert_contains "terraform is shipped" "$tfrec" '"name":"terraform","shipped":"yes"'
assert_contains "a tfvars file is an environment" "$tfrec" '"environment":"prod","tool":"terraform"'
assert_contains "the other tfvars file is an environment" "$tfrec" '"environment":"staging","tool":"terraform"'
assert_contains "an ECS cluster is a compute node" "$tfrec" '"id":"prod/aws_ecs_cluster.main","env":"prod","tool":"terraform","kind":"compute","name":"acme","detail":"aws_ecs_cluster"'
assert_contains "a task definition container is placed on its service's cluster" "$tfrec" '"container":"api","env":"prod","tool":"terraform","node":"prod/aws_ecs_cluster.main","compute":"prod/aws_ecs_cluster.main","image":"ghcr.io/acme/api:1.4.0","replicas":"3","ports":"8080"'
assert_contains "an auto tfvars file outranks terraform.tfvars" "$tfrec" '"container":"api","env":"staging","tool":"terraform","node":"staging/aws_ecs_cluster.main","compute":"staging/aws_ecs_cluster.main","image":"ghcr.io/acme/api:1.0.0","replicas":"1"'
assert_contains "a second container of the task is its own placement" "$tfrec" '"container":"sidecar","env":"prod"'
assert_contains "a local is recorded as unresolved" "$tfrec" '"parameter":"REGION","env":"prod","tool":"terraform","container":"api","value":"unresolved:local.region"'
assert_contains "a heredoc container definition is read" "$tfrec" '"container":"batch","env":"prod","tool":"terraform","node":"prod","compute":"","image":"ghcr.io/acme/batch:1","replicas":"undeclared"'
assert_contains "a heredoc environment entry is a parameter" "$tfrec" '"parameter":"MODE","env":"prod","tool":"terraform","container":"batch","value":"nightly"'
assert_contains "an undeclared variable is unresolved, not evaluated" "$tfrec" '"container":"web","env":"prod","tool":"terraform","node":"prod/kubernetes_deployment.web","compute":"prod/kubernetes_deployment.web","image":"unresolved:var.web_image","replicas":"2"'
assert_contains "a tf.json Cloud Run service is placed" "$tfrec" '"container":"worker","env":"prod","tool":"terraform","node":"prod","compute":"","image":"ghcr.io/acme/worker:1.4.0","replicas":"2","ports":"9090"'
assert_contains "terraform image diff" "$tfrec" '"change":"image","left":"prod","right":"staging","tool":"terraform","container":"api","detail":"ghcr.io/acme/api:1.4.0 -> ghcr.io/acme/api:1.0.0"'
assert_contains "terraform replicas diff" "$tfrec" '"change":"replicas","left":"prod","right":"staging","tool":"terraform","container":"api","detail":"3 -> 1"'
assert_contains "a service whose task definition is not declared keeps the reference unresolved" "$tfrec" '"container":"legacy","env":"prod","tool":"terraform","node":"prod","compute":"","image":"unresolved:arn:aws:ecs:eu-west-1:000000000000:task-definition/legacy:3"'
assert_not_contains "a tfvars file is not a container" "$tfrec" '"container":"replicas"'
assert_not_contains "an auto-loaded tfvars file is not an environment" "$tfrec" '"environment":"common.auto"'
assert_not_contains "terraform.tfvars is not an environment" "$tfrec" '"environment":"terraform"'
bash "$RENDER" --record "$TEST_TMPDIR/tf-envs.json" --out "$TEST_TMPDIR/tf-envs-out" --dialect likec4 --env prod >/dev/null
tfmd="$(cat "$TEST_TMPDIR/tf-envs-out/deployment.md")"
assert_contains "likec4 runs the ECS container inside the cluster" "$tfmd" $'= node \'acme\' \'compute aws_ecs_cluster\' {\n      instanceOf c'
bash "$RENDER" --record "$TEST_TMPDIR/tf-envs.json" --out "$TEST_TMPDIR/tf-envs-puml" --dialect c4-plantuml >/dev/null
assert_contains "plantuml runs the ECS container inside the cluster" "$(cat "$TEST_TMPDIR/tf-envs-puml/deployment.md")" $'"acme", "compute", "aws_ecs_cluster") {\n    Container('

# Terraform: a module-only root per envs/<env>/ directory follows a local module source.
repoM="$TEST_TMPDIR/tf-modules"
init_repo "$repoM"
mkdir -p "$repoM/envs/staging" "$repoM/envs/prod" "$repoM/modules/app"
printf 'module "app" {\n  source = "../../modules/app"\n  image  = "ghcr.io/acme/web:1"\n}\n' >"$repoM/envs/staging/main.tf"
printf 'module "app" {\n  source = "../../modules/app"\n  image  = var.web_image\n}\n' >"$repoM/envs/prod/main.tf"
printf 'variable "web_image" {\n  default = "ghcr.io/acme/web:2"\n}\n' >"$repoM/envs/prod/variables.tf"
cat >"$repoM/modules/app/main.tf" <<'EOF'
variable "image" {}

resource "azurerm_container_app_environment" "env" {
  name = "acme-env"
}

resource "azurerm_container_app" "web" {
  name                         = "web"
  container_app_environment_id = azurerm_container_app_environment.env.id
  template {
    min_replicas = 1
    container {
      name  = "web"
      image = var.image
      env {
        name  = "MODE"
        value = "web"
      }
      env {
        name        = "DB_URL"
        secret_name = "db-url"
      }
    }
  }
  ingress {
    target_port = 80
  }
}
EOF
commit_all "$repoM"
bash "$COLLECT" --repo "$repoM" --out "$TEST_TMPDIR/tf-modules.json" --generated-on 2026-09-28
tmrec="$(cat "$TEST_TMPDIR/tf-modules.json")"
assert_contains "a module-only root is drawn" "$tmrec" '"status": "drawn"'
assert_contains "an envs directory names the environment" "$tmrec" '"environment":"prod","tool":"terraform"'
assert_not_contains "a module directory is not an environment" "$tmrec" '"environment":"app"'
assert_contains "a module environment resource is a compute node" "$tmrec" '"id":"prod/module.app.azurerm_container_app_environment.env","env":"prod","tool":"terraform","kind":"compute","name":"acme-env"'
assert_contains "a module argument that is a root variable resolves" "$tmrec" '"container":"web","env":"prod","tool":"terraform","node":"prod/module.app.azurerm_container_app_environment.env","compute":"prod/module.app.azurerm_container_app_environment.env","image":"ghcr.io/acme/web:2","replicas":"1","ports":"80"'
assert_contains "a literal module argument resolves" "$tmrec" '"container":"web","env":"staging","tool":"terraform","node":"staging/module.app.azurerm_container_app_environment.env","compute":"staging/module.app.azurerm_container_app_environment.env","image":"ghcr.io/acme/web:1"'
assert_contains "a container app secret reference is a redacted parameter" "$tmrec" '"parameter":"DB_URL","env":"prod","tool":"terraform","container":"web","value":"","redacted":"yes"'
assert_contains "the module image differs between environments" "$tmrec" '"detail":"ghcr.io/acme/web:2 -> ghcr.io/acme/web:1"'
assert_equals "each module resource is drawn once per environment" "$(grep -c '"container":"web","env":"[a-z]*","tool":"terraform","node"' "$TEST_TMPDIR/tf-modules.json")" "2"

# Terraform: a remote module source, or a local one with no tracked files, refuses the record by name.
repoR="$TEST_TMPDIR/tf-remote"
tf_refusal() {
  local label="$1" reason="$2" file="$3" content="$4" rec
  rm -rf "$repoR"
  init_repo "$repoR"
  mkdir -p "$repoR/$(dirname "$file")"
  printf '%s\n' "$content" >"$repoR/$file"
  printf 'services:\n  api:\n    image: ghcr.io/acme/api:1\n' >"$repoR/compose.yaml"
  commit_all "$repoR"
  bash "$COLLECT" --repo "$repoR" --out "$TEST_TMPDIR/tf-remote.json" --generated-on 2026-09-28
  rec="$(cat "$TEST_TMPDIR/tf-remote.json")"
  assert_contains "$label refuses by name" "$rec" "\"reason\": \"$reason\""
  assert_not_contains "$label draws nothing from compose either" "$rec" "ghcr.io/acme/api"
  bash "$RENDER" --record "$TEST_TMPDIR/tf-remote.json" --out "$TEST_TMPDIR/tf-remote-out" --dialect likec4 >/dev/null
  assert_not_contains "$label renders no diagram" "$(cat "$TEST_TMPDIR/tf-remote-out/deployment.md")" '```'
  TF_REFUSAL_REC="$rec$(cat "$TEST_TMPDIR/tf-remote-out/deployment.md")"
}
tf_refusal "a remote git module" "terraform-module-unread:infra/main.tf:module.net" infra/main.tf \
  "$(printf 'module "net" {\n  source = "git::https://deploy:%s@github.com/acme/net.git"\n}' "$(gh_tok R)")"
assert_not_contains "a remote module source never reaches the record" "$TF_REFUSAL_REC" "$(gh_tok R)"
assert_not_contains "a remote module source host is not printed" "$TF_REFUSAL_REC" "github.com/acme/net"
tf_refusal "a registry module" "terraform-module-unread:main.tf:module.vpc" main.tf \
  "$(printf 'resource "aws_ecs_cluster" "main" {\n  name = "acme"\n}\nmodule "vpc" {\n  source = "terraform-aws-modules/vpc/aws"\n}')"
tf_refusal "a local module with no tracked files" "terraform-module-unread:main.tf:module.net" main.tf 'module "net" { source = "./net" }'
tf_refusal "an unbalanced block" "terraform-unreadable:main.tf" main.tf "$(printf 'resource "aws_ecs_cluster" "main" {\n  name = "acme"\n')"
tf_refusal "an unterminated heredoc" "terraform-unreadable:main.tf" main.tf "$(printf 'resource "aws_ecs_task_definition" "x" {\n  container_definitions = <<EOF\n[]\n}\n')"
tf_refusal "a tfvars file with no configuration" "terraform-orphan-tfvars:infra/prod.tfvars" infra/prod.tfvars 'region = "westeurope"'

# Terraform no-leak: a secret in a tfvars file that a container env references, a sensitive
# variable, and literal secrets in container_definitions.
repoTL="$TEST_TMPDIR/tf-leaks"
init_repo "$repoTL"
cat >"$repoTL/main.tf" <<EOF
variable "upstream" {}
variable "cs_sql" {}
variable "opaque" {
  sensitive = true
}
variable "on" {}
resource "aws_ecs_task_definition" "api" {
  family = "api"
  container_definitions = jsonencode([{
    name  = "api"
    image = "ghcr.io/acme/api:1"
    environment = [
      { name = "PREFIXED", value = "prefix-\${var.upstream}" },
      { name = "CHOSEN", value = var.on ? "$(gh_tok C)" : "" },
      { name = "UPSTREAM_A", value = var.upstream },
      { name = "CS_SQL", value = var.cs_sql },
      { name = "OPAQUE", value = var.opaque },
      { name = "UPSTREAM_B", value = "$(gh_pat L)" },
      { name = "CS_BUS", value = "Endpoint=sb://fakebus.servicebus.windows.net/;SharedAccessKey=${fake}-SAKL" },
      { name = "LOG_LEVEL", value = "info" }
    ]
    secrets = [{ name = "API_KEY", valueFrom = "arn:aws:ssm:eu-west-1:000000000000:parameter/api" }]
  }])
}
resource "aws_ecs_task_definition" "hidden" {
  family                = "hidden"
  container_definitions = jsonencode([{ name = "hidden", image = var.opaque }])
}
EOF
leak_needles+=("$(gh_pat L)" "$(gh_tok C)")
for s in S P; do
  [[ "$s" == S ]] && d=staging || d=prod
  {
    printf 'upstream = "%s"\n' "$(gh_tok "$s")"
    printf 'cs_sql   = "Server=db.example.com;User ID=app;Password=%s-TFSQL%s"\n' "$fake" "$s"
    printf 'opaque   = "%s-OPQ%s"\n' "$fake" "$s"
  } >"$repoTL/$d.tfvars"
done
commit_all "$repoTL"
bash "$COLLECT" --repo "$repoTL" --out "$TEST_TMPDIR/tf-leaks.json" --generated-on 2026-09-28
tlrec="$(cat "$TEST_TMPDIR/tf-leaks.json")"
assert_contains "terraform leak fixture is drawn" "$tlrec" '"status": "drawn"'
assert_contains "a sensitive variable in an image prints as redacted" "$tlrec" '"container":"hidden","env":"prod","tool":"terraform","node":"prod","compute":"","image":"[redacted]"'
for k in UPSTREAM_A CS_SQL OPAQUE UPSTREAM_B CS_BUS API_KEY PREFIXED CHOSEN; do
  assert_contains "terraform leak fixture redacts $k" "$tlrec" "\"parameter\":\"$k\",\"env\":\"prod\",\"tool\":\"terraform\",\"container\":\"api\",\"value\":\"\",\"redacted\":\"yes\""
done
assert_contains "a tfvars secret that differs is reported without its value" "$tlrec" "secret parameter UPSTREAM_A differs"
assert_contains "a sensitive variable that differs is reported without its value" "$tlrec" "secret parameter OPAQUE differs"
assert_no_leak "terraform record" "$tlrec"
tlsum="$(bash "$RENDER" --record "$TEST_TMPDIR/tf-leaks.json" --out "$TEST_TMPDIR/tf-leaks-out" --dialect c4-plantuml --diff staging prod)"
assert_no_leak "terraform render" "$(cat "$TEST_TMPDIR/tf-leaks-out/deployment.md")$tlsum"

# Bicep: .bicepparam environments over one template, a local module, and compute references.
repoB="$TEST_TMPDIR/bicep"
init_repo "$repoB"
mkdir -p "$repoB/infra/modules"
cat >"$repoB/infra/main.bicep" <<'EOF'
targetScope = 'resourceGroup'
param location string = resourceGroup().location
param apiImage string = 'ghcr.io/acme/api:1.0.0'
param minReplicas int = 1
@description('''The managed
environment name''')
param envName string

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  properties: {}
}

resource api 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'api'
  location: location
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      ingress: { external: true, targetPort: 8080 }
    }
    template: {
      containers: [
        {
          name: 'api'
          image: apiImage
          env: [
            { name: 'LOG_LEVEL', value: 'info' }
            { name: 'REGION', value: '${location}-${envName}' }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
      }
    }
  }
}

resource worker 'Microsoft.App/containerApps@2024-03-01' = if (minReplicas > 1) {
  name: 'worker'
  properties: {
    environmentId: env.id
    template: {
      containers: containerList
    }
  }
}

module web 'modules/web.bicep' = {
  name: 'web'
  params: {
    image: 'ghcr.io/acme/web:${minReplicas}'
  }
}

output fqdn string = api.properties.configuration.ingress.fqdn
EOF
cat >"$repoB/infra/modules/web.bicep" <<'EOF'
param image string
resource plan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'plan'
  sku: { name: 'B1' }
}
resource site 'Microsoft.Web/sites@2023-01-01' = {
  name: 'web'
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      linuxFxVersion: 'DOCKER|${image}'
      appSettings: [
        { name: 'WEBSITES_PORT', value: '80' }
      ]
    }
  }
}
resource code 'Microsoft.Web/sites@2023-01-01' = {
  name: 'code'
  properties: {
    siteConfig: { linuxFxVersion: 'NODE|20-lts' }
  }
}
EOF
printf "using 'main.bicep'\nparam envName = 'prod-env'\nparam apiImage = 'ghcr.io/acme/api:1.4.0'\nparam minReplicas = 3\n" >"$repoB/infra/main.prod.bicepparam"
printf "using './main.bicep'\nparam envName = 'stg-env'\n" >"$repoB/infra/main.staging.bicepparam"
commit_all "$repoB"
bash "$COLLECT" --repo "$repoB" --out "$TEST_TMPDIR/bicep.json" --generated-on 2026-09-28
assert_equals "bicep collect exits 0" "$?" "0"
brec="$(cat "$TEST_TMPDIR/bicep.json")"
assert_contains "bicep record is drawn" "$brec" '"status": "drawn"'
assert_contains "a bicepparam file is an environment" "$brec" '"environment":"prod","tool":"bicep","evidence":"infra/main.bicep, infra/main.prod.bicepparam"'
assert_contains "the other bicepparam file is an environment" "$brec" '"environment":"staging","tool":"bicep"'
assert_equals "bicep has two environments" "$(grep -c '"environment":"[a-z]*","tool":"bicep"' "$TEST_TMPDIR/bicep.json")" "2"
assert_contains "a managed environment is a compute node named by its parameter" "$brec" '"id":"prod/env","env":"prod","tool":"bicep","kind":"compute","name":"prod-env","detail":"Microsoft.App/managedEnvironments"'
assert_contains "a container app runs on the environment its id names" "$brec" '"container":"api","env":"prod","tool":"bicep","node":"prod/env","compute":"prod/env","image":"ghcr.io/acme/api:1.4.0","replicas":"3","ports":"8080"'
assert_contains "a parameter default applies when the bicepparam file omits it" "$brec" '"container":"api","env":"staging","tool":"bicep","node":"staging/env","compute":"staging/env","image":"ghcr.io/acme/api:1.0.0","replicas":"1"'
# shellcheck disable=SC2016 # ${...} is literal Bicep interpolation
assert_contains "an interpolation over a function default is unresolved" "$brec" '"parameter":"REGION","env":"prod","tool":"bicep","container":"api","value":"unresolved:'"'"'${location}-${envName}'"'"'"'
assert_contains "a containers expression places one unresolved container" "$brec" '"container":"worker","env":"prod","tool":"bicep","node":"prod/env","compute":"prod/env","image":"unresolved:containerList"'
assert_contains "a module server farm is a compute node" "$brec" '"id":"prod/module.web.plan","env":"prod","tool":"bicep","kind":"compute","name":"plan","detail":"Microsoft.Web/serverfarms","evidence":"infra/modules/web.bicep"'
assert_contains "a DOCKER site runs on its server farm with the module argument resolved" "$brec" '"container":"web","env":"prod","tool":"bicep","node":"prod/module.web.plan","compute":"prod/module.web.plan","image":"ghcr.io/acme/web:3"'
assert_contains "an app setting is a parameter" "$brec" '"parameter":"WEBSITES_PORT","env":"prod","tool":"bicep","container":"web","value":"80"'
assert_not_contains "a code site is not a container" "$brec" '"container":"code"'
assert_contains "bicep image diff" "$brec" '"change":"image","left":"prod","right":"staging","tool":"bicep","container":"api","detail":"ghcr.io/acme/api:1.4.0 -> ghcr.io/acme/api:1.0.0"'
assert_contains "bicep replicas diff" "$brec" '"change":"replicas","left":"prod","right":"staging","tool":"bicep","container":"api","detail":"3 -> 1"'
bash "$RENDER" --record "$TEST_TMPDIR/bicep.json" --out "$TEST_TMPDIR/bicep-l" --dialect likec4 --env prod >/dev/null
assert_contains "likec4 runs the bicep container inside its managed environment" "$(cat "$TEST_TMPDIR/bicep-l/deployment.md")" $'= node \'prod-env\' \'compute Microsoft.App/managedEnvironments\' {\n      instanceOf'

# ARM: <stem>.parameters.<env>.json and parameters.<env>.json beside the only template.
repoA="$TEST_TMPDIR/arm"
init_repo "$repoA"
mkdir -p "$repoA/infra"
cat >"$repoA/infra/app.json" <<EOF
{
  "\$schema": "$arm_schema",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "envName": { "type": "string" },
    "image": { "type": "string", "defaultValue": "ghcr.io/acme/api:1.0.0" },
    "replicas": { "type": "int", "defaultValue": 1 }
  },
  "variables": { "suffix": "x" },
  "resources": [
    {
      "type": "Microsoft.App/managedEnvironments",
      "apiVersion": "2024-03-01",
      "name": "[parameters('envName')]",
      "location": "[resourceGroup().location]",
      "properties": {}
    },
    {
      "type": "Microsoft.App/containerApps",
      "apiVersion": "2024-03-01",
      "name": "api",
      "properties": {
        "managedEnvironmentId": "[resourceId('Microsoft.App/managedEnvironments', parameters('envName'))]",
        "configuration": { "ingress": { "targetPort": 8080 } },
        "template": {
          "containers": [
            {
              "name": "api",
              "image": "[parameters('image')]",
              "env": [
                { "name": "REGION", "value": "[concat('eu-', variables('suffix'))]" },
                { "name": "LITERAL", "value": "[[bracketed]" }
              ]
            }
          ],
          "scale": { "minReplicas": "[parameters('replicas')]" }
        }
      }
    },
    {
      "type": "Microsoft.ContainerInstance/containerGroups",
      "apiVersion": "2023-05-01",
      "name": "jobs",
      "properties": {
        "containers": [
          {
            "name": "batch",
            "properties": {
              "image": "ghcr.io/acme/batch:1",
              "ports": [ { "port": 9000 } ],
              "environmentVariables": [ { "name": "MODE", "value": "nightly" } ]
            }
          }
        ]
      }
    }
  ]
}
EOF
# shellcheck disable=SC2016 # $schema is a literal JSON key
arm_params() { printf '{\n  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",\n  "parameters": {\n%s\n  }\n}\n' "$1"; }
arm_params '    "envName": { "value": "prod-env" },
    "image": { "value": "ghcr.io/acme/api:1.4.0" },
    "replicas": { "value": 3 }' >"$repoA/infra/app.parameters.prod.json"
arm_params '    "envName": { "value": "stg-env" }' >"$repoA/infra/parameters.staging.json"
mkdir -p "$repoA/sub"
# shellcheck disable=SC2016 # $schema is a literal JSON key
printf '{\n  "$schema": "https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentTemplate.json#",\n  "resources": []\n}\n' >"$repoA/sub/main.json"
commit_all "$repoA"
bash "$COLLECT" --repo "$repoA" --out "$TEST_TMPDIR/arm.json" --generated-on 2026-09-28
assert_equals "arm collect exits 0" "$?" "0"
arec="$(cat "$TEST_TMPDIR/arm.json")"
assert_contains "arm record is drawn" "$arec" '"status": "drawn"'
assert_contains "arm is a shipped tool" "$arec" '"name":"arm","shipped":"yes"'
assert_contains "a stem parameters file is an environment" "$arec" '"environment":"prod","tool":"arm","evidence":"infra/app.json, infra/app.parameters.prod.json"'
assert_contains "a bare parameters file pairs with the only template" "$arec" '"environment":"staging","tool":"arm","evidence":"infra/app.json, infra/parameters.staging.json"'
assert_contains "a subscription template is recognized and read" "$arec" '"environment":"sub","tool":"arm","evidence":"sub/main.json"'
assert_contains "an ARM managed environment is a compute node" "$arec" '"id":"prod/resources[0]","env":"prod","tool":"arm","kind":"compute","name":"prod-env"'
assert_contains "resourceId matches the environment by its resolved name" "$arec" '"container":"api","env":"prod","tool":"arm","node":"prod/resources[0]","compute":"prod/resources[0]","image":"ghcr.io/acme/api:1.4.0","replicas":"3","ports":"8080"'
assert_contains "an ARM default applies when the parameters file omits it" "$arec" '"container":"api","env":"staging","tool":"arm","node":"staging/resources[0]","compute":"staging/resources[0]","image":"ghcr.io/acme/api:1.0.0","replicas":"1"'
assert_contains "an ARM function is recorded unresolved" "$arec" '"parameter":"REGION","env":"prod","tool":"arm","container":"api","value":"unresolved:concat('"'"'eu-'"'"', variables('"'"'suffix'"'"'))"'
assert_contains "a doubled bracket is a literal" "$arec" '"parameter":"LITERAL","env":"prod","tool":"arm","container":"api","value":"[bracketed]"'
assert_contains "a container group is its own compute node" "$arec" '"id":"prod/resources[2]","env":"prod","tool":"arm","kind":"compute","name":"jobs","detail":"Microsoft.ContainerInstance/containerGroups"'
assert_contains "a container group container is placed with its port" "$arec" '"container":"batch","env":"prod","tool":"arm","node":"prod/resources[2]","compute":"prod/resources[2]","image":"ghcr.io/acme/batch:1","replicas":"undeclared","ports":"9000"'
assert_contains "arm image diff" "$arec" '"change":"image","left":"prod","right":"staging","tool":"arm","container":"api","detail":"ghcr.io/acme/api:1.4.0 -> ghcr.io/acme/api:1.0.0"'
bash "$RENDER" --record "$TEST_TMPDIR/arm.json" --out "$TEST_TMPDIR/arm-p" --dialect c4-plantuml --env prod >/dev/null
assert_contains "plantuml runs the ARM container inside its container group" "$(cat "$TEST_TMPDIR/arm-p/deployment.md")" $'"compute", "Microsoft.ContainerInstance/containerGroups") {\n    Container('
bash "$RENDER" --record "$TEST_TMPDIR/arm.json" --out "$TEST_TMPDIR/arm-l" --dialect likec4 --env prod >/dev/null
assert_contains "likec4 runs the ARM container inside its container group" "$(cat "$TEST_TMPDIR/arm-l/deployment.md")" $'= node \'jobs\' \'compute Microsoft.ContainerInstance/containerGroups\' {\n      instanceOf'

# Bicep and ARM refuse by name what they cannot read; a module source is never printed.
tf_refusal "a Bicep registry module" "bicep-module-unread:main.bicep:module.net" main.bicep \
  "$(printf "module net 'br:acme.azurecr.io/bicep/net:%s' = {\n  name: 'net'\n}" "$(gh_tok M)")"
assert_not_contains "a registry module source never reaches the record" "$TF_REFUSAL_REC" "$(gh_tok M)"
tf_refusal "a Bicep template-spec module" "bicep-module-unread:main.bicep:module.net" main.bicep \
  "$(printf "module net 'ts/Specs:net:1.0' = {\n  name: 'net'\n}")"
tf_refusal "a Bicep module with no tracked file" "bicep-module-unread:main.bicep:module.net" main.bicep \
  "$(printf "module net './net.bicep' = {\n  name: 'net'\n}")"
tf_refusal "an unbalanced Bicep block" "bicep-unreadable:main.bicep" main.bicep \
  "$(printf "resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {\n  name: 'x'\n")"
tf_refusal "an unbalanced ARM template" "arm-unreadable:infra/main.json" infra/main.json \
  "{\"\$schema\": \"$arm_schema\", \"resources\": ["
tf_refusal "a bicepparam file with using none" "bicep-param-unread:main.bicepparam" main.bicepparam "using none"
tf_refusal "a nested deployment" "arm-deployment-unread:infra/main.json:resources[0]" infra/main.json \
  "{\"\$schema\": \"$arm_schema\", \"resources\": [{\"type\": \"Microsoft.Resources/deployments\", \"name\": \"inner\", \"properties\": {}}]}"
rm -rf "$repoR"
init_repo "$repoR"
mkdir -p "$repoR/infra"
printf "param a string\n" >"$repoR/infra/one.bicep"
printf "param b string\n" >"$repoR/infra/two.bicep"
arm_params '    "a": { "value": "x" }' >"$repoR/infra/parameters.prod.json"
commit_all "$repoR"
bash "$COLLECT" --repo "$repoR" --out "$TEST_TMPDIR/unpaired.json" --generated-on 2026-09-28
assert_contains "a parameters file beside two templates is refused by name" "$(cat "$TEST_TMPDIR/unpaired.json")" '"reason": "arm-parameters-unpaired:infra/parameters.prod.json"'

# Bicep no-leak: a secure parameter default, a secure parameter passed through a module into an
# unmarked one, literal connection strings in env, a secret reference, and a bicepparam secret.
repoBL="$TEST_TMPDIR/bicep-leaks"
init_repo "$repoBL"
cat >"$repoBL/main.bicep" <<EOF
@secure()
param dbPassword string = '${fake}-BSEC'
@secure()
param token string
param upstream string
resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'api'
  properties: {
    template: {
      containers: [
        {
          name: 'api'
          image: 'ghcr.io/acme/api:1'
          env: [
            { name: 'OPAQUE', value: dbPassword }
            { name: 'PREFIXED', value: 'x-\${token}' }
            { name: 'UPSTREAM_A', value: upstream }
            { name: 'CS_SQL', value: 'Server=db.example.com;User ID=app;Password=${fake}-BSQL' }
            { name: 'CS_BUS', value: 'Endpoint=sb://fakebus.servicebus.windows.net/;SharedAccessKey=${fake}-BSAK' }
            { name: 'DB_URL', secretRef: 'db' }
            { name: 'LOG_LEVEL', value: 'info' }
          ]
        }
      ]
    }
  }
}
module hidden 'hidden.bicep' = {
  name: 'hidden'
  params: {
    image: token
  }
}
EOF
printf "param image string\nresource g 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {\n  name: 'g'\n  properties: {\n    containers: [\n      {\n        name: 'hidden'\n        properties: {\n          image: image\n        }\n      }\n    ]\n  }\n}\n" >"$repoBL/hidden.bicep"
for s in S P; do
  [[ "$s" == S ]] && d=staging || d=prod
  printf "using 'main.bicep'\nparam token = '%s-BTOK%s'\nparam upstream = '%s'\n" "$fake" "$s" "$(gh_tok "$s")" >"$repoBL/main.$d.bicepparam"
done
commit_all "$repoBL"
bash "$COLLECT" --repo "$repoBL" --out "$TEST_TMPDIR/bicep-leaks.json" --generated-on 2026-09-28
blrec="$(cat "$TEST_TMPDIR/bicep-leaks.json")"
assert_contains "bicep leak fixture is drawn" "$blrec" '"status": "drawn"'
for k in OPAQUE PREFIXED UPSTREAM_A CS_SQL CS_BUS DB_URL; do
  assert_contains "bicep leak fixture redacts $k" "$blrec" "\"parameter\":\"$k\",\"env\":\"prod\",\"tool\":\"bicep\",\"container\":\"api\",\"value\":\"\",\"redacted\":\"yes\""
done
assert_contains "a secure parameter passed through a module prints as redacted" "$blrec" '"container":"hidden","env":"prod","tool":"bicep","node":"prod/module.hidden.g","compute":"prod/module.hidden.g","image":"[redacted]"'
assert_contains "a bicepparam secret that differs is reported without its value" "$blrec" "secret parameter PREFIXED differs"
assert_no_leak "bicep record" "$blrec"
blsum="$(bash "$RENDER" --record "$TEST_TMPDIR/bicep-leaks.json" --out "$TEST_TMPDIR/bicep-leaks-out" --dialect c4-plantuml --diff staging prod)"
assert_no_leak "bicep render" "$(cat "$TEST_TMPDIR/bicep-leaks-out/deployment.md")$blsum"
bash "$RENDER" --record "$TEST_TMPDIR/bicep-leaks.json" --out "$TEST_TMPDIR/bicep-leaks-l" --dialect likec4 >/dev/null
assert_no_leak "bicep likec4 render" "$(cat "$TEST_TMPDIR/bicep-leaks-l/deployment.md")"

# ARM no-leak: a securestring default, a literal connection string, a container group secure
# value, and a Key Vault reference in a parameters file.
repoAL="$TEST_TMPDIR/arm-leaks"
init_repo "$repoAL"
cat >"$repoAL/app.json" <<EOF
{
  "\$schema": "$arm_schema",
  "parameters": {
    "dbPassword": { "type": "securestring", "defaultValue": "${fake}-ASEC" },
    "upstream": { "type": "string" },
    "vaulted": { "type": "string" }
  },
  "resources": [
    {
      "type": "Microsoft.ContainerInstance/containerGroups",
      "name": "g",
      "properties": {
        "containers": [
          {
            "name": "api",
            "properties": {
              "image": "ghcr.io/acme/api:1",
              "environmentVariables": [
                { "name": "OPAQUE", "value": "[parameters('dbPassword')]" },
                { "name": "UPSTREAM_A", "value": "[parameters('upstream')]" },
                { "name": "VAULTED", "value": "[parameters('vaulted')]" },
                { "name": "CS_SQL", "value": "Server=db.example.com;User ID=app;Password=${fake}-ASQL" },
                { "name": "SIGNING", "secureValue": "${fake}-ASV" },
                { "name": "LOG_LEVEL", "value": "info" }
              ]
            }
          }
        ]
      }
    }
  ]
}
EOF
for s in S P; do
  [[ "$s" == S ]] && d=staging || d=prod
  arm_params "    \"upstream\": { \"value\": \"$(gh_tok "$s")\" },
    \"vaulted\": { \"reference\": { \"keyVault\": { \"id\": \"/subscriptions/0/vaults/kv\" }, \"secretName\": \"db-$s\" } }" >"$repoAL/app.parameters.$d.json"
done
commit_all "$repoAL"
bash "$COLLECT" --repo "$repoAL" --out "$TEST_TMPDIR/arm-leaks.json" --generated-on 2026-09-28
alrec="$(cat "$TEST_TMPDIR/arm-leaks.json")"
assert_contains "arm leak fixture is drawn" "$alrec" '"status": "drawn"'
for k in OPAQUE UPSTREAM_A VAULTED CS_SQL SIGNING; do
  assert_contains "arm leak fixture redacts $k" "$alrec" "\"parameter\":\"$k\",\"env\":\"prod\",\"tool\":\"arm\",\"container\":\"api\",\"value\":\"\",\"redacted\":\"yes\""
done
assert_contains "arm leak fixture keeps a plain value" "$alrec" '"parameter":"LOG_LEVEL","env":"prod","tool":"arm","container":"api","value":"info","redacted":"no"'
assert_contains "an ARM parameters secret that differs is reported without its value" "$alrec" "secret parameter UPSTREAM_A differs"
assert_no_leak "arm record" "$alrec"
alsum="$(bash "$RENDER" --record "$TEST_TMPDIR/arm-leaks.json" --out "$TEST_TMPDIR/arm-leaks-out" --dialect c4-plantuml --diff staging prod)"
assert_no_leak "arm render" "$(cat "$TEST_TMPDIR/arm-leaks-out/deployment.md")$alsum"
bash "$RENDER" --record "$TEST_TMPDIR/arm-leaks.json" --out "$TEST_TMPDIR/arm-leaks-l" --dialect likec4 >/dev/null
assert_no_leak "arm likec4 render" "$(cat "$TEST_TMPDIR/arm-leaks-l/deployment.md")"

if [[ "$FAILED" -eq 0 ]]; then
  printf 'all collect-deployment tests passed\n'
  exit 0
fi
printf '%d collect-deployment test(s) failed\n' "$FAILED" >&2
exit 1
