#!/usr/bin/env bash
# Seeds a webhook sender with no retry and a failure log showing 503s during customer deploys.
set -euo pipefail

mkdir -p src/webhooks logs
cat >src/webhooks/sender.py <<'PY'
import requests


def send(endpoint_url, payload):
    response = requests.post(endpoint_url, json=payload, timeout=10)
    response.raise_for_status()
    return response.status_code
PY
cat >logs/webhook-failures.log <<'LOG'
# week summary: 214 dropped deliveries, 9 customers, status 503
14:02:11 drop customer=acme-test endpoint=https://hooks.example.com/a status=503
14:02:12 drop customer=acme-test endpoint=https://hooks.example.com/a status=503
16:40:03 drop customer=demo-co endpoint=https://hooks.example.org/b status=503
LOG
