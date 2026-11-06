#!/usr/bin/env bash
# Seeds the eval workspace with the disconnected-admin-export fixture, plus an
# approved greenfield export plan that claims nothing exports orders today, so the
# disconnected export is less visible than the plan.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/disconnected-admin-export"
dst=evals/fixtures/disconnected-admin-export
for f in README.md config/flags.json db/schema.sql src/admin/routes.js src/db.js src/flags.js \
  src/reports/csv-exporter.js; do
  mkdir -p "$dst/$(dirname "$f")"
  cp "$src/$f" "$dst/$f"
done

mkdir -p evals/fixtures/disconnected-admin-export/docs
cat > evals/fixtures/disconnected-admin-export/docs/bulk-export-plan.md <<'EOF'
# Plan: admin bulk export

Status: approved, starts next sprint.

Admins cannot export orders today; support pulls CSVs by hand from a read replica. We will build
a new export service:

1. Add `src/export/` with a streaming CSV writer.
2. Add `POST /admin/export/orders` behind admin auth.
3. Add an `order_exports` table recording who exported what and how many rows.
4. Ship it behind a new `ordersExportV2` flag.

Estimate: two sprints.
EOF
