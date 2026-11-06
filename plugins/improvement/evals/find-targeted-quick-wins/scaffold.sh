#!/usr/bin/env bash
# Seeds the workspace root as the checkout-service source tree, with nothing that measures speed,
# plus a monthly reporting module that has nothing to do with checkout, so a scan that strays
# outside the checkout flow reads src/reporting/.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"

mkdir -p src/reporting
cat > src/reporting/monthly-report.js <<'EOF'
export function monthlyRevenue(orders, month) {
  var total = 0;
  for (var i = 0; i < orders.length; i++) {
    if (orders[i].month == month) {
      total = total + orders[i].totalCents;
    }
  }
  return total;
}
EOF
cat > src/reporting/README.md <<'EOF'
# reporting

Monthly revenue figures for the finance team. Not part of the checkout flow.
EOF
