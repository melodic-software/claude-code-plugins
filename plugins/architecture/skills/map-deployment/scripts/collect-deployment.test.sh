#!/usr/bin/env bash
# Tests for collect-deployment.sh and render-deployment.sh.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export AWS_SECRET_ACCESS_KEY="SuperSecretFromEnv"
export LEAK="SuperSecretFromEnv"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-deployment.sh"
RENDER="$SCRIPT_DIR/render-deployment.sh"
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
assert_contains "image differs" "$rec" "ghcr.io/acme/api:1.4.0 -> ghcr.io/acme/api:1.0.0"
assert_contains "replicas differ" "$rec" '"change":"replicas"'
assert_contains "cron added" "$rec" "present only in prod"
sum="$(bash "$RENDER" --record "$TEST_TMPDIR/dep.json" --out "$TEST_TMPDIR/dep-out" --dialect mermaid --diff staging prod)"
assert_equals "render exits 0" "$?" "0"
md="$(cat "$TEST_TMPDIR/dep-out/deployment.md")"
assert_contains "c4 deployment" "$md" "C4Deployment"
assert_contains "names compose" "$md" "compose"
assert_contains "diff table has the image" "$md" "1.4.0 ->"
assert_not_contains "diagram has no secret" "$md" "SuperSecret"
assert_contains "catalog absent note" "$md" "map-containers output was not present"
assert_contains "summary" "$sum" "status=drawn"

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
bash "$RENDER" --record "$TEST_TMPDIR/both.json" --out "$TEST_TMPDIR/both-out" >/dev/null
bothmd="$(cat "$TEST_TMPDIR/both-out/deployment.md")"
assert_not_contains "partial read draws nothing" "$bothmd" "C4Deployment"
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
  template:
    spec:
      containers:
        - name: api
          image: ghcr.io/acme/api:2
          env:
            - name: PASSWORD
              value: SuperSecret123
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
  namespace: prod
spec:
  rules:
    - host: api.example.com
EOF
commit_all "$repo4"
bash "$COLLECT" --repo "$repo4" --out "$TEST_TMPDIR/k8s.json" --generated-on 2026-09-28
k8s="$(cat "$TEST_TMPDIR/k8s.json")"
assert_contains "k8s drawn" "$k8s" '"status": "drawn"'
assert_contains "k8s tool" "$k8s" '"name":"kubernetes"'
assert_contains "compose still read" "$k8s" '"name":"compose"'
assert_contains "ingress host" "$k8s" "api.example.com"
assert_not_contains "k8s secret dropped" "$k8s" "SuperSecret123"
bash "$RENDER" --record "$TEST_TMPDIR/k8s.json" --out "$TEST_TMPDIR/k8s-dsl" --dialect structurizr >/dev/null
dsl="$(cat "$TEST_TMPDIR/k8s-dsl/deployment.dsl")"
assert_contains "structurizr environment" "$dsl" "deploymentEnvironment"
assert_contains "container instance" "$dsl" "containerInstance"

# flat record
printf '%s\n' '{"schema_version":1}' >"$TEST_TMPDIR/flat.json"
set +e
bash "$RENDER" --record "$TEST_TMPDIR/flat.json" --out "$TEST_TMPDIR/flat-out" >/dev/null 2>"$TEST_TMPDIR/flat-err"
frc=$?
set +e
assert_equals "flat record exits 1" "$frc" "1"
assert_not_contains "flat writes nothing" "$(ls "$TEST_TMPDIR/flat-out" 2>/dev/null || true)" "deployment.md"

if [[ "$FAILED" -eq 0 ]]; then
  printf 'all collect-deployment tests passed\n'
  exit 0
fi
printf '%d collect-deployment test(s) failed\n' "$FAILED" >&2
exit 1
