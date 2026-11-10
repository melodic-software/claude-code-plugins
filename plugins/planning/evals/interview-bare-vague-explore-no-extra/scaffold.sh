#!/usr/bin/env bash
# Seeds a small client with a retry helper for an exploratory question.
set -euo pipefail

mkdir -p src/client
cat >src/client/retry.py <<'PY'
import time


def with_retry(call, attempts=3, delay=0.5):
    for attempt in range(attempts):
        try:
            return call()
        except ConnectionError:
            if attempt == attempts - 1:
                raise
            time.sleep(delay)
            delay *= 2
PY
cat >src/client/api.py <<'PY'
import requests

from .retry import with_retry


def fetch_status(url):
    return with_retry(lambda: requests.get(url, timeout=5).json())
PY
