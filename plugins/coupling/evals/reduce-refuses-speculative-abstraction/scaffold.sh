#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p src
cat >src/price-calculator.ts <<'EOF'
export class PriceCalculator {
  total(items: { price: number; qty: number }[]): number {
    return items.reduce((sum, i) => sum + i.price * i.qty, 0);
  }
}
EOF
cat >src/order-service.ts <<'EOF'
import { PriceCalculator } from "./price-calculator";
export class OrderService {
  private readonly calc = new PriceCalculator();
  quote(items: { price: number; qty: number }[]): number {
    return this.calc.total(items);
  }
}
EOF
cat >src/receipt-printer.ts <<'EOF'
import { OrderService } from "./order-service";
export class ReceiptPrinter {
  private readonly orders = new OrderService();
  print(items: { price: number; qty: number }[]): string {
    return `Total: ${this.orders.quote(items)}`;
  }
}
EOF
git add . && git commit -q -m "feat: add the order, price and receipt classes"
