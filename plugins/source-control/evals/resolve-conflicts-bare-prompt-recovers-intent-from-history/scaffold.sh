#!/usr/bin/env bash
# git merge main stopped on api/client.py. main removed legacy_token on purpose (the endpoint
# rejects it); feature added a region filter in the same function. Only the commit message says why.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

mkdir -p api
: > api/__init__.py
cat > api/client.py <<'PY'
def fetch_orders(session, customer_id, legacy_token=None):
    params = {"customer": customer_id}
    if legacy_token:
        params["token"] = legacy_token
    return session.get("/orders", params=params)
PY
cat > test_client.py <<'PY'
import unittest

from api.client import fetch_orders


class FakeSession:
    def get(self, path, params):
        return path, params


class ClientTest(unittest.TestCase):
    def test_sends_customer(self):
        self.assertEqual(fetch_orders(FakeSession(), 7)[1]["customer"], 7)


if __name__ == "__main__":
    unittest.main()
PY
git add .
git commit -q -m "feat(api): orders client"

git checkout -q -b feature
cat > api/client.py <<'PY'
def fetch_orders(session, customer_id, legacy_token=None, region=None):
    params = {"customer": customer_id}
    if region:
        params["region"] = region
    if legacy_token:
        params["token"] = legacy_token
    return session.get("/orders", params=params)
PY
git add api/client.py
git commit -q -m "feat(api): filter orders by region" -m "The EU dashboard shows only its own region's orders. Refs ORD-5."

git checkout -q main
cat > api/client.py <<'PY'
def fetch_orders(session, customer_id):
    params = {"customer": customer_id}
    return session.get("/orders", params=params)
PY
git add api/client.py
git commit -q -m "refactor(api): drop legacy_token from fetch_orders" -m "The /orders endpoint stopped accepting token query auth on 2026-03-01; sending it now returns 400. Refs SEC-12."

git checkout -q feature
git merge main -q -m "Merge branch main into feature" >/dev/null 2>&1 || true
test -f .git/MERGE_HEAD
git diff --name-only --diff-filter=U | grep -qx api/client.py
