#!/usr/bin/env bash
# A storefront repository whose committed landscape record still lists an edge to
# acme-labs/legacy-reports. The commit after the record removed every reference to it
# and added one to acme-labs/pricing-engine, so the record has drifted.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git remote add origin https://github.com/acme-labs/storefront.git
mkdir -p .github/workflows docs/architecture

cat >.github/workflows/ci.yml <<'YAML'
name: ci
on: [push]
jobs:
  build:
    uses: acme-labs/shared-workflows/.github/workflows/dotnet-build.yml@v1
YAML

cat >README.md <<'MD'
# Storefront

Orders flow to https://github.com/acme-labs/billing-service and nightly totals go to
https://github.com/acme-labs/legacy-reports.
MD

git add -A
git commit -q -m "Storefront with its first neighbors"

cat >docs/architecture/landscape.json <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-10-01",
  "discovery_source": "default (current repository plus reference graph)",
  "remote": "not used",
  "subject_owner": "acme-labs",
  "repositories": [
    {"name":"storefront","remote":"https://github.com/acme-labs/storefront.git","owner":"acme-labs","runtime":"unknown","tooling":"unknown","target_framework":"unknown","dependencies":[],"dev_dependencies":[],"last_touched":"2026-10-01T09:00:00+00:00","evidence":{"owner":"origin remote URL","runtime":"no runtime-scope manifest under depth 3","tooling":"no development-scope manifest under depth 3","target_framework":"no framework declaration for runtime unknown","dependencies":"no runtime-scope dependency manifest","dev_dependencies":"no development-scope dependency manifest","last_touched":"git log -1 --format=%cI (local HEAD)"}}
  ],
  "edges": [
    {"from":"storefront","to":"acme-labs/billing-service","type":"cites","relation":"internal","count":1,"files":["README.md"]},
    {"from":"storefront","to":"acme-labs/legacy-reports","type":"cites","relation":"internal","count":1,"files":["README.md"]},
    {"from":"storefront","to":"acme-labs/shared-workflows","type":"cites","relation":"internal","count":1,"files":[".github/workflows/ci.yml"]},
    {"from":"storefront","to":"acme-labs/shared-workflows","type":"uses-workflow","relation":"internal","count":1,"files":[".github/workflows/ci.yml"]}
  ]
}
JSON

git add -A
git commit -q -m "Commit the landscape record"

cat >README.md <<'MD'
# Storefront

Orders flow to https://github.com/acme-labs/billing-service and prices come from
https://github.com/acme-labs/pricing-engine.
MD

git add -A
git commit -q -m "Retire legacy-reports, read prices from pricing-engine"
