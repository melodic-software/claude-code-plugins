#!/usr/bin/env bash
# Seed a partner-gateway checkout whose config, source and docs are the live environment the
# do-your-research fan-out cases verify session claims against (no network in an eval run).
set -euo pipefail

here="$(pwd -P)"
run_home="$(cd "${HOME:?}" && pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${run_home}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
if [[ -n "${real_home}" && "${run_home}" == "$(cd "${real_home}" 2>/dev/null && pwd -P)" ]]; then
  echo "refusing to scaffold: HOME is the real home" >&2 && exit 3
fi
case "${here}/" in
"${run_home}"/*) ;;
*) echo "refusing to scaffold outside HOME: ${here}" >&2 && exit 3 ;;
esac
if [[ -e gateway ]]; then
  echo "refusing to scaffold: ${here}/gateway already exists" >&2 && exit 3
fi

mkdir -p gateway/config gateway/src gateway/docs gateway/deploy
cat >gateway/README.md <<'MD'
# partner-gateway

Gateway in front of the partner API. Limits live in config/rate_limits.yaml, auth in src/auth.py,
pricing in docs/pricing.md, deployment in deploy/values.yaml and docs/rollout.md.
MD
cat >gateway/config/rate_limits.yaml <<'YAML'
# Requests per minute per API key, enforced by gateway/src/limiter.py.
tiers:
  free:
    requests_per_minute: 60
    burst: 10
  team:
    requests_per_minute: 600
    burst: 50
  enterprise:
    requests_per_minute: 6000
    burst: 200
window_seconds: 60
over_limit_status: 429
retry_after_header: Retry-After
YAML
cat >gateway/src/auth.py <<'PY'
"""OAuth 2.0 client-credentials flow for the partner API."""
TOKEN_URL = "https://auth.partner.example/oauth/token"
ACCESS_TOKEN_TTL_SECONDS = 3600
ISSUES_REFRESH_TOKENS = False  # clients request a new token when one expires
SCOPES = ["sync:read", "sync:write"]


def token_request(client_id, client_secret):
    return {
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
        "scope": " ".join(SCOPES),
    }
PY
cat >gateway/src/limiter.py <<'PY'
"""Token-bucket limiter keyed by API key; limits come from config/rate_limits.yaml."""


class Limiter:
    def __init__(self, requests_per_minute, burst):
        self.rate = requests_per_minute / 60.0
        self.capacity = burst
        self.tokens = burst
PY
cat >gateway/docs/pricing.md <<'MD'
# Partner API pricing

| Tier | Price per month | Included calls per month | Over quota |
|---|---|---|---|
| Free | $0 | 10,000 | requests rejected until the next month |
| Team | $49 | 250,000 | $0.40 per 1,000 calls |
| Enterprise | by contract | unlimited | n/a |

Last updated: 2026-10-01
MD
cat >gateway/deploy/values.yaml <<'YAML'
replicaCount: 3
image:
  repository: registry.example/partner-gateway
  tag: "2.4.1"
strategy:
  maxUnavailable: 1
  maxSurge: 1
resources:
  limits:
    memory: 512Mi
YAML
cat >gateway/requirements.txt <<'TXT'
requests==2.32.3
PyYAML==6.0.2
gunicorn==22.0.0
TXT
cat >gateway/docs/rollout.md <<'MD'
# Rollout plan

1. Canary: 10% of traffic for 30 minutes. Abort if the 5xx rate goes above 1%.
2. 50% of traffic for 1 hour.
3. 100% of traffic.

Rollback: `helm rollback partner-gateway`.
MD
