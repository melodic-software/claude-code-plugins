#!/usr/bin/env bash
# A billing package whose one invoicing module is to be split: the work changes module structure, so
# the design round should reach for the architecture plugin's vocabulary and scan, or say it is absent.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p billing .work/split-invoicing

cat >billing/__init__.py <<'PY'
PY

cat >billing/invoicing.py <<'PY'
"""Invoices: totals, tax, PDF rendering and email, all in one module."""
import smtplib
from datetime import datetime

TAX_RATES = {"DE": 0.19, "FR": 0.20, "US-CA": 0.0725}


def tax_for(region, amount):
    return round(amount * TAX_RATES[region], 2)


def invoice_total(lines, region):
    net = sum(line["qty"] * line["unit_price"] for line in lines)
    return net + tax_for(region, net)


def render_pdf(invoice):
    return f"INVOICE {invoice['id']} {datetime.now():%Y-%m-%d}".encode()


def send_invoice(invoice, to):
    with smtplib.SMTP("localhost") as smtp:
        smtp.sendmail("billing@example.invalid", to, render_pdf(invoice))
PY

cat >billing/checkout.py <<'PY'
from billing.invoicing import TAX_RATES, invoice_total


def quote(lines, region):
    return {"total": invoice_total(lines, region), "rate": TAX_RATES[region]}
PY

cat >.work/split-invoicing/PLAN.md <<'MD'
# Split the invoicing module

## Brief

### Goal
`billing/invoicing.py` mixes tax calculation, totals, PDF rendering and email. Split it so tax
rules can change without touching rendering or email, and so tax can be tested without SMTP.

### Constraints
- `billing/checkout.py` reads `TAX_RATES` directly today; after the split it goes through the tax
  module's interface.
- Behavior stays the same; no new features.

### Acceptance criteria
- Tax calculation lives in its own module with one public entry point.
- No module outside the tax module reads the rate table.
- Rendering and email do not import the tax module's internals.

### Captured assumptions
- Quality bar: production
- Variation intent: second variant = none known; existing structure: one module; upstream: none
MD

git add .
git commit -q -m "feat: invoicing"
