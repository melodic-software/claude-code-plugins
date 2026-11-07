#!/usr/bin/env bash
# A Python monorepo with a new shared pricing library (discount rules with branching) used by two
# services, a contracts-only library, and a docs/testing.md that sets where single-project and
# cross-project integration tests live.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main libs services docs
mkdir -p libs/pricing/pricing libs/contracts/contracts services/checkout services/invoicing docs
cat >docs/testing.md <<'EOF'
# Testing

- Integration tests that exercise one project sit in that project's `tests/integration/` folder.
- Integration tests that span more than one project live at the repository root, under
  `tests/integration/<area>/`.
- A library that only declares contracts (protocols, dataclasses with no logic) gets no test folder
  of its own; its consumers' tests cover it.
EOF
cat >libs/pricing/pricing/discounts.py <<'EOF'
from decimal import Decimal


def discounted_total(subtotal: Decimal, customer_tier: str, coupon: str | None) -> Decimal:
    rate = {"gold": Decimal("0.10"), "silver": Decimal("0.05")}.get(customer_tier, Decimal("0"))
    if coupon == "SPRING":
        rate += Decimal("0.05")
    if subtotal < Decimal("20"):
        rate = min(rate, Decimal("0.05"))
    return (subtotal * (1 - rate)).quantize(Decimal("0.01"))
EOF
cat >libs/contracts/contracts/order.py <<'EOF'
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class OrderLine:
    sku: str
    quantity: int
    unit_price: Decimal
EOF
cat >services/checkout/checkout.py <<'EOF'
from pricing.discounts import discounted_total
EOF
cat >services/invoicing/invoice.py <<'EOF'
from pricing.discounts import discounted_total
EOF
g add -A
g commit -q -m "shared pricing library"
