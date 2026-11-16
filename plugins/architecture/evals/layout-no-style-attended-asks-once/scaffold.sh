#!/usr/bin/env bash
# No recorded style: no ADR, no architecture topic doc, no boundary rule. OrderForm.tsx, orders.ts,
# orderRepo.ts and orders.test.ts change together in six commits; each of their folders also holds
# files that change alone, so the co-change script finds one four-folder cluster.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git src
# shellcheck source=../fixtures/git-history.sh
. "${here}/../fixtures/git-history.sh"

repo_init
for i in 1 2 3 4 5 6; do
  commit_files "feat(orders): order change ${i}" \
    src/orders/OrderForm.tsx src/api/orders.ts src/db/orderRepo.ts src/tests/orders.test.ts
done
for f in src/orders/OrderList.tsx src/orders/OrderBadge.tsx src/api/users.ts src/api/health.ts \
  src/db/userRepo.ts src/db/pool.ts src/tests/users.test.ts src/tests/health.test.ts; do
  commit_files "chore: touch ${f##*/}" "${f}"
done
