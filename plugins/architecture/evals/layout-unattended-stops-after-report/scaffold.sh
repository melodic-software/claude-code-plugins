#!/usr/bin/env bash
# docs/adr/0004-folder-per-feature.md line 9 records "Each feature lives in one folder under
# src/features/." CartView.tsx changes with cartTotals.ts, useCart.ts and cart.ts, which live
# outside src/features/cart, in six commits, so the cart cluster contradicts the recorded style.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git src docs
# shellcheck source=../fixtures/git-history.sh
. "${here}/../fixtures/git-history.sh"

repo_init
mkdir -p docs/adr
cat >docs/adr/0004-folder-per-feature.md <<'MD'
# 4. Folder per feature

Status: accepted

## Context

Features were spread over layer folders.

Each feature lives in one folder under src/features/.
MD
for i in 1 2 3 4 5 6; do
  commit_files "feat(cart): cart change ${i}" \
    src/features/cart/CartView.tsx src/shared/cartTotals.ts src/hooks/useCart.ts src/api/cart.ts
done
for f in src/features/cart/CartIcon.tsx src/shared/money.ts src/hooks/useUser.ts src/api/users.ts; do
  commit_files "chore: touch ${f##*/}" "${f}"
done
