#!/usr/bin/env bash
# An invoice export of three one-step classes. Three call sites (jobs, api, cli) repeat the
# load, format, write sequence; the case's scan report says five. There are no tests.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git billing jobs api cli
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p billing jobs api cli
: >billing/__init__.py
: >jobs/__init__.py
: >api/__init__.py
: >cli/__init__.py

cat >billing/loader.py <<'PY'
class InvoiceLoader:
    def __init__(self, store):
        self.store = store

    def load(self, invoice_id):
        return self.store.get(invoice_id)
PY

cat >billing/formatter.py <<'PY'
class InvoiceFormatter:
    def format(self, invoice):
        return "\n".join(f"{line['sku']},{line['amount']}" for line in invoice["lines"])
PY

cat >billing/writer.py <<'PY'
class InvoiceWriter:
    def __init__(self, sink):
        self.sink = sink

    def write(self, invoice_id, text):
        self.sink.put(f"invoices/{invoice_id}.csv", text)
PY

for site in jobs/nightly.py api/routes.py cli/export.py; do
  cat >"$site" <<'PY'
from billing.formatter import InvoiceFormatter
from billing.loader import InvoiceLoader
from billing.writer import InvoiceWriter


def export_invoice(store, sink, invoice_id):
    invoice = InvoiceLoader(store).load(invoice_id)
    text = InvoiceFormatter().format(invoice)
    InvoiceWriter(sink).write(invoice_id, text)
PY
done

git add billing jobs api cli
git commit -q -m "feat: invoice export"
