#!/usr/bin/env bash
# Seeds a webhook sender with no retry and no failure log, so any problem behind the request is inferred.
set -euo pipefail

mkdir -p src/webhooks
cat >src/webhooks/sender.py <<'PY'
import requests


def send(endpoint_url, payload):
    response = requests.post(endpoint_url, json=payload, timeout=10)
    response.raise_for_status()
    return response.status_code
PY
