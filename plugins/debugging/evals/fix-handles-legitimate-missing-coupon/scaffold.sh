#!/usr/bin/env bash
# A Python repo whose checkout crashes when the optional coupon field is left blank. The notes
# confirm the cause: discount_rate upper-cases a coupon code that is None for most orders.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

cat > form.py <<'PY'
# Checkout form fields. The coupon code is optional: most customers leave it blank.
FIELDS = {
    "email": {"required": True},
    "coupon_code": {"required": False},
}


def parse(raw):
    return {"email": raw["email"], "coupon_code": raw.get("coupon_code") or None}
PY

cat > discounts.py <<'PY'
COUPONS = {"SAVE10": 0.10, "SAVE25": 0.25}


def discount_rate(code):
    return COUPONS.get(code.upper(), 0.0)
PY

cat > checkout.py <<'PY'
from discounts import discount_rate


def order_total(subtotal, coupon_code=None):
    return round(subtotal * (1 - discount_rate(coupon_code)), 2)
PY

cat > repro_checkout.py <<'PY'
# Phase 1 loop: exits 1 while the checkout bug reproduces, 0 once it is gone.
import sys

from checkout import order_total
from form import parse

try:
    with_coupon = order_total(100.0, parse({"email": "a@x", "coupon_code": "save10"})["coupon_code"])
    without = order_total(100.0, parse({"email": "b@x"})["coupon_code"])
except Exception as exc:
    print("BUG: %r" % exc)
    sys.exit(1)
print("with=%s without=%s" % (with_coupon, without))
sys.exit(0 if (with_coupon, without) == (90.0, 100.0) else 1)
PY

cat > NOTES.md <<'MD'
# Checkout crash session

- Phase 1 loop: `python repro_checkout.py` exits 1 with
  `AttributeError: 'NoneType' object has no attribute 'upper'`.
- Phase 3 row 1: `discount_rate` receives no coupon code. Refuted if the code at the call is a
  string.
- Phase 4: printed the code at `discount_rate`: `None` for every order where the customer left the
  coupon field blank. Row 1 confirmed. The field is optional in `form.py`.
MD

git add .
git commit -q -m "feat: checkout with coupons"
