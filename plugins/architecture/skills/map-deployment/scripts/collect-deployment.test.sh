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
  assert_contains "hostile record $d draws the relationship" "$hmd" "$([[ $d == c4-plantuml ]] && echo 'Rel(n2_svc, c1_api, "routes' || echo '.n2_svc -> env1_a.cn1_')"
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

# terraform plus compose is a partial read
repo2="$TEST_TMPDIR/both"
init_repo "$repo2"
mkdir -p "$repo2/deploy"
printf 'services:\n  api:\n    image: ghcr.io/acme/api:1\n' >"$repo2/deploy/compose.yaml"
printf 'resource "azurerm_linux_web_app" "api" {\n  name = "api"\n}\n' >"$repo2/main.tf"
commit_all "$repo2"
bash "$COLLECT" --repo "$repo2" --out "$TEST_TMPDIR/both.json" --generated-on 2026-09-28
both="$(cat "$TEST_TMPDIR/both.json")"
assert_contains "partial read" "$both" '"reason": "partial-read"'
assert_contains "names terraform" "$both" '"name":"terraform"'
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
assert_contains "adapter not shipped" "$tf" '"reason": "adapter-not-shipped"'
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

# Layered Compose is refused, never read as environments.
for layered in "compose.yaml compose.override.yaml" "docker-compose.yml docker-compose.prod.yml" "compose.yaml compose.prod.yaml" "compose.override.yaml"; do
  repoL="$TEST_TMPDIR/layered"
  rm -rf "$repoL"
  init_repo "$repoL"
  for f in $layered; do
    printf 'services:\n  api:\n    image: ghcr.io/acme/api:1\n' >"$repoL/$f"
  done
  commit_all "$repoL"
  bash "$COLLECT" --repo "$repoL" --out "$TEST_TMPDIR/layered.json" --generated-on 2026-09-28
  layerrec="$(cat "$TEST_TMPDIR/layered.json")"
  assert_contains "layered compose [$layered] is refused" "$layerrec" '"reason": "layered-compose"'
  assert_not_contains "layered compose [$layered] draws no environment" "$layerrec" '"environment":"'
done
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
check_declines "an ARM template" arm infra/main.json "{\"\$schema\": \"$arm_schema\", \"resources\": []}"
check_declines "a tfvars file" terraform infra/prod.tfvars 'region = "westeurope"'
check_declines "a tf.json file" terraform infra/main.tf.json '{"resource": {}}'
check_declines "a module-only main.tf" terraform main.tf 'module "net" { source = "./net" }'
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
assert_contains "diff section names the compared kinds" "$nsmd" "Kinds compared: container added or removed, image, replicas, ports, parameter added or removed"
assert_contains "diff section says nodes are not compared" "$nsmd" "Networks and Ingress hosts are not compared."
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

if [[ "$FAILED" -eq 0 ]]; then
  printf 'all collect-deployment tests passed\n'
  exit 0
fi
printf '%d collect-deployment test(s) failed\n' "$FAILED" >&2
exit 1
