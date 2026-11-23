#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git src tests

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/orders src/api src/db tests

n=0
touch_files() {
  local f
  for f in "$@"; do
    n=$((n + 1))
    printf 'export const v%s = %s;\n' "$n" "$n" >>"$f"
  done
}

for i in 1 2 3 4 5 6; do
  touch_files src/orders/OrderForm.tsx src/api/orders.ts src/db/orderRepo.ts tests/orders.test.ts
  git add .
  git commit -q -m "feat(orders): order change ${i}"
done

for f in src/orders/OrderList.tsx src/orders/OrderBadge.tsx src/orders/OrderIcon.tsx \
  src/api/users.ts src/api/health.ts src/api/auth.ts \
  src/db/userRepo.ts src/db/pool.ts src/db/migrate.ts \
  tests/users.test.ts tests/health.test.ts tests/auth.test.ts; do
  touch_files "$f"
  git add .
  git commit -q -m "chore: touch ${f##*/}"
done
