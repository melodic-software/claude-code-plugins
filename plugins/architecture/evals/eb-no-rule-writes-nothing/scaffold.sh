#!/usr/bin/env bash
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs src scripts
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh"
mkdir -p src/billing src/reporting src/shared scripts

cat >src/shared/money.js <<'JS'
export function cents(amount) {
  return Math.round(amount * 100);
}
JS

cat >src/billing/invoice.js <<'JS'
import { cents } from "../shared/money.js";

export function invoiceTotal(lines) {
  return lines.reduce((sum, line) => sum + cents(line.amount), 0);
}
JS

cat >src/reporting/summary.js <<'JS'
import { invoiceTotal } from "../billing/invoice.js";

export function monthlySummary(invoices) {
  return invoices.map((lines) => invoiceTotal(lines));
}
JS

cat >scripts/check.sh <<'SH'
#!/usr/bin/env bash
# Runs every check this repository has.
set -euo pipefail
echo "no checks yet"
SH

git add -A
git commit -q -m "Billing, reporting and shared modules"
