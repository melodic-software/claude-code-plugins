#!/usr/bin/env bash
# A draft plan whose Brief has two acceptance criteria about a 404 response and an Out-of-scope
# list naming only pagination. Phase 1 covers both criteria; Phase 2 adds a response cache that
# serves neither and is not listed as Out-of-scope. The plan review should flag Phase 2.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p app tests .work/orders-404

cat >app/__init__.py <<'PY'
PY

cat >app/orders.py <<'PY'
ORDERS = {"a1": {"id": "a1", "total_cents": 1200}}


def get_order(order_id):
    return 200, ORDERS[order_id]
PY

cat >tests/test_orders.py <<'PY'
from app.orders import get_order


def test_known_order():
    status, body = get_order("a1")
    assert status == 200
    assert body["id"] == "a1"
PY

cat >.work/orders-404/PLAN.md <<'MD'
# Orders 404

## Brief

### Goal
`GET /orders/{id}` answers an unknown id with a clear 404 instead of a server error.

### Acceptance criteria
1. `GET /orders/{id}` returns 404 for an unknown id.
2. The 404 body names the id that was not found.

### Out-of-scope
- Pagination of order lists.

### Captured assumptions
- Quality bar: production

## Plan

### Phase 1: 404 handler and tests
- `app/orders.py`: return `404, {"error": "order not found", "id": order_id}` when the id is unknown.
- `tests/test_orders.py`: add a test for an unknown id that checks the status and that the body names the id.
- **Sanity Check:** `pytest tests/test_orders.py` exits 0.

### Phase 2: Response caching for order lookups
- `app/cache.py`: add an in-memory LRU cache with a 60-second TTL.
- `app/orders.py`: read through the cache in `get_order`.
- `tests/test_cache.py`: test hits, misses and expiry.
- **Sanity Check:** `pytest tests/test_cache.py` exits 0.

### Files affected
| File | Action |
|---|---|
| app/orders.py | modify: 404 branch, cache read-through |
| app/cache.py | create |
| tests/test_orders.py | modify: unknown-id test |
| tests/test_cache.py | create |

### Test strategy
Unit tests drive `get_order`, the existing public function, for a known and an unknown id; `tests/test_cache.py` drives the cache.
MD

git add .
git commit -q -m "feat: order lookup"
