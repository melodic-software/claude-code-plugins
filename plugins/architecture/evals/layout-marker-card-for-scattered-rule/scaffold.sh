#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git src lib ARCHITECTURE.md
# shellcheck source=../fixtures/git-history.sh
. "${here}/../fixtures/git-history.sh"

repo_init
{
  printf '# Architecture\n\n'
  for i in $(seq 3 21); do printf 'Line %s of the overview.\n' "${i}"; done
  printf 'The files src/billing/invoice.ts, src/reports/ledger-view.ts and lib/tax.ts hold the tax rules and must change only through a reviewed tax change.\n'
} >ARCHITECTURE.md
commit_files "feat(tax): tax rules" src/billing/invoice.ts src/reports/ledger-view.ts lib/tax.ts
for i in 1 2 3 4 5 6; do
  commit_files "feat(orders): order change ${i}" \
    src/orders/OrderForm.tsx src/api/orders.ts src/db/orderRepo.ts src/tests/orders.test.ts
done
for f in src/orders/OrderList.tsx src/api/users.ts src/db/userRepo.ts src/tests/users.test.ts; do
  commit_files "chore: touch ${f##*/}" "${f}"
done
