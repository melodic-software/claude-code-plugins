#!/usr/bin/env bash
# main holds two independently deployed services and a standards index whose service-boundaries file
# says a value two services need is copied into each on purpose. The branch adds the shipping
# service's retry policy, copying MAX_RETRIES from billing. The bundled Duplicated Code default
# would rate that copy CRITICAL; the consumer standard permits it. The base commit SHA is in
# .review-base.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '.review-base\n' >>.git/info/exclude
mkdir -p docs/standards services/billing services/shipping

cat >docs/standards/README.md <<'MD'
---
standards-contract: 1.1.0
---

# Standards index

| Surface | Applies when | File |
|---|---|---|
| service-boundaries | code design, duplication, or reviewing any change under services/ | service-boundaries.md |
MD

cat >docs/standards/service-boundaries.md <<'MD'
# Service boundaries

Each directory under `services/` deploys on its own and never imports code from another service.

A value two services both need is copied into each service on purpose, so each can change it on its
own release. A copy across services is not a review finding. A module shared across services is.
MD

cat >services/billing/retry.js <<'JS'
export const MAX_RETRIES = 3;

export async function withRetry(fn) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt >= MAX_RETRIES) throw err;
    }
  }
}
JS

git add .
git commit -q -m "feat: billing retry policy"
git rev-parse HEAD >.review-base
git checkout -q -b feat/shipping-retry

cat >services/shipping/retry.js <<'JS'
export const MAX_RETRIES = 3;

export async function withRetry(fn) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt >= MAX_RETRIES) throw err;
    }
  }
}
JS

git add services
git commit -q -m "feat: shipping retry policy"
