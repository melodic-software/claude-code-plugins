#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p src/orders services/storefront services/backoffice
for name in list show cancel refund exportOrder archive restore notify invoice report audit; do
  printf 'export const %s = (order: { status: string }) => order.status === "archived" ? null : order;\n' "$name" >"src/orders/$name.ts"
done
cat >services/storefront/update-order.sql <<'EOF'
UPDATE orders SET status = :status, updated_at = now() WHERE id = :id;
EOF
cat >services/backoffice/update-order.sql <<'EOF'
UPDATE orders SET status = :status, note = :note WHERE id = :id;
EOF
printf 'DATABASE_URL=postgres://db.internal/shop\n' >services/storefront/.env.example
printf 'DATABASE_URL=postgres://db.internal/shop\n' >services/backoffice/.env.example
git add . && git commit -q -m "feat: add order handlers and the two web services"
