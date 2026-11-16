#!/usr/bin/env bash
# A small JavaScript repository whose own import check (scripts/check-imports.sh, rules in
# scripts/import-rules.txt) runs under scripts/check.sh. The architecture topic doc records two
# boundary rules: shared must not import billing (already in the check, with Enforced by) and
# billing must not import reporting (in no check yet). Needs no install: the check is bash and grep.
# The caller runs the repository guard first and commits afterwards.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/convention-home.sh"

cat >>docs/conventions/architecture/README.md <<'MD'

## Boundary rules

- shared must not import billing. Evidence: src/shared/money.js:1. Accepted 2026-10-02. Enforced by: `bash scripts/check.sh`.
- billing must not import reporting. Evidence: src/billing/invoice.js:1, src/reporting/summary.js:1. Accepted 2026-10-30.
MD

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

cat >scripts/import-rules.txt <<'TXT'
# One rule per line: <rule-id> <from-dir> <forbidden-dir>
# A file under <from-dir> may not import a path that names <forbidden-dir>'s folder.
shared-no-billing src/shared src/billing
TXT

cat >scripts/check-imports.sh <<'SH'
#!/usr/bin/env bash
# Fails when a file imports across a rule in scripts/import-rules.txt.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
status=0
while read -r id from forbidden; do
  [[ -z "${id}" || "${id}" == \#* ]] && continue
  seg="$(basename "${forbidden}")"
  while IFS= read -r hit; do
    echo "FAIL ${id}: ${hit}"
    status=1
  done < <(grep -rnE "(from|import|require\() *[\"'][^\"']*/${seg}/" "${root}/${from}" --include='*.js' | sed "s|^${root}/||" || true)
done <"${root}/scripts/import-rules.txt"
[[ "${status}" -eq 0 ]] && echo "imports ok"
exit "${status}"
SH

cat >scripts/check.sh <<'SH'
#!/usr/bin/env bash
# Runs every check this repository has. CI runs this file.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/check-imports.sh"
SH

mkdir -p .github/workflows
cat >.github/workflows/ci.yml <<'YML'
name: ci
on: [push]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/check.sh
YML
