#!/usr/bin/env bash
# Stages an orders package whose docs/testing.md sets the test layout, with one
# older test left at the tests/ root outside that layout.
set -euo pipefail

mkdir -p docs src/orders tests/unit/orders tests/integration/orders
: >src/__init__.py
: >src/orders/__init__.py

cat >docs/testing.md <<'MD'
# Testing

- Unit tests for pure code (no database session, no network) go in
  `tests/unit/<package>/test_<module>.py`.
- Anything that opens a database session goes in
  `tests/integration/<package>/test_<module>.py` and uses the `db` fixture.
- `tests/test_order_status.py` predates this layout; leave it until it is moved.
MD

cat >src/orders/order_mapper.py <<'PY'
def to_dto(order):
    return {
        "id": order.id,
        "status": order.status.lower(),
        "total": f"{order.total_cents / 100:.2f}",
    }
PY

cat >src/orders/order_repo.py <<'PY'
def save(session, order):
    session.add(order)
    session.commit()
PY

cat >src/orders/order_totals.py <<'PY'
def line_total(qty, unit_cents):
    return qty * unit_cents
PY

cat >tests/unit/orders/test_order_totals.py <<'PY'
from src.orders.order_totals import line_total


def test_line_total_multiplies_quantity_by_unit_price():
    assert line_total(3, 250) == 750
PY

cat >tests/integration/orders/test_order_repo.py <<'PY'
def test_save_persists(db):
    from src.orders.order_repo import save
    order = db.new_order(total_cents=500)
    save(db.session, order)
    assert db.session.get(type(order), order.id).total_cents == 500
PY

cat >tests/test_order_status.py <<'PY'
def test_status_is_lowercase():
    assert "PAID".lower() == "paid"
PY

git init -q -b main
git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add orders package"
printf '/.*\n' >>.git/info/exclude
