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
assert_contains "terraform with no mapped container is refused" "$tf" '"reason": "no-mapped-container"'
assert_contains "terraform is a shipped tool" "$tf" '"name":"terraform","shipped":"yes"'
assert_contains "the resource type it could not map is listed" "$tf" '{"tool":"terraform","type":"azurerm_virtual_network","evidence":"net.tf"}'
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
cat >"$repo4/deploy/web.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: prod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: ghcr.io/acme/web:2
          env:
            - name: PASSWORD
              value: SuperSecret123
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: prod
spec:
  selector:
    app: web
  ports:
    - port: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: prod
spec:
  rules:
    - host: web.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-svc
                port:
                  number: 80
EOF
commit_all "$repo4"
bash "$COLLECT" --repo "$repo4" --out "$TEST_TMPDIR/k8s.json" --generated-on 2026-09-28
k8s="$(cat "$TEST_TMPDIR/k8s.json")"
assert_contains "k8s drawn" "$k8s" '"status": "drawn"'
assert_contains "k8s tool" "$k8s" '"name":"kubernetes"'
assert_contains "compose still read" "$k8s" '"name":"compose"'
assert_contains "ingress host" "$k8s" "web.example.com"
assert_not_contains "k8s secret dropped" "$k8s" "SuperSecret123"
bash "$RENDER" --record "$TEST_TMPDIR/k8s.json" --out "$TEST_TMPDIR/k8s-l" --dialect likec4 --env prod >/dev/null
kl="$(cat "$TEST_TMPDIR/k8s-l/deployment.md")"
assert_contains "likec4 ingress node" "$kl" "= node 'web' 'ingress web.example.com'"
assert_contains "likec4 view includes the environment" "$kl" ".**"
assert_likec4_golden "deployment-kubernetes.c4" "$TEST_TMPDIR/k8s-l/deployment.md"
assert_contains "likec4 runs the container inside its workload node" "$kl" $'compute Deployment\' {\n      instanceOf c2_web\n    }'
assert_contains "likec4 draws the Service selector as a relationship" "$kl" "-> env2_prod.cn4_web.c2_web 'selects app=web'"
assert_contains "likec4 draws the Ingress backend as a relationship" "$kl" "-> env2_prod.cn4_web.c2_web 'routes web.example.com'"
assert_contains "the placement names its compute node" "$k8s" '"compute":"prod/wl-web"'
assert_contains "the Service edge is in the record" "$k8s" '{"from":"prod/svc-web-svc","to":"web","to_compute":"prod/wl-web","env":"prod","tool":"kubernetes","label":"selects app=web"'
assert_contains "the Ingress edge is in the record" "$k8s" '{"from":"prod/ing-web","to":"web","to_compute":"prod/wl-web","env":"prod","tool":"kubernetes","label":"routes web.example.com"'
bash "$RENDER" --record "$TEST_TMPDIR/k8s.json" --out "$TEST_TMPDIR/k8s-p" --dialect c4-plantuml --env prod >/dev/null
kp="$(cat "$TEST_TMPDIR/k8s-p/deployment.md")"
assert_contains "plantuml runs the container inside its workload node" "$kp" $'"compute", "Deployment") {\n    Container(c2_web, "web", "ghcr.io/acme/web:2", "replicas 2")\n  }'
assert_contains "plantuml draws the Service selector as Rel" "$kp" 'Rel(n3_web_svc, c2_web, "selects app=web")'
assert_contains "plantuml draws the Ingress backend as Rel" "$kp" 'Rel(n2_web, c2_web, "routes web.example.com")'

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
check_declines "a Pulumi nodejs project" pulumi Pulumi.yaml $'name: web\nruntime: nodejs'
check_declines "a Kustomize overlay" kustomize deploy/kustomization.yaml "resources: []"
check_declines "a Helm chart" helm chart/Chart.yaml $'apiVersion: v2\nname: web\nversion: 0.1.0'
declining_fixture "$TEST_TMPDIR/notarm" package.json "$(printf '{"%sschema": "https://json.schemastore.org/package.json"}' '$')"
bash "$COLLECT" --repo "$TEST_TMPDIR/notarm" --out "$TEST_TMPDIR/notarm.json" --generated-on 2026-09-28
assert_contains "an unrelated json schema is not ARM" "$(cat "$TEST_TMPDIR/notarm.json")" '"reason": "no-declared-iac"'

declining_fixture "$TEST_TMPDIR/cfn-word" tool.sh "grep -q AWSTemplateFormatVersion \"\$1\""
bash "$COLLECT" --repo "$TEST_TMPDIR/cfn-word" --out "$TEST_TMPDIR/cfn-word.json" --generated-on 2026-09-28
assert_contains "a script that names the CloudFormation key is not a template" "$(cat "$TEST_TMPDIR/cfn-word.json")" '"reason": "no-declared-iac"'
declining_fixture "$TEST_TMPDIR/cfn" stack.yaml "AWSTemplateFormatVersion: '2010-09-09'"
bash "$COLLECT" --repo "$TEST_TMPDIR/cfn" --out "$TEST_TMPDIR/cfn.json" --generated-on 2026-09-28
assert_contains "a bare CloudFormation template is a shipped read" "$(cat "$TEST_TMPDIR/cfn.json")" '"name":"cloudformation","shipped":"yes"'
assert_contains "a bare CloudFormation template places nothing" "$(cat "$TEST_TMPDIR/cfn.json")" '"placements": []'

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
# variable, a secret-named variable with no sensitive marker feeding a plainly named env var, and
# literal secrets in container_definitions.
repoTL="$TEST_TMPDIR/tf-leaks"
init_repo "$repoTL"
cat >"$repoTL/main.tf" <<EOF
variable "upstream" {}
variable "api_token" {}
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
      { name = "FEED", value = var.api_token },
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
leak_needles+=("$(gh_pat L)" "$(gh_tok C)" "plainvalueXYZ")
for s in S P; do
  [[ "$s" == S ]] && d=staging || d=prod
  {
    printf 'upstream = "%s"\n' "$(gh_tok "$s")"
    printf 'api_token = "plainvalueXYZ%s"\n' "$s"
    printf 'cs_sql   = "%s"\n' "Server=db.example.com;User ID=app;Password=${fake}-TFSQL${s}"
    printf 'opaque   = "%s-OPQ%s"\n' "$fake" "$s"
  } >"$repoTL/$d.tfvars"
done
commit_all "$repoTL"
bash "$COLLECT" --repo "$repoTL" --out "$TEST_TMPDIR/tf-leaks.json" --generated-on 2026-09-28
tlrec="$(cat "$TEST_TMPDIR/tf-leaks.json")"
assert_contains "terraform leak fixture is drawn" "$tlrec" '"status": "drawn"'
assert_contains "a sensitive variable in an image prints as redacted" "$tlrec" '"container":"hidden","env":"prod","tool":"terraform","node":"prod","compute":"","image":"[redacted]"'
for k in UPSTREAM_A FEED CS_SQL OPAQUE UPSTREAM_B CS_BUS API_KEY PREFIXED CHOSEN; do
  assert_contains "terraform leak fixture redacts $k" "$tlrec" "\"parameter\":\"$k\",\"env\":\"prod\",\"tool\":\"terraform\",\"container\":\"api\",\"value\":\"\",\"redacted\":\"yes\""
done
assert_contains "a tfvars secret that differs is reported without its value" "$tlrec" "secret parameter UPSTREAM_A differs"
assert_contains "a sensitive variable that differs is reported without its value" "$tlrec" "secret parameter OPAQUE differs"
assert_contains "a secret-named unmarked variable that differs is reported without its value" "$tlrec" "secret parameter FEED differs"
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
assert_contains "a site with no container image is listed as unmapped" "$brec" '{"tool":"bicep","type":"Microsoft.Web/sites","evidence":"infra/modules/web.bicep"}'
assert_equals "only the site that reads no image is unmapped" "$(grep -c '{"tool":"bicep","type"' "$TEST_TMPDIR/bicep.json")" "1"
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
tf_refusal "a bicepparam file that extends another" "bicep-param-unread:main.bicepparam" main.bicepparam \
  "$(printf "using 'main.bicep'\nextends 'base.bicepparam'")"
tf_refusal "a bicepparam file whose template is not tracked" "bicep-param-unread:main.bicepparam" main.bicepparam "using './missing.bicep'"
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
param apiToken string
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
            { name: 'FEED', value: apiToken }
            { name: 'CHOSEN', value: upstream == 'x' ? '$(gh_tok C)' : '' }
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
  printf "using 'main.bicep'\nparam token = '%s-BTOK%s'\nparam upstream = '%s'\nparam apiToken = 'plainvalueXYZ%s'\n" "$fake" "$s" "$(gh_tok "$s")" "$s" >"$repoBL/main.$d.bicepparam"
done
commit_all "$repoBL"
bash "$COLLECT" --repo "$repoBL" --out "$TEST_TMPDIR/bicep-leaks.json" --generated-on 2026-09-28
blrec="$(cat "$TEST_TMPDIR/bicep-leaks.json")"
assert_contains "bicep leak fixture is drawn" "$blrec" '"status": "drawn"'
for k in OPAQUE PREFIXED UPSTREAM_A FEED CS_SQL CS_BUS DB_URL CHOSEN; do
  assert_contains "bicep leak fixture redacts $k" "$blrec" "\"parameter\":\"$k\",\"env\":\"prod\",\"tool\":\"bicep\",\"container\":\"api\",\"value\":\"\",\"redacted\":\"yes\""
done
assert_contains "a secure parameter passed through a module prints as redacted" "$blrec" '"container":"hidden","env":"prod","tool":"bicep","node":"prod/module.hidden.g","compute":"prod/module.hidden.g","image":"[redacted]"'
assert_contains "a bicepparam secret that differs is reported without its value" "$blrec" "secret parameter PREFIXED differs"
assert_contains "a secret-named unmarked bicep parameter that differs is reported without its value" "$blrec" "secret parameter FEED differs"
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
    "apiToken": { "type": "string" },
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
                { "name": "FEED", "value": "[parameters('apiToken')]" },
                { "name": "CHOSEN", "value": "[if(equals(parameters('upstream'), 'x'), '$(gh_tok C)', '')]" },
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
    \"apiToken\": { \"value\": \"plainvalueXYZ$s\" },
    \"vaulted\": { \"reference\": { \"keyVault\": { \"id\": \"/subscriptions/0/vaults/kv\" }, \"secretName\": \"db-$s\" } }" >"$repoAL/app.parameters.$d.json"
done
commit_all "$repoAL"
bash "$COLLECT" --repo "$repoAL" --out "$TEST_TMPDIR/arm-leaks.json" --generated-on 2026-09-28
alrec="$(cat "$TEST_TMPDIR/arm-leaks.json")"
assert_contains "arm leak fixture is drawn" "$alrec" '"status": "drawn"'
for k in OPAQUE UPSTREAM_A FEED VAULTED CS_SQL SIGNING CHOSEN; do
  assert_contains "arm leak fixture redacts $k" "$alrec" "\"parameter\":\"$k\",\"env\":\"prod\",\"tool\":\"arm\",\"container\":\"api\",\"value\":\"\",\"redacted\":\"yes\""
done
assert_contains "arm leak fixture keeps a plain value" "$alrec" '"parameter":"LOG_LEVEL","env":"prod","tool":"arm","container":"api","value":"info","redacted":"no"'
assert_contains "an ARM parameters secret that differs is reported without its value" "$alrec" "secret parameter UPSTREAM_A differs"
assert_contains "a secret-named unmarked ARM parameter that differs is reported without its value" "$alrec" "secret parameter FEED differs"
assert_no_leak "arm record" "$alrec"
alsum="$(bash "$RENDER" --record "$TEST_TMPDIR/arm-leaks.json" --out "$TEST_TMPDIR/arm-leaks-out" --dialect c4-plantuml --diff staging prod)"
assert_no_leak "arm render" "$(cat "$TEST_TMPDIR/arm-leaks-out/deployment.md")$alsum"
bash "$RENDER" --record "$TEST_TMPDIR/arm-leaks.json" --out "$TEST_TMPDIR/arm-leaks-l" --dialect likec4 >/dev/null
assert_no_leak "arm likec4 render" "$(cat "$TEST_TMPDIR/arm-leaks-l/deployment.md")"

# CloudFormation: one template, one environment per parameter file (both file shapes), short tags,
# a block Sub, and every intrinsic the reader does not evaluate recorded as unresolved.
repoC="$TEST_TMPDIR/cfn-env"
init_repo "$repoC"
mkdir -p "$repoC/infra"
cat >"$repoC/infra/service.yaml" <<'EOF'
AWSTemplateFormatVersion: "2010-09-09"
Description: Service line one
  and line two # trailing comment
Metadata:
  Note: "quoted line
    continues"
Parameters:
  EnvName:
    Type: String
  Tag:
    Type: String
    Default: latest
  Count:
    Type: Number
    Default: 1
Conditions:
  IsProd: !Equals [!Ref EnvName, prod]
Resources:
  Cluster:
    Type: AWS::ECS::Cluster
    Properties:
      ClusterName: !Sub "app-${EnvName}"
  TaskDef:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: !Join
        - "-"
        - - api
          - !Ref EnvName
      ContainerDefinitions:
        - Name: api
          Image: !Sub "ghcr.io/acme/api:${Tag}"
          PortMappings:
            - ContainerPort: 8080
          Environment:
            - Name: LOG_LEVEL
              Value: info
            - Name: GREETING
              Value: !Sub |
                hello ${EnvName}
            - Name: REGION
              Value: !Ref AWS::Region
            - Name: CLUSTER_ARN
              Value: !GetAtt Cluster.Arn
            - {Name: MODE, Value: !If [IsProd, strict, lax]}
            - Name: SAME_INDENT
              Value: !Join
              - ""
              - [a, b]
        - Name: sidecar
          Image: ghcr.io/acme/proxy:1
  Service:
    Type: AWS::ECS::Service
    Properties:
      ServiceName: api
      Cluster: !Ref Cluster
      TaskDefinition: !Ref TaskDef
      DesiredCount: !Ref Count
EOF
printf '[{"ParameterKey":"EnvName","ParameterValue":"staging"},{"ParameterKey":"Tag","ParameterValue":"1.0.0"}]\n' >"$repoC/infra/service.staging.json"
printf '[\n  {"ParameterKey": "EnvName", "ParameterValue": "prod"},\n  {"ParameterKey": "Tag", "ParameterValue": "1.4.0"},\n  {"ParameterKey": "Count", "ParameterValue": "3"}\n]\n' >"$repoC/infra/service.prod.json"
printf '{\n  "Parameters": {\n    "EnvName": "qa",\n    "Tag": "0.9.0"\n  }\n}\n' >"$repoC/infra/service.parameters.qa.json"
commit_all "$repoC"
bash "$COLLECT" --repo "$repoC" --out "$TEST_TMPDIR/cfn-env.json" --generated-on 2026-09-28
crec="$(cat "$TEST_TMPDIR/cfn-env.json")"
assert_contains "cloudformation is drawn" "$crec" '"status": "drawn"'
assert_contains "cloudformation is a shipped tool" "$crec" '"name":"cloudformation","shipped":"yes","evidence":"infra/service.yaml"'
for e in staging prod qa; do
  assert_contains "cloudformation environment $e" "$crec" "\"environment\":\"$e\",\"tool\":\"cloudformation\""
done
assert_contains "an environment cites its template and parameter file" "$crec" '"evidence":"infra/service.yaml, infra/service.prod.json"'
assert_contains "a parameters-object file names its environment" "$crec" '"evidence":"infra/service.yaml, infra/service.parameters.qa.json"'
assert_contains "the cluster is a compute node named through Sub" "$crec" '"id":"prod/Cluster","env":"prod","tool":"cloudformation","kind":"compute","name":"app-prod","detail":"AWS::ECS::Cluster"'
assert_contains "a container resolves a parameter file value and DesiredCount" "$crec" '"container":"api","env":"prod","tool":"cloudformation","node":"prod/Cluster","compute":"prod/Cluster","image":"ghcr.io/acme/api:1.4.0","replicas":"3","ports":"8080"'
assert_contains "a container falls back to the parameter Default" "$crec" '"container":"api","env":"staging","tool":"cloudformation","node":"staging/Cluster","compute":"staging/Cluster","image":"ghcr.io/acme/api:1.0.0","replicas":"1","ports":"8080"'
assert_contains "a sidecar container is its own placement on the same cluster" "$crec" '"container":"sidecar","env":"prod","tool":"cloudformation","node":"prod/Cluster","compute":"prod/Cluster","image":"ghcr.io/acme/proxy:1"'
assert_contains "a block Sub resolves a parameter" "$crec" '"parameter":"GREETING","env":"prod","tool":"cloudformation","container":"api","value":"hello prod"'
assert_contains "a plain env value is kept" "$crec" '"parameter":"LOG_LEVEL","env":"prod","tool":"cloudformation","container":"api","value":"info","redacted":"no"'
assert_contains "a pseudo parameter is unresolved" "$crec" 'unresolved:{Ref:\"AWS::Region\"}'
assert_contains "GetAtt is unresolved" "$crec" 'unresolved:{Fn::GetAtt:\"Cluster.Arn\"}'
assert_contains "a flow-map env entry with If is unresolved" "$crec" '"parameter":"MODE","env":"prod","tool":"cloudformation","container":"api","value":"unresolved:{Fn::If:['
assert_contains "a short tag over a sequence at the key's own indent is read" "$crec" '"parameter":"SAME_INDENT","env":"prod","tool":"cloudformation","container":"api","value":"unresolved:{Fn::Join:[\"\",[\"a\",\"b\"]]}"'
assert_contains "the cloudformation diff reports the image" "$crec" '"change":"image","left":"prod","right":"staging","tool":"cloudformation","container":"api","detail":"ghcr.io/acme/api:1.4.0 -> ghcr.io/acme/api:1.0.0"'
assert_contains "the cloudformation diff reports replicas" "$crec" '"change":"replicas","left":"prod","right":"staging","tool":"cloudformation","container":"api","detail":"3 -> 1"'
csum="$(bash "$RENDER" --record "$TEST_TMPDIR/cfn-env.json" --out "$TEST_TMPDIR/cfn-env-out" --dialect c4-plantuml --diff prod staging)"
assert_contains "cloudformation renders one node per environment" "$(cat "$TEST_TMPDIR/cfn-env-out/deployment.md")" 'Deployment_Node'
assert_contains "cloudformation summary" "$csum" 'status=drawn reason=none tools=cloudformation environments=3'
bash "$RENDER" --record "$TEST_TMPDIR/cfn-env.json" --out "$TEST_TMPDIR/cfn-env-l" --dialect likec4 >/dev/null
assert_equals "cloudformation renders under likec4" "$?" "0"

# A JSON template, one parameter file per environment in another directory, and detection by
# Resources with AWS:: types when there is no format version.
repoCJ="$TEST_TMPDIR/cfn-json"
init_repo "$repoCJ"
mkdir -p "$repoCJ/params"
cat >"$repoCJ/stack.json" <<'EOF'
{
  "Parameters": { "Tag": { "Type": "String", "Default": "latest" } },
  "Resources": {
    "Cluster": { "Type": "AWS::ECS::Cluster", "Properties": { "ClusterName": "main" } },
    "TaskDef": {
      "Type": "AWS::ECS::TaskDefinition",
      "Properties": {
        "ContainerDefinitions": [
          { "Name": "web", "Image": { "Fn::Sub": "ghcr.io/acme/web:${Tag}" }, "PortMappings": [{ "ContainerPort": 80 }] }
        ]
      }
    },
    "Service": {
      "Type": "AWS::ECS::Service",
      "Properties": { "Cluster": { "Ref": "Cluster" }, "TaskDefinition": { "Ref": "TaskDef" }, "DesiredCount": 2 }
    }
  }
}
EOF
printf '[{"ParameterKey":"Tag","ParameterValue":"3.1"}]\n' >"$repoCJ/params/prod.json"
printf '[{"ParameterKey":"Tag","ParameterValue":"3.0"}]\n' >"$repoCJ/params/dev.json"
commit_all "$repoCJ"
bash "$COLLECT" --repo "$repoCJ" --out "$TEST_TMPDIR/cfn-json.json" --generated-on 2026-09-28
cjrec="$(cat "$TEST_TMPDIR/cfn-json.json")"
assert_contains "a JSON template without a format version is detected by its AWS types" "$cjrec" '"name":"cloudformation","shipped":"yes","evidence":"stack.json"'
assert_contains "a JSON template resolves Fn::Sub from a parameter file" "$cjrec" '"container":"web","env":"prod","tool":"cloudformation","node":"prod/Cluster","compute":"prod/Cluster","image":"ghcr.io/acme/web:3.1","replicas":"2","ports":"80"'
assert_contains "the environment is the parameter file name" "$cjrec" '"environment":"dev","tool":"cloudformation","evidence":"stack.json, params/dev.json"'
assert_contains "the JSON diff reports the image" "$cjrec" '"detail":"ghcr.io/acme/web:3.0 -> ghcr.io/acme/web:3.1"'
declining_fixture "$TEST_TMPDIR/cfn-detect" only.yaml $'Resources:\n  Job:\n    Type: Custom::Thing'
bash "$COLLECT" --repo "$TEST_TMPDIR/cfn-detect" --out "$TEST_TMPDIR/cfn-detect.json" --generated-on 2026-09-28
assert_contains "Resources without an AWS:: type is not a template" "$(cat "$TEST_TMPDIR/cfn-detect.json")" '"reason": "no-declared-iac"'
declining_fixture "$TEST_TMPDIR/cfn-lower" only.yaml $'resources:\n  job:\n    type: AWS::ECS::Cluster'
bash "$COLLECT" --repo "$TEST_TMPDIR/cfn-lower" --out "$TEST_TMPDIR/cfn-lower.json" --generated-on 2026-09-28
assert_contains "a lowercase resources key is not CloudFormation" "$(cat "$TEST_TMPDIR/cfn-lower.json")" '"reason": "no-declared-iac"'
declining_fixture "$TEST_TMPDIR/cfn-stray" params.json '[{"ParameterKey":"A","ParameterValue":"b"}]'
bash "$COLLECT" --repo "$TEST_TMPDIR/cfn-stray" --out "$TEST_TMPDIR/cfn-stray.json" --generated-on 2026-09-28
assert_contains "a parameter file with no template is not IaC" "$(cat "$TEST_TMPDIR/cfn-stray.json")" '"reason": "no-declared-iac"'

# CloudFormation no-leak: NoEcho parameters (a Default, a param-file value, through Sub, in an
# image), dynamic references, container Secrets, and literal credentials in Environment values.
cfn_needles=("$(gh_tok Q)" "$(gh_tok R)" "$(gh_tok C)" "${fake}-CFN" "resolve:" "secretsmanager:prod" "plainvalueXYZ")
repoCL="$TEST_TMPDIR/cfn-leaks"
init_repo "$repoCL"
cat >"$repoCL/app.yaml" <<EOF
AWSTemplateFormatVersion: "2010-09-09"
Parameters:
  Opaque:
    Type: String
    NoEcho: true
    Default: ${fake}-CFNDEFAULT
  Upstream:
    Type: String
  ApiToken:
    Type: String
Resources:
  TaskDef:
    Type: AWS::ECS::TaskDefinition
    Properties:
      ContainerDefinitions:
        - Name: api
          Image: ghcr.io/acme/api:1
          Environment:
            - {Name: OPAQUE, Value: !Ref Opaque}
            - Name: PREFIXED
              Value: !Sub "prefix-\${Opaque}"
            - Name: LITERAL_GH
              Value: $(gh_tok C)
            - Name: FROM_PARAM
              Value: !Ref Upstream
            - Name: FEED
              Value: !Ref ApiToken
            - Name: DYN_SM
              Value: "{{resolve:secretsmanager:prod/db:SecretString:password}}"
            - Name: DYN_SSM
              Value: !Sub "{{resolve:ssm-secure:/prod/api/key:1}}"
            - Name: NESTED_DYN
              Value: !Join ["", ["{{resolve:secretsmanager:prod/x}}", "-y"]]
            - Name: CS_SQL
              Value: "Server=db.example.com;User ID=app;Password=${fake}-CFNSQL"
            - Name: LOG_LEVEL
              Value: info
          Secrets:
            - Name: API_KEY
              ValueFrom: arn:aws:ssm:eu-west-1:000000000000:parameter/api
  Hidden:
    Type: AWS::ECS::TaskDefinition
    Properties:
      ContainerDefinitions:
        - Name: hidden
          Image: !Ref Opaque
EOF
for s in Q R; do
  [[ "$s" == Q ]] && d=staging || d=prod
  printf '[{"ParameterKey":"Opaque","ParameterValue":"%s-CFNOPQ%s"},{"ParameterKey":"Upstream","ParameterValue":"%s"},{"ParameterKey":"ApiToken","ParameterValue":"plainvalueXYZ%s"}]\n' "$fake" "$s" "$(gh_tok "$s")" "$s" >"$repoCL/app.$d.json"
done
commit_all "$repoCL"
bash "$COLLECT" --repo "$repoCL" --out "$TEST_TMPDIR/cfn-leaks.json" --generated-on 2026-09-28
clrec="$(cat "$TEST_TMPDIR/cfn-leaks.json")"
assert_contains "cloudformation leak fixture is drawn" "$clrec" '"status": "drawn"'
for k in OPAQUE PREFIXED LITERAL_GH FROM_PARAM FEED DYN_SM DYN_SSM NESTED_DYN CS_SQL API_KEY; do
  assert_contains "cloudformation leak fixture redacts $k" "$clrec" "\"parameter\":\"$k\",\"env\":\"prod\",\"tool\":\"cloudformation\",\"container\":\"api\",\"value\":\"\",\"redacted\":\"yes\""
done
assert_contains "cloudformation leak fixture keeps a plain value" "$clrec" '"parameter":"LOG_LEVEL","env":"prod","tool":"cloudformation","container":"api","value":"info","redacted":"no"'
assert_contains "a NoEcho parameter in an image prints as redacted" "$clrec" '"container":"hidden","env":"prod","tool":"cloudformation","node":"prod","compute":"","image":"[redacted]"'
assert_contains "a NoEcho parameter that differs is reported without its value" "$clrec" "secret parameter OPAQUE differs"
assert_contains "a secret-shaped parameter file value that differs is reported without its value" "$clrec" "secret parameter FROM_PARAM differs"
assert_contains "a secret-named parameter with no NoEcho that differs is reported without its value" "$clrec" "secret parameter FEED differs"
cl_all="$clrec"
clsum="$(bash "$RENDER" --record "$TEST_TMPDIR/cfn-leaks.json" --out "$TEST_TMPDIR/cfn-leaks-out" --dialect c4-plantuml --diff prod staging)"
cl_all="$cl_all$(cat "$TEST_TMPDIR/cfn-leaks-out/deployment.md")$clsum"
bash "$RENDER" --record "$TEST_TMPDIR/cfn-leaks.json" --out "$TEST_TMPDIR/cfn-leaks-l" --dialect likec4 >/dev/null
cl_all="$cl_all$(cat "$TEST_TMPDIR/cfn-leaks-l/deployment.md")"
for needle in "${cfn_needles[@]}"; do
  assert_not_contains "cloudformation record, renders and summary hold no ${needle:0:12}" "$cl_all" "$needle"
done

# CloudFormation refuses what it cannot read as text, by file name.
cfn_refusal() {
  local label="$1" reason="$2" dir="$TEST_TMPDIR/cfn-refuse"
  shift 2
  rm -rf "$dir"
  init_repo "$dir"
  while [[ $# -ge 2 ]]; do
    mkdir -p "$dir/$(dirname "$1")"
    printf '%s\n' "$2" >"$dir/$1"
    shift 2
  done
  commit_all "$dir"
  bash "$COLLECT" --repo "$dir" --out "$TEST_TMPDIR/cfn-refuse.json" --generated-on 2026-09-28
  cfn_refused="$(cat "$TEST_TMPDIR/cfn-refuse.json")"
  assert_contains "$label refuses" "$cfn_refused" "\"reason\": \"$reason\""
  assert_contains "$label draws nothing" "$cfn_refused" '"placements": []'
}
cfn_ecs=$'Resources:\n  Cluster:\n    Type: AWS::ECS::Cluster'
cfn_refusal "a SAM Transform" "cloudformation-transform-unread:sam.yaml" sam.yaml $'Transform: AWS::Serverless-2016-10-31\nResources:\n  Fn:\n    Type: AWS::Serverless::Function'
cfn_refusal "a nested stack" "cloudformation-stack-unread:root.yaml:Child" root.yaml $'Resources:\n  Cluster:\n    Type: AWS::ECS::Cluster\n  Child:\n    Type: AWS::CloudFormation::Stack\n    Properties:\n      TemplateURL: https://s3.example.com/hidden-bucket/child.yaml'
assert_not_contains "a nested stack template location is never printed" "$cfn_refused" "hidden-bucket"
cfn_refusal "a parameter file beside two templates" "cloudformation-parameters-unpaired:params.prod.json" a.yaml "$cfn_ecs" b.yaml "$cfn_ecs" params.prod.json '[{"ParameterKey":"A","ParameterValue":"b"}]'
cfn_refusal "a YAML anchor" "cloudformation-unreadable:anchor.yaml" anchor.yaml $'Resources:\n  Cluster: &c\n    Type: AWS::ECS::Cluster'
cfn_refusal "a merge key" "cloudformation-unreadable:merge.yaml" merge.yaml $'Resources:\n  Cluster:\n    <<: *c\n    Type: AWS::ECS::Cluster'
cfn_refusal "a tab in the indentation" "cloudformation-unreadable:tab.yaml" tab.yaml $'Resources:\n\tCluster:\n\t\tType: AWS::ECS::Cluster'
cfn_refusal "a duplicate key" "cloudformation-unreadable:dup.yaml" dup.yaml $'Resources:\n  Cluster:\n    Type: AWS::ECS::Cluster\n    Type: AWS::ECS::Service'
cfn_refusal "a second document" "cloudformation-unreadable:docs.yaml" docs.yaml $'Resources:\n  Cluster:\n    Type: AWS::ECS::Cluster\n---\nResources: {}'
cfn_refusal "an unclosed flow collection" "cloudformation-unreadable:flow.yaml" flow.yaml $'Resources:\n  Cluster:\n    Type: AWS::ECS::Cluster\n    Properties: {ClusterName: a'
cfn_refusal "an unterminated quoted scalar" "cloudformation-unreadable:quote.yaml" quote.yaml $'Resources:\n  Cluster:\n    Type: AWS::ECS::Cluster\n    Properties:\n      ClusterName: "a'
cfn_refusal "a truncated JSON template" "cloudformation-unreadable:cut.json" cut.json $'{\n  "AWSTemplateFormatVersion": "2010-09-09",\n  "Resources": {'

# CloudFormation beside Compose is read, and beside an unshipped tool is a partial read.
repoCB="$TEST_TMPDIR/cfn-both"
init_repo "$repoCB"
printf 'services:\n  api:\n    image: ghcr.io/acme/api:1\n' >"$repoCB/compose.yaml"
printf '%s\n' "$cfn_ecs" >"$repoCB/stack.yaml"
commit_all "$repoCB"
bash "$COLLECT" --repo "$repoCB" --out "$TEST_TMPDIR/cfn-both.json" --generated-on 2026-09-28
assert_contains "cloudformation beside compose is drawn" "$(cat "$TEST_TMPDIR/cfn-both.json")" '"status": "drawn"'
mkdir -p "$repoCB/overlay"
printf 'resources: []\n' >"$repoCB/overlay/kustomization.yaml"
commit_all "$repoCB"
bash "$COLLECT" --repo "$repoCB" --out "$TEST_TMPDIR/cfn-both.json" --generated-on 2026-09-28
assert_contains "cloudformation beside kustomize is a partial read" "$(cat "$TEST_TMPDIR/cfn-both.json")" '"reason": "partial-read"'

# Pulumi YAML: one environment per Pulumi.<stack>.yaml, ${pulumi.stack}, config from the stack file
# then the project default, a secure: value, and fn::secret.
repoP="$TEST_TMPDIR/pulumi-env"
init_repo "$repoP"
mkdir -p "$repoP/infra"
cat >"$repoP/infra/Pulumi.yaml" <<'EOF'
name: web
runtime: yaml
config:
  imageTag:
    type: string
    default: latest
  replicas:
    type: integer
    default: 1
  dbPassword:
    type: string
    secret: true
resources:
  cluster:
    type: aws:ecs:Cluster
    properties:
      name: web-${pulumi.stack}
  taskdef:
    type: aws:ecs/taskDefinition:TaskDefinition
    properties:
      family: api
      containerDefinitions:
        fn::toJSON:
          - name: api
            image: ghcr.io/acme/api:${imageTag}
            portMappings:
              - containerPort: 8080
            environment:
              - name: LOG_LEVEL
                value: info
              - name: DB_URL
                value: postgres://u:${dbPassword}@h/db
              - name: JOINED
                value:
                  fn::join:
                    - "-"
                    - [a, b]
            secrets:
              - name: API_KEY
                valueFrom: arn:aws:ssm:eu-west-1:000000000000:parameter/api
  svc:
    type: aws:ecs:Service
    properties:
      cluster: ${cluster.arn}
      taskDefinition: ${taskdef.arn}
      desiredCount: ${replicas}
EOF
printf 'encryptionsalt: v1:abc:def\nconfig:\n  web:imageTag: 2.0.0\n  web:replicas: 3\n  web:dbPassword:\n    secure: v1:%s-PUL:cipher\n  aws:region: us-east-1\n' "$fake" >"$repoP/infra/Pulumi.prod.yaml"
printf 'config:\n  replicas: 1\n' >"$repoP/infra/Pulumi.dev.yaml"
commit_all "$repoP"
bash "$COLLECT" --repo "$repoP" --out "$TEST_TMPDIR/pulumi-env.json" --generated-on 2026-09-28
prec="$(cat "$TEST_TMPDIR/pulumi-env.json")"
assert_contains "pulumi yaml is drawn" "$prec" '"status": "drawn"'
assert_contains "pulumi yaml is a shipped tool" "$prec" '"name":"pulumi-yaml","shipped":"yes","evidence":"infra/Pulumi.yaml"'
assert_not_contains "stack files are not tools of their own" "$prec" 'Pulumi.prod.yaml","shipped"'
assert_contains "a stack is an environment" "$prec" '"environment":"prod","tool":"pulumi-yaml","evidence":"infra/Pulumi.yaml, infra/Pulumi.prod.yaml"'
assert_contains "the other stack is an environment" "$prec" '"environment":"dev","tool":"pulumi-yaml","evidence":"infra/Pulumi.yaml, infra/Pulumi.dev.yaml"'
assert_contains "pulumi.stack resolves in a node name" "$prec" '"id":"prod/cluster","env":"prod","tool":"pulumi-yaml","kind":"compute","name":"web-prod","detail":"aws:ecs:Cluster"'
assert_contains "a stack config value beats the project default" "$prec" '"container":"api","env":"prod","tool":"pulumi-yaml","node":"prod/cluster","compute":"prod/cluster","image":"ghcr.io/acme/api:2.0.0","replicas":"3","ports":"8080"'
assert_contains "a missing stack value falls back to the project default" "$prec" '"container":"api","env":"dev","tool":"pulumi-yaml","node":"dev/cluster","compute":"dev/cluster","image":"ghcr.io/acme/api:latest","replicas":"1","ports":"8080"'
assert_contains "a bare stack config key resolves" "$prec" '"replicas":"1"'
assert_contains "fn::join is unresolved, never evaluated" "$prec" '"parameter":"JOINED","env":"prod","tool":"pulumi-yaml","container":"api","value":"unresolved:{fn::join:['
assert_contains "a secret config value is a redacted parameter" "$prec" '"parameter":"DB_URL","env":"prod","tool":"pulumi-yaml","container":"api","value":"","redacted":"yes"'
assert_contains "a container secret is a redacted parameter" "$prec" '"parameter":"API_KEY","env":"dev","tool":"pulumi-yaml","container":"api","value":"","redacted":"yes"'
assert_contains "the pulumi diff reports the image" "$prec" '"change":"image","left":"dev","right":"prod","tool":"pulumi-yaml","container":"api","detail":"ghcr.io/acme/api:latest -> ghcr.io/acme/api:2.0.0"'
assert_contains "the pulumi diff reports replicas" "$prec" '"change":"replicas","left":"dev","right":"prod","tool":"pulumi-yaml","container":"api","detail":"1 -> 3"'
assert_contains "the pulumi diff reports a secret that differs" "$prec" "secret parameter DB_URL differs"
assert_not_contains "a secure: ciphertext is never printed" "$prec" "PUL"
psum="$(bash "$RENDER" --record "$TEST_TMPDIR/pulumi-env.json" --out "$TEST_TMPDIR/pulumi-env-out" --dialect c4-plantuml --diff dev prod)"
assert_contains "pulumi renders one node per environment" "$(cat "$TEST_TMPDIR/pulumi-env-out/deployment.md")" 'Deployment_Node'
assert_contains "pulumi summary" "$psum" 'status=drawn reason=none tools=pulumi-yaml environments=2'

# Pulumi no-leak: a secret: true default, a secure: value that differs by stack, fn::secret,
# a secret-shaped stack value, and literal credentials.
pul_needles=("$(gh_tok U)" "$(gh_tok V)" "$(gh_tok C)" "${fake}-PUL" "plainvalueXYZ")
repoPL="$TEST_TMPDIR/pulumi-leaks"
init_repo "$repoPL"
cat >"$repoPL/Pulumi.yaml" <<EOF
name: web
runtime: yaml
config:
  apiToken:
    type: string
    secret: true
    default: ${fake}-PULDEFAULT
  dbPassword:
    type: string
    secret: true
  upstream:
    type: string
  feedToken:
    type: string
resources:
  taskdef:
    type: aws:ecs:TaskDefinition
    properties:
      containerDefinitions:
        fn::toJSON:
          - name: api
            image: ghcr.io/acme/api:1
            environment:
              - name: TOKEN
                value: \${apiToken}
              - name: PREFIXED
                value: prefix-\${dbPassword}
              - name: WRAPPED
                value:
                  fn::secret: ${fake}-PULWRAP
              - name: LITERAL_GH
                value: $(gh_tok C)
              - name: FROM_STACK
                value: \${upstream}
              - name: FEED
                value: \${feedToken}
              - name: NESTED
                value:
                  fn::join:
                    - "-"
                    - - fn::secret: ${fake}-PULNEST
              - name: STRUCT
                value: \${db}
              - name: CS_SQL
                value: "Server=db.example.com;User ID=app;Password=${fake}-PULSQL"
              - name: LOG_LEVEL
                value: info
  hidden:
    type: aws:ecs:TaskDefinition
    properties:
      containerDefinitions:
        fn::toJSON:
          - name: hidden
            image: \${dbPassword}
EOF
for s in U V; do
  [[ "$s" == U ]] && d=staging || d=prod
  printf 'config:\n  web:dbPassword:\n    secure: v1:%s-PUL%s:cipher\n  web:upstream: %s\n  web:feedToken: plainvalueXYZ%s\n  web:db:\n    user: app\n    token:\n      secure: v1:%s-PULDB%s:cipher\n' "$fake" "$s" "$(gh_tok "$s")" "$s" "$fake" "$s" >"$repoPL/Pulumi.$d.yaml"
done
commit_all "$repoPL"
bash "$COLLECT" --repo "$repoPL" --out "$TEST_TMPDIR/pulumi-leaks.json" --generated-on 2026-09-28
plrec="$(cat "$TEST_TMPDIR/pulumi-leaks.json")"
assert_contains "pulumi leak fixture is drawn" "$plrec" '"status": "drawn"'
for k in TOKEN PREFIXED WRAPPED LITERAL_GH FROM_STACK FEED NESTED STRUCT CS_SQL; do
  assert_contains "pulumi leak fixture redacts $k" "$plrec" "\"parameter\":\"$k\",\"env\":\"prod\",\"tool\":\"pulumi-yaml\",\"container\":\"api\",\"value\":\"\",\"redacted\":\"yes\""
done
assert_contains "pulumi leak fixture keeps a plain value" "$plrec" '"parameter":"LOG_LEVEL","env":"prod","tool":"pulumi-yaml","container":"api","value":"info","redacted":"no"'
assert_contains "a secret config key in an image prints as redacted" "$plrec" '"container":"hidden","env":"prod","tool":"pulumi-yaml","node":"prod","compute":"","image":"[redacted]"'
assert_contains "a secure stack value that differs is reported without its value" "$plrec" "secret parameter PREFIXED differs"
assert_contains "a secret-shaped stack value that differs is reported without its value" "$plrec" "secret parameter FROM_STACK differs"
assert_contains "a secret-named config key with no secret marker that differs is reported without its value" "$plrec" "secret parameter FEED differs"
pl_all="$plrec"
plsum="$(bash "$RENDER" --record "$TEST_TMPDIR/pulumi-leaks.json" --out "$TEST_TMPDIR/pulumi-leaks-out" --dialect c4-plantuml --diff prod staging)"
pl_all="$pl_all$(cat "$TEST_TMPDIR/pulumi-leaks-out/deployment.md")$plsum"
bash "$RENDER" --record "$TEST_TMPDIR/pulumi-leaks.json" --out "$TEST_TMPDIR/pulumi-leaks-l" --dialect likec4 >/dev/null
pl_all="$pl_all$(cat "$TEST_TMPDIR/pulumi-leaks-l/deployment.md")"
for needle in "${pul_needles[@]}"; do
  assert_not_contains "pulumi record, renders and summary hold no ${needle:0:12}" "$pl_all" "$needle"
done

# Pulumi runtimes: only a program written in Pulumi.yaml is read. Every other runtime, and a
# yaml project with a compiler or a main, is declined by the tool name with its runtime cited.
for rt in nodejs python go dotnet java; do
  declining_fixture "$TEST_TMPDIR/pulumi-rt" Pulumi.yaml "$(printf 'name: web\nruntime: %s' "$rt")"
  printf 'config:\n  aws:region: us-east-1\n' >"$TEST_TMPDIR/pulumi-rt/Pulumi.dev.yaml"
  git -C "$TEST_TMPDIR/pulumi-rt" add -A && git -C "$TEST_TMPDIR/pulumi-rt" commit -q -m stack
  bash "$COLLECT" --repo "$TEST_TMPDIR/pulumi-rt" --out "$TEST_TMPDIR/pulumi-rt.json" --generated-on 2026-09-28
  rtrec="$(cat "$TEST_TMPDIR/pulumi-rt.json")"
  assert_contains "a $rt Pulumi project is refused" "$rtrec" '"reason": "adapter-not-shipped"'
  assert_contains "a $rt Pulumi project is declined by name" "$rtrec" "\"name\":\"pulumi\",\"shipped\":\"no\",\"evidence\":\"Pulumi.yaml (runtime $rt)\""
  assert_contains "a $rt Pulumi project draws nothing" "$rtrec" '"placements": []'
done
declining_fixture "$TEST_TMPDIR/pulumi-rt" Pulumi.yaml $'name: web\nruntime:\n  name: nodejs\n  options:\n    typescript: false'
bash "$COLLECT" --repo "$TEST_TMPDIR/pulumi-rt" --out "$TEST_TMPDIR/pulumi-rt.json" --generated-on 2026-09-28
assert_contains "the object runtime form names its runtime" "$(cat "$TEST_TMPDIR/pulumi-rt.json")" '(runtime nodejs)'
declining_fixture "$TEST_TMPDIR/pulumi-rt" Pulumi.yaml $'name: web\nruntime:\n  name: yaml\n  options:\n    compiler: cue export'
bash "$COLLECT" --repo "$TEST_TMPDIR/pulumi-rt" --out "$TEST_TMPDIR/pulumi-rt.json" --generated-on 2026-09-28
assert_contains "a yaml runtime with a compiler is declined" "$(cat "$TEST_TMPDIR/pulumi-rt.json")" '"reason": "adapter-not-shipped"'
declining_fixture "$TEST_TMPDIR/pulumi-rt" Pulumi.yaml $'name: web\nruntime: yaml\nmain: ./sub'
bash "$COLLECT" --repo "$TEST_TMPDIR/pulumi-rt" --out "$TEST_TMPDIR/pulumi-rt.json" --generated-on 2026-09-28
assert_contains "a yaml project with a main directory is declined" "$(cat "$TEST_TMPDIR/pulumi-rt.json")" '"reason": "adapter-not-shipped"'
for form in $'runtime: yaml' $'runtime: "yaml"' $'runtime: yaml # the program is this file' $'runtime:\n  name: yaml'; do
  declining_fixture "$TEST_TMPDIR/pulumi-rt" Pulumi.yaml "$(printf 'name: web\n%s\nresources:\n  cluster:\n    type: aws:ecs:Cluster' "$form")"
  bash "$COLLECT" --repo "$TEST_TMPDIR/pulumi-rt" --out "$TEST_TMPDIR/pulumi-rt.json" --generated-on 2026-09-28
  assert_contains "the runtime form [${form//$'\n'/ }] is read" "$(cat "$TEST_TMPDIR/pulumi-rt.json")" '"id":"default/cluster"'
done
repoPM="$TEST_TMPDIR/pulumi-mixed"
init_repo "$repoPM"
mkdir -p "$repoPM/a" "$repoPM/b"
printf 'name: a\nruntime: yaml\nresources:\n  cluster:\n    type: aws:ecs:Cluster\n' >"$repoPM/a/Pulumi.yaml"
printf 'name: b\nruntime: nodejs\n' >"$repoPM/b/Pulumi.yaml"
commit_all "$repoPM"
bash "$COLLECT" --repo "$repoPM" --out "$TEST_TMPDIR/pulumi-mixed.json" --generated-on 2026-09-28
pmrec="$(cat "$TEST_TMPDIR/pulumi-mixed.json")"
assert_contains "a yaml and a nodejs project is a partial read" "$pmrec" '"reason": "partial-read"'
assert_contains "the mixed record lists the shipped project" "$pmrec" '"name":"pulumi-yaml","shipped":"yes","evidence":"a/Pulumi.yaml"'
assert_contains "the mixed record declines the other by name" "$pmrec" '"name":"pulumi","shipped":"no","evidence":"b/Pulumi.yaml (runtime nodejs)"'
declining_fixture "$TEST_TMPDIR/pulumi-orphan" Pulumi.dev.yaml $'config:\n  aws:region: us-east-1'
bash "$COLLECT" --repo "$TEST_TMPDIR/pulumi-orphan" --out "$TEST_TMPDIR/pulumi-orphan.json" --generated-on 2026-09-28
assert_contains "a stack file alone is not IaC" "$(cat "$TEST_TMPDIR/pulumi-orphan.json")" '"reason": "no-declared-iac"'
declining_fixture "$TEST_TMPDIR/pulumi-bad" Pulumi.yaml $'name: web\nruntime: yaml\nresources:\n  cluster: &c\n    type: aws:ecs:Cluster'
bash "$COLLECT" --repo "$TEST_TMPDIR/pulumi-bad" --out "$TEST_TMPDIR/pulumi-bad.json" --generated-on 2026-09-28
assert_contains "a Pulumi.yaml that does not parse is refused by name" "$(cat "$TEST_TMPDIR/pulumi-bad.json")" '"reason": "pulumi-unreadable:Pulumi.yaml"'
printf 'config:\n\tweb:a: b\n' >"$TEST_TMPDIR/pulumi-bad/Pulumi.prod.yaml"
printf 'name: web\nruntime: yaml\n' >"$TEST_TMPDIR/pulumi-bad/Pulumi.yaml"
git -C "$TEST_TMPDIR/pulumi-bad" add -A && git -C "$TEST_TMPDIR/pulumi-bad" commit -q -m stack
bash "$COLLECT" --repo "$TEST_TMPDIR/pulumi-bad" --out "$TEST_TMPDIR/pulumi-bad.json" --generated-on 2026-09-28
assert_contains "a stack file that does not parse is refused by name" "$(cat "$TEST_TMPDIR/pulumi-bad.json")" '"reason": "pulumi-unreadable:Pulumi.prod.yaml"'

# CloudFormation and Pulumi YAML in one repository are both read, each diffed only against itself.
repoCP="$TEST_TMPDIR/cfn-pulumi"
init_repo "$repoCP"
mkdir -p "$repoCP/cfn" "$repoCP/pulumi"
printf '%s\n' "$cfn_ecs" >"$repoCP/cfn/stack.yaml"
printf 'name: a\nruntime: yaml\nresources:\n  cluster:\n    type: aws:ecs:Cluster\n' >"$repoCP/pulumi/Pulumi.yaml"
commit_all "$repoCP"
bash "$COLLECT" --repo "$repoCP" --out "$TEST_TMPDIR/cfn-pulumi.json" --generated-on 2026-09-28
cprec="$(cat "$TEST_TMPDIR/cfn-pulumi.json")"
assert_contains "cloudformation beside pulumi yaml is drawn" "$cprec" '"status": "drawn"'
assert_contains "the cloudformation environment is its directory" "$cprec" '"environment":"cfn","tool":"cloudformation"'
assert_contains "the pulumi environment is its directory" "$cprec" '"environment":"pulumi","tool":"pulumi-yaml"'

# A read that drops resources says so, and one that places no container is refused. A repository is
# never drawn from part of what its readers parsed without the rest being named.
unm_check() {
  local dir="$1"
  bash "$COLLECT" --repo "$dir" --out "$dir.json" --generated-on 2026-09-28
  unm_rec="$(cat "$dir.json")"
  unm_sum="$(bash "$RENDER" --record "$dir.json" --out "$dir-out" --dialect likec4)"
  unm_md="$(cat "$dir-out/deployment.md")"
}
unm_fixture() {
  local dir="$TEST_TMPDIR/unm-$1"
  shift
  rm -rf "$dir"
  init_repo "$dir"
  while [[ $# -ge 2 ]]; do
    mkdir -p "$dir/$(dirname "$1")"
    printf '%s\n' "$2" >"$dir/$1"
    shift 2
  done
  commit_all "$dir"
}
tf_ecs=$'resource "aws_ecs_cluster" "c" {\n  name = "c"\n}\nresource "aws_ecs_task_definition" "api" {\n  family = "api"\n  container_definitions = jsonencode([{ name = "api", image = "acme/api:1" }])\n}\nresource "aws_ecs_service" "api" {\n  name            = "api"\n  cluster         = aws_ecs_cluster.c.id\n  task_definition = aws_ecs_task_definition.api.arn\n}'
tf_lambda=$'resource "aws_lambda_function" "fn" {\n  function_name = "fn"\n}'
tf_helm=$'resource "helm_release" "api" {\n  name  = "api"\n  chart = "api"\n}'

unm_fixture tf-helm main.tf "$tf_helm"
unm_check "$TEST_TMPDIR/unm-tf-helm"
assert_contains "a helm_release is a partial read, not an empty drawing" "$unm_rec" '"reason": "partial-read"'
assert_contains "a helm_release names helm as declined" "$unm_rec" '"name":"helm","shipped":"no","evidence":"main.tf (helm_release)"'
assert_not_contains "a helm_release draws nothing" "$unm_md" '```likec4'
assert_contains "a refusal for another reason carries no unmapped list" "$unm_sum" "unmapped=0"

unm_fixture tf-ecs-helm main.tf "$tf_ecs"$'\n'"$tf_helm"
unm_check "$TEST_TMPDIR/unm-tf-ecs-helm"
assert_contains "ECS beside a helm_release is a partial read" "$unm_rec" '"reason": "partial-read"'

unm_fixture tf-helm-json main.tf.json '{"resource":{"helm_release":{"api":{"name":"api"}}}}'
unm_check "$TEST_TMPDIR/unm-tf-helm-json"
assert_contains "a helm_release in .tf.json is a partial read" "$unm_rec" '"reason": "partial-read"'

unm_fixture tf-lambda main.tf "$tf_lambda"$'\nresource "aws_s3_bucket" "b" {\n  bucket = "b"\n}'
unm_check "$TEST_TMPDIR/unm-tf-lambda"
assert_contains "a Terraform root that maps no container is refused" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "the refusal keeps the unmapped lambda" "$unm_rec" '{"tool":"terraform","type":"aws_lambda_function","evidence":"main.tf"}'
assert_contains "the refusal keeps the unmapped bucket" "$unm_rec" '{"tool":"terraform","type":"aws_s3_bucket","evidence":"main.tf"}'
assert_contains "the refusal prose says why" "$unm_md" "would look like a full read"
assert_contains "the refusal lists the types" "$unm_md" '| terraform | aws_lambda_function | main.tf |'
assert_not_contains "the refusal draws no environment" "$unm_md" '```likec4'
assert_contains "the summary counts the unmapped types" "$unm_sum" "status=refused reason=no-mapped-container"
assert_contains "the summary ends with the unmapped count" "$unm_sum" "unmapped=2"

unm_fixture tf-mixed main.tf "$tf_ecs"$'\n'"$tf_lambda"$'\nresource "aws_iam_role" "r" {\n  name = "r"\n}'
unm_check "$TEST_TMPDIR/unm-tf-mixed"
assert_contains "a mixed root still draws its containers" "$unm_rec" '"status": "drawn"'
assert_contains "a mixed root lists the lambda it did not draw" "$unm_rec" '{"tool":"terraform","type":"aws_lambda_function","evidence":"main.tf"}'
assert_contains "a mixed root lists the role it did not draw" "$unm_rec" '{"tool":"terraform","type":"aws_iam_role","evidence":"main.tf"}'
assert_not_contains "a type the reader maps is not listed" "$unm_rec" '"type":"aws_ecs'
assert_contains "a mixed root reports the placement" "$unm_sum" "placements=1"
assert_contains "a mixed root reports the count" "$unm_sum" "unmapped=2"
assert_contains "a mixed root renders the unmapped section" "$unm_md" '## Unmapped resources'
assert_contains "a mixed root renders the unmapped type" "$unm_md" '| terraform | aws_lambda_function | main.tf |'

unm_fixture tf-module main.tf $'module "fn" {\n  source = "./fn"\n}' fn/main.tf "$tf_lambda"
unm_check "$TEST_TMPDIR/unm-tf-module"
assert_contains "a resource inside a local module is unmapped by its own file" "$unm_rec" '{"tool":"terraform","type":"aws_lambda_function","evidence":"fn/main.tf"}'
assert_contains "a module-only root that maps nothing is refused" "$unm_rec" '"reason": "no-mapped-container"'

unm_fixture tf-envs envs/dev/main.tf "$tf_ecs"$'\n'"$tf_lambda" envs/prod/main.tf "$tf_ecs"$'\n'"$tf_lambda"
unm_check "$TEST_TMPDIR/unm-tf-envs"
assert_equals "an unmapped type is listed once per file, not once per environment" "$(grep -c '{"tool":"terraform","type":"aws_lambda_function"' "$TEST_TMPDIR/unm-tf-envs.json")" "2"

unm_fixture tf-clean main.tf "$tf_ecs"
unm_check "$TEST_TMPDIR/unm-tf-clean"
assert_contains "a fully mapped root is drawn" "$unm_rec" '"status": "drawn"'
assert_contains "a fully mapped root reports no unmapped resource" "$unm_sum" "unmapped=0"
assert_not_contains "a fully mapped root has no unmapped section" "$unm_md" 'Unmapped resources'

# A mapped resource whose containers are a dynamic block or an expression still places one
# container, its image unresolved, so it never disappears from a drawing that names the rest.
tf_env=$'resource "azurerm_container_app_environment" "env" {\n  name = "env"\n}'
tf_dyn_app=$'resource "azurerm_container_app" "dyn" {\n  name                         = "dynapp"\n  container_app_environment_id = azurerm_container_app_environment.env.id\n  template {\n    dynamic "container" {\n      for_each = var.containers\n      content {\n        name  = container.value.name\n        image = container.value.image\n      }\n    }\n  }\n}'
tf_static_app=$'resource "azurerm_container_app" "plain" {\n  name                         = "plainapp"\n  container_app_environment_id = azurerm_container_app_environment.env.id\n  template {\n    container {\n      name  = "plainapp"\n      image = "acme/plain:1"\n    }\n  }\n}'
tf_env_node='"node":"default/azurerm_container_app_environment.env","compute":"default/azurerm_container_app_environment.env"'

unm_fixture tf-dyn-only main.tf "$tf_env"$'\n'"$tf_dyn_app"
unm_check "$TEST_TMPDIR/unm-tf-dyn-only"
assert_contains "an app whose containers are a dynamic block is drawn" "$unm_rec" '"status": "drawn"'
assert_contains "the dynamic app places one container with an unresolved image" "$unm_rec" '"container":"dyn","env":"default","tool":"terraform",'"$tf_env_node"',"image":"unresolved:dynamic container"'
assert_contains "the dynamic app is counted as a placement" "$unm_sum" "placements=1"
assert_contains "the rendered view carries the unresolved image" "$unm_md" "unresolved:dynamic container"

unm_fixture tf-dyn-mixed main.tf "$tf_env"$'\n'"$tf_dyn_app"$'\n'"$tf_static_app"
unm_check "$TEST_TMPDIR/unm-tf-dyn-mixed"
assert_contains "a mixed root places the plain app" "$unm_rec" '"container":"plainapp","env":"default","tool":"terraform",'"$tf_env_node"',"image":"acme/plain:1"'
assert_contains "a mixed root keeps the dynamic app" "$unm_rec" '"container":"dyn","env":"default","tool":"terraform",'"$tf_env_node"',"image":"unresolved:dynamic container"'
assert_contains "a mixed root counts both" "$unm_sum" "placements=2"

unm_fixture tf-dyn-beside main.tf "$tf_env"$'\nresource "azurerm_container_app" "app" {\n  name                         = "app"\n  container_app_environment_id = azurerm_container_app_environment.env.id\n  template {\n    container {\n      name  = "app"\n      image = "acme/app:1"\n    }\n    dynamic "container" {\n      for_each = var.sidecars\n      content {\n        name = container.value.name\n      }\n    }\n  }\n}'
unm_check "$TEST_TMPDIR/unm-tf-dyn-beside"
assert_contains "a plain container keeps its image beside a dynamic block" "$unm_rec" '"container":"app","env":"default","tool":"terraform",'"$tf_env_node"',"image":"acme/app:1"'
assert_contains "the dynamic block beside it is its own placement" "$unm_rec" '"container":"app.dynamic","env":"default","tool":"terraform",'"$tf_env_node"',"image":"unresolved:dynamic container"'
assert_contains "both are counted" "$unm_sum" "placements=2"

unm_fixture tf-dyn-others main.tf $'resource "google_cloud_run_v2_service" "svc" {\n  name = "svc"\n  template {\n    dynamic "containers" {\n      for_each = var.c\n      content {\n        image = containers.value\n      }\n    }\n  }\n}\nresource "kubernetes_deployment" "wl" {\n  metadata {\n    name = "wl"\n  }\n  spec {\n    template {\n      spec {\n        dynamic "container" {\n          for_each = var.c\n          content {\n            image = container.value\n          }\n        }\n      }\n    }\n  }\n}'
unm_check "$TEST_TMPDIR/unm-tf-dyn-others"
assert_contains "a Cloud Run service with dynamic containers places one" "$unm_rec" '"container":"svc","env":"default","tool":"terraform","node":"default","compute":"","image":"unresolved:dynamic containers"'
assert_contains "a Kubernetes workload with a dynamic container places one on its node" "$unm_rec" '"container":"wl","env":"default","tool":"terraform","node":"default/kubernetes_deployment.wl","compute":"default/kubernetes_deployment.wl","image":"unresolved:dynamic container"'
assert_contains "both are counted" "$unm_sum" "placements=2"

# shellcheck disable=SC2016 # ${...} is literal Terraform interpolation
unm_fixture tf-dyn-json main.tf.json '{"resource":{"azurerm_container_app":{"j":{"name":"j","template":{"dynamic":{"container":{"for_each":"${var.c}","content":{"name":"n","image":"i"}}}}}}}}'
unm_check "$TEST_TMPDIR/unm-tf-dyn-json"
assert_contains "a dynamic block in .tf.json places one container" "$unm_rec" '"container":"j","env":"default","tool":"terraform","node":"default","compute":"","image":"unresolved:dynamic container"'

unm_fixture tf-expr-containers main.tf $'resource "azurerm_container_app" "x" {\n  name = "x"\n  template {\n    container = var.containers\n  }\n}'
unm_check "$TEST_TMPDIR/unm-tf-expr-containers"
assert_contains "a container list that is an expression places one container" "$unm_rec" '"container":"x","env":"default","tool":"terraform","node":"default","compute":"","image":"unresolved:container"'

# A resource with an empty body has no attribute rows, and is still placed or listed.
tf_empty_bucket=$'resource "aws_s3_bucket" "b" {}'
unm_fixture tf-empty main.tf "$tf_empty_bucket"
unm_check "$TEST_TMPDIR/unm-tf-empty"
assert_contains "a root of only an empty-body resource is refused" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "the empty-body bucket is listed" "$unm_rec" '{"tool":"terraform","type":"aws_s3_bucket","evidence":"main.tf"}'
assert_contains "the empty-body bucket is counted" "$unm_sum" "unmapped=1"

unm_fixture tf-empty-null main.tf $'resource "null_resource" "n" {\n  triggers = {}\n}'
unm_check "$TEST_TMPDIR/unm-tf-empty-null"
assert_contains "a resource whose only content is an empty map is refused" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "the null_resource is listed" "$unm_rec" '{"tool":"terraform","type":"null_resource","evidence":"main.tf"}'

unm_fixture tf-empty-mixed main.tf "$tf_ecs"$'\n'"$tf_empty_bucket"
unm_check "$TEST_TMPDIR/unm-tf-empty-mixed"
assert_contains "a mixed root with an empty-body bucket is drawn" "$unm_rec" '"status": "drawn"'
assert_contains "the empty-body bucket is listed beside the placed container" "$unm_rec" '{"tool":"terraform","type":"aws_s3_bucket","evidence":"main.tf"}'
assert_contains "the placed container is counted" "$unm_sum" "placements=1"
assert_contains "only the bucket is unmapped" "$unm_sum" "unmapped=1"

unm_fixture tf-empty-json main.tf.json '{"resource":{"aws_s3_bucket":{"b":{}}}}'
unm_check "$TEST_TMPDIR/unm-tf-empty-json"
assert_contains "a .tf.json root of only an empty-body resource is refused" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "the .tf.json empty-body bucket is listed" "$unm_rec" '{"tool":"terraform","type":"aws_s3_bucket","evidence":"main.tf.json"}'

unm_fixture tf-empty-json-mixed main.tf.json '{"resource":{"azurerm_container_app":{"j":{"name":"j","template":{"container":{"name":"j","image":"acme/j:1"}}}},"aws_s3_bucket":{"b":{}}}}'
unm_check "$TEST_TMPDIR/unm-tf-empty-json-mixed"
assert_contains "a mixed .tf.json root is drawn" "$unm_rec" '"status": "drawn"'
assert_contains "the .tf.json empty-body bucket is listed beside the container" "$unm_rec" '{"tool":"terraform","type":"aws_s3_bucket","evidence":"main.tf.json"}'
assert_contains "the .tf.json container is counted" "$unm_sum" "placements=1"

unm_fixture tf-empty-taskdef main.tf $'resource "aws_ecs_task_definition" "t" {}'
unm_check "$TEST_TMPDIR/unm-tf-empty-taskdef"
assert_contains "an empty task definition places one container with an unresolved image" "$unm_rec" '"container":"t","env":"default","tool":"terraform","node":"default","compute":"","image":"unresolved:container_definitions"'
assert_contains "the empty task definition is counted as a placement" "$unm_sum" "placements=1"

unm_fixture cfn-eks t.yaml $'AWSTemplateFormatVersion: "2010-09-09"\nResources:\n  Cluster:\n    Type: AWS::EKS::Cluster\n    Properties: {}\n  Fn:\n    Type: AWS::Lambda::Function\n    Properties: {}'
unm_check "$TEST_TMPDIR/unm-cfn-eks"
assert_contains "a CloudFormation template that maps no container is refused" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "the EKS cluster is listed" "$unm_rec" '{"tool":"cloudformation","type":"AWS::EKS::Cluster","evidence":"t.yaml"}'
assert_contains "the lambda is listed" "$unm_rec" '{"tool":"cloudformation","type":"AWS::Lambda::Function","evidence":"t.yaml"}'

unm_fixture cfn-mixed t.yaml $'Resources:\n  Cluster:\n    Type: AWS::ECS::Cluster\n  Task:\n    Type: AWS::ECS::TaskDefinition\n    Properties:\n      ContainerDefinitions:\n        - Name: api\n          Image: acme/api:1\n  Fn:\n    Type: AWS::Lambda::Function'
unm_check "$TEST_TMPDIR/unm-cfn-mixed"
assert_contains "a mixed template draws its containers" "$unm_rec" '"status": "drawn"'
assert_contains "a mixed template lists the lambda" "$unm_rec" '{"tool":"cloudformation","type":"AWS::Lambda::Function","evidence":"t.yaml"}'
assert_not_contains "the ECS types are not listed" "$unm_rec" '"type":"AWS::ECS'
assert_contains "a mixed template reports the count" "$unm_sum" "unmapped=1"

unm_fixture bicep-storage main.bicep $'resource sa \'Microsoft.Storage/storageAccounts@2023-01-01\' = {\n  name: \'sa\'\n  location: \'x\'\n}'
unm_check "$TEST_TMPDIR/unm-bicep-storage"
assert_contains "a Bicep file that maps no container is refused" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "the storage account is listed" "$unm_rec" '{"tool":"bicep","type":"Microsoft.Storage/storageAccounts","evidence":"main.bicep"}'

unm_fixture arm-storage main.json "{\"\$schema\":\"$arm_schema\",\"contentVersion\":\"1.0.0.0\",\"resources\":[{\"type\":\"Microsoft.Storage/storageAccounts\",\"apiVersion\":\"2023-01-01\",\"name\":\"sa\"}]}"
unm_check "$TEST_TMPDIR/unm-arm-storage"
assert_contains "an ARM template that maps no container is refused" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "the ARM type is listed under arm" "$unm_rec" '{"tool":"arm","type":"Microsoft.Storage/storageAccounts","evidence":"main.json"}'

# A child resource nested in its parent is listed under its full type, never dropped behind the
# parent: a Bicep `resource x 'child'` inside a body, an ARM resources array inside a resource.
bicep_site=$'resource site \'Microsoft.Web/sites@2022-09-01\' = {\n  name: \'web\'\n  properties: {\n    siteConfig: {\n      linuxFxVersion: \'DOCKER|nginx:1\'\n    }\n  }\n  resource slot \'slots\' = {\n    name: \'staging\'\n    properties: {\n      siteConfig: {\n        linuxFxVersion: \'DOCKER|nginx:2\'\n      }\n    }\n  }\n}'
bicep_blob=$'resource sa \'Microsoft.Storage/storageAccounts@2023-01-01\' = {\n  name: \'sa\'\n  resource blob \'blobServices\' = {\n    name: \'default\'\n    resource c \'containers@2023-01-01\' = {\n      name: \'data\'\n    }\n  }\n}'
unm_fixture bicep-nested main.bicep "$bicep_site"$'\n'"$bicep_blob"
unm_check "$TEST_TMPDIR/unm-bicep-nested"
assert_contains "a site with a nested slot is still drawn" "$unm_rec" '"status": "drawn"'
assert_contains "the parent site is placed" "$unm_rec" '"container":"web","env":"default","tool":"bicep"'
assert_not_contains "the nested slot is not placed as if it were the site" "$unm_rec" 'nginx:2'
assert_contains "a nested slot is listed under its full type" "$unm_rec" '{"tool":"bicep","type":"Microsoft.Web/sites/slots","evidence":"main.bicep"}'
assert_contains "a child of a storage account is listed under its full type" "$unm_rec" '{"tool":"bicep","type":"Microsoft.Storage/storageAccounts/blobServices","evidence":"main.bicep"}'
assert_contains "a grandchild is listed under its full type" "$unm_rec" '{"tool":"bicep","type":"Microsoft.Storage/storageAccounts/blobServices/containers","evidence":"main.bicep"}'
assert_not_contains "the mapped parent site is not listed" "$unm_rec" '"type":"Microsoft.Web/sites"'
assert_contains "the nested resources are counted" "$unm_sum" "unmapped=4"
assert_contains "the nested slot is in the unmapped table" "$unm_md" '| bicep | Microsoft.Web/sites/slots | main.bicep |'

unm_fixture bicep-nested-refused main.bicep "$bicep_blob"
unm_check "$TEST_TMPDIR/unm-bicep-nested-refused"
assert_contains "a Bicep storage account with nested children maps no container and is refused" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "the nested Bicep child is listed in the refusal" "$unm_rec" '{"tool":"bicep","type":"Microsoft.Storage/storageAccounts/blobServices","evidence":"main.bicep"}'

arm_site="{\"type\":\"Microsoft.Web/sites\",\"name\":\"web\",\"properties\":{\"siteConfig\":{\"linuxFxVersion\":\"DOCKER|nginx:1\"}},\"resources\":[{\"type\":\"slots\",\"name\":\"staging\",\"properties\":{\"siteConfig\":{\"linuxFxVersion\":\"DOCKER|nginx:2\"}}}]}"
arm_blob='{"name":"sa","resources":[{"type":"blobServices","name":"default","resources":[{"type":"containers","name":"data"}]}],"type":"Microsoft.Storage/storageAccounts"}'
unm_fixture arm-nested main.json "{\"\$schema\":\"$arm_schema\",\"contentVersion\":\"1.0.0.0\",\"resources\":[$arm_site,$arm_blob]}"
unm_check "$TEST_TMPDIR/unm-arm-nested"
assert_contains "an ARM site with a nested slot is still drawn" "$unm_rec" '"status": "drawn"'
assert_contains "the ARM parent site is placed" "$unm_rec" '"container":"web","env":"default","tool":"arm"'
assert_not_contains "the nested ARM slot is not placed as if it were the site" "$unm_rec" 'nginx:2'
assert_contains "a nested ARM slot is listed under its full type" "$unm_rec" '{"tool":"arm","type":"Microsoft.Web/sites/slots","evidence":"main.json"}'
assert_contains "an ARM child is listed under its full type" "$unm_rec" '{"tool":"arm","type":"Microsoft.Storage/storageAccounts/blobServices","evidence":"main.json"}'
assert_contains "an ARM grandchild is listed under its full type" "$unm_rec" '{"tool":"arm","type":"Microsoft.Storage/storageAccounts/blobServices/containers","evidence":"main.json"}'
assert_not_contains "the mapped ARM parent site is not listed" "$unm_rec" '"type":"Microsoft.Web/sites"'
assert_contains "the nested ARM resources are counted" "$unm_sum" "unmapped=4"

unm_fixture arm-nested-refused main.json "{\"\$schema\":\"$arm_schema\",\"contentVersion\":\"1.0.0.0\",\"resources\":[$arm_blob]}"
unm_check "$TEST_TMPDIR/unm-arm-nested-refused"
assert_contains "an ARM storage account with nested children maps no container and is refused" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "the nested ARM child is listed in the refusal" "$unm_rec" '{"tool":"arm","type":"Microsoft.Storage/storageAccounts/blobServices","evidence":"main.json"}'

unm_fixture arm-nested-symbolic main.json "{\"\$schema\":\"$arm_schema\",\"languageVersion\":\"2.0\",\"contentVersion\":\"1.0.0.0\",\"resources\":{\"site\":{\"type\":\"Microsoft.Web/sites\",\"name\":\"web\",\"properties\":{\"siteConfig\":{\"linuxFxVersion\":\"DOCKER|nginx:1\"}},\"resources\":{\"slot\":{\"type\":\"slots\",\"name\":\"staging\"}}}}}"
unm_check "$TEST_TMPDIR/unm-arm-nested-symbolic"
assert_contains "a nested child under a symbolic-name resource is listed under its full type" "$unm_rec" '{"tool":"arm","type":"Microsoft.Web/sites/slots","evidence":"main.json"}'
assert_not_contains "the symbolic-name parent site is not listed" "$unm_rec" '"type":"Microsoft.Web/sites"'

unm_fixture pulumi-bucket Pulumi.yaml $'name: p\nruntime: yaml\nresources:\n  bucket:\n    type: aws:s3:Bucket'
unm_check "$TEST_TMPDIR/unm-pulumi-bucket"
assert_contains "a Pulumi program that maps no container is refused" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "the bucket is listed" "$unm_rec" '{"tool":"pulumi-yaml","type":"aws:s3:Bucket","evidence":"Pulumi.yaml"}'

unm_fixture pulumi-mixed Pulumi.yaml $'name: p\nruntime: yaml\nresources:\n  cluster:\n    type: aws:ecs:Cluster\n  bucket:\n    type: aws:s3:Bucket'
unm_check "$TEST_TMPDIR/unm-pulumi-mixed"
assert_contains "a mixed Pulumi program lists the bucket" "$unm_rec" '{"tool":"pulumi-yaml","type":"aws:s3:Bucket","evidence":"Pulumi.yaml"}'
assert_not_contains "a mapped Pulumi type is not listed" "$unm_rec" '"type":"aws:ecs'

unm_fixture pulumi-helm Pulumi.yaml $'name: p\nruntime: yaml\nresources:\n  cluster:\n    type: aws:ecs:Cluster\n  chart:\n    type: kubernetes:helm.sh/v3:Release'
unm_check "$TEST_TMPDIR/unm-pulumi-helm"
assert_contains "a Pulumi Helm release is a partial read" "$unm_rec" '"reason": "partial-read"'
assert_contains "a Pulumi Helm release names helm as declined" "$unm_rec" '"name":"helm","shipped":"no","evidence":"Pulumi.yaml (kubernetes:helm.sh)"'

unm_check "$repo"
assert_contains "a Compose record reports no unmapped resource" "$unm_sum" "unmapped=0"

# A helm_release inside a Terraform block comment is not a Helm release.
unm_fixture tf-helm-comment main.tf $'/*\nresource "helm_release" "old" {\n  name = "old"\n}\n*/\nresource "azurerm_container_app" "api" {\n  name = "api"\n  template {\n    container {\n      name  = "api"\n      image = "ghcr.io/acme/api:1"\n    }\n  }\n}'
unm_check "$TEST_TMPDIR/unm-tf-helm-comment"
assert_contains "a commented helm_release leaves the Terraform root drawn" "$unm_rec" '"status": "drawn"'
assert_not_contains "a commented helm_release names no helm tool" "$unm_rec" '"name":"helm"'

# COMPOSE_FILE entries spelled with a leading ./ name the tracked files.
unm_fixture compose-dot-slash compose.yaml $'services:\n  web:\n    image: nginx:1' compose.prod.yaml $'services:\n  web:\n    image: nginx:2' .env $'COMPOSE_FILE=./compose.yaml:./compose.prod.yaml'
unm_check "$TEST_TMPDIR/unm-compose-dot-slash"
assert_contains "COMPOSE_FILE entries with a leading ./ merge" "$unm_rec" '"status": "drawn"'
assert_contains "the later ./ layer overrides the image" "$unm_rec" 'nginx:2'

# Two tools that name the same environment draw one environment with each container once.
unm_fixture same-env compose.yaml $'services:\n  web:\n    image: nginx:1' main.tf $'resource "azurerm_container_app" "api" {\n  name = "api"\n  template {\n    container {\n      name  = "api"\n      image = "ghcr.io/acme/api:1"\n    }\n  }\n}'
unm_check "$TEST_TMPDIR/unm-same-env"
assert_contains "two tools in one environment place each container once" "$unm_sum" "placements=2"
assert_equals "one default environment is drawn" "$(grep -c "= environment 'default'" <<<"$unm_md")" "1"
assert_equals "each container is an instanceOf once" "$(grep -c 'instanceOf' <<<"$unm_md")" "2"

# A container app, container group or ECS task definition with no containers still places one
# container named for it, its image unresolved, so the resource is never dropped.
unm_fixture bicep-app-none main.bicep $'resource app \'Microsoft.App/containerApps@2023-05-01\' = {\n  name: \'api\'\n  properties: {\n    template: {\n      scale: { minReplicas: 1 }\n    }\n  }\n}'
unm_check "$TEST_TMPDIR/unm-bicep-app-none"
assert_contains "a Bicep container app with no containers places one" "$unm_rec" '"container":"api","env":"default","tool":"bicep","node":"default","compute":"","image":"unresolved:containers"'
unm_fixture bicep-app-empty main.bicep $'resource app \'Microsoft.App/containerApps@2023-05-01\' = {\n  name: \'api\'\n  properties: {\n    template: {\n      containers: []\n    }\n  }\n}'
unm_check "$TEST_TMPDIR/unm-bicep-app-empty"
assert_contains "a Bicep container app with an empty containers list places one" "$unm_rec" '"container":"api","env":"default","tool":"bicep","node":"default","compute":"","image":"unresolved:containers"'
unm_fixture arm-group-empty main.json "{\"\$schema\":\"$arm_schema\",\"contentVersion\":\"1.0.0.0\",\"resources\":[{\"type\":\"Microsoft.ContainerInstance/containerGroups\",\"name\":\"g\",\"properties\":{}}]}"
unm_check "$TEST_TMPDIR/unm-arm-group-empty"
assert_contains "an ARM container group with no containers places one in the group" "$unm_rec" '"container":"g","env":"default","tool":"arm","node":"default/resources[0]","compute":"default/resources[0]","image":"unresolved:containers"'
unm_fixture cfn-td-none template.yaml $'Resources:\n  Td:\n    Type: AWS::ECS::TaskDefinition\n    Properties:\n      Family: api'
unm_check "$TEST_TMPDIR/unm-cfn-td-none"
assert_contains "a CloudFormation task definition with no container definitions places one" "$unm_rec" '"container":"Td","env":"default","tool":"cloudformation","node":"default","compute":"","image":"unresolved:containerDefinitions"'
unm_fixture cfn-td-empty template.yaml $'Resources:\n  Td:\n    Type: AWS::ECS::TaskDefinition\n    Properties:\n      ContainerDefinitions: []'
unm_check "$TEST_TMPDIR/unm-cfn-td-empty"
assert_contains "a CloudFormation task definition with an empty list places one" "$unm_rec" '"container":"Td","env":"default","tool":"cloudformation","node":"default","compute":"","image":"unresolved:containerDefinitions"'
unm_fixture pulumi-td-none Pulumi.yaml $'name: p\nruntime: yaml\nresources:\n  td:\n    type: aws:ecs:TaskDefinition\n    properties:\n      family: api'
unm_check "$TEST_TMPDIR/unm-pulumi-td-none"
assert_contains "a Pulumi task definition with no container definitions places one" "$unm_rec" '"container":"td","env":"default","tool":"pulumi-yaml","node":"default","compute":"","image":"unresolved:containerDefinitions"'
unm_fixture pulumi-td-empty Pulumi.yaml $'name: p\nruntime: yaml\nresources:\n  td:\n    type: aws:ecs:TaskDefinition\n    properties:\n      containerDefinitions: []'
unm_check "$TEST_TMPDIR/unm-pulumi-td-empty"
assert_contains "a Pulumi task definition with an empty list places one" "$unm_rec" '"container":"td","env":"default","tool":"pulumi-yaml","node":"default","compute":"","image":"unresolved:containerDefinitions"'

# A second ECS service on a task definition another service already runs is listed, not dropped.
unm_fixture tf-shared-td main.tf "$tf_ecs"$'\nresource "aws_ecs_service" "api2" {\n  name            = "api2"\n  task_definition = aws_ecs_task_definition.api.arn\n}'
unm_check "$TEST_TMPDIR/unm-tf-shared-td"
assert_contains "a Terraform service sharing a task definition keeps the root drawn" "$unm_rec" '"status": "drawn"'
assert_contains "a second Terraform service on one task definition is listed" "$unm_rec" '{"tool":"terraform","type":"aws_ecs_service","evidence":"main.tf"}'
unm_fixture cfn-shared-td template.yaml $'Resources:\n  Td:\n    Type: AWS::ECS::TaskDefinition\n    Properties:\n      ContainerDefinitions:\n        - Name: api\n          Image: acme/api:1\n  One:\n    Type: AWS::ECS::Service\n    Properties:\n      TaskDefinition: !Ref Td\n  Two:\n    Type: AWS::ECS::Service\n    Properties:\n      TaskDefinition: !Ref Td'
unm_check "$TEST_TMPDIR/unm-cfn-shared-td"
assert_contains "a second CloudFormation service on one task definition is listed" "$unm_rec" '{"tool":"cloudformation","type":"AWS::ECS::Service","evidence":"template.yaml"}'
unm_fixture pulumi-shared-td Pulumi.yaml $'name: p\nruntime: yaml\nresources:\n  td:\n    type: aws:ecs:TaskDefinition\n    properties:\n      containerDefinitions:\n        - name: api\n          image: acme/api:1\n  one:\n    type: aws:ecs:Service\n    properties:\n      taskDefinition: ${td.arn}\n  two:\n    type: aws:ecs:Service\n    properties:\n      taskDefinition: ${td.arn}'
unm_check "$TEST_TMPDIR/unm-pulumi-shared-td"
assert_contains "a second Pulumi service on one task definition is listed" "$unm_rec" '{"tool":"pulumi-yaml","type":"aws:ecs:Service","evidence":"Pulumi.yaml"}'

# .tf.json blocks written as arrays of objects read like the object form.
unm_fixture tfjson-array main.tf.json '{"resource":[{"aws_s3_bucket":{"b":{}}}]}'
unm_check "$TEST_TMPDIR/unm-tfjson-array"
assert_contains "an array-form .tf.json bucket is refused as unmapped" "$unm_rec" '"reason": "no-mapped-container"'
assert_contains "an array-form .tf.json bucket is listed under its type" "$unm_rec" '{"tool":"terraform","type":"aws_s3_bucket","evidence":"main.tf.json"}'
unm_fixture tfjson-type-array main.tf.json '{"resource":{"aws_s3_bucket":[{"b":{"bucket":"b"}}]}}'
unm_check "$TEST_TMPDIR/unm-tfjson-type-array"
assert_contains "a type-level array lists the type without an index" "$unm_rec" '{"tool":"terraform","type":"aws_s3_bucket","evidence":"main.tf.json"}'
unm_fixture tfjson-array-td main.tf.json '{"resource":[{"aws_ecs_task_definition":{"api":[{"family":"api","container_definitions":"[{\"name\":\"api\",\"image\":\"acme/api:1\"}]"}]}}]}'
unm_check "$TEST_TMPDIR/unm-tfjson-array-td"
assert_contains "an array-form .tf.json task definition is placed" "$unm_rec" '"container":"api","env":"default","tool":"terraform","node":"default","compute":"","image":"acme/api:1"'
unm_fixture tfjson-array-module main.tf.json '{"module":[{"net":{"source":"https://example.com/net"}}]}'
unm_check "$TEST_TMPDIR/unm-tfjson-array-module"
assert_contains "an array-form remote module refuses by name" "$unm_rec" '"reason": "terraform-module-unread:main.tf.json:module.net"'

if [[ "$FAILED" -eq 0 ]]; then
  printf 'all collect-deployment tests passed\n'
  exit 0
fi
printf '%d collect-deployment test(s) failed\n' "$FAILED" >&2
exit 1
