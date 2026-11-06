#!/usr/bin/env bash
# Seeds the workspace root as an orders service whose OrderService.cs has a nested pricing loop,
# committed on main, so the conversation's target exists.
set -euo pipefail

mkdir -p src/orders
cat > src/orders/OrderService.cs <<'EOF'
namespace Shop.Orders;

public sealed class OrderService
{
    public decimal PriceOrder(Order order, IReadOnlyList<Discount> discounts)
    {
        decimal total = 0;
        for (int i = 0; i < order.Lines.Count; i++)
        {
            var l = order.Lines[i];
            decimal p = l.UnitPrice * l.Quantity;
            for (int j = 0; j < discounts.Count; j++)
            {
                if (discounts[j].Sku == l.Sku && discounts[j].MinQuantity <= l.Quantity)
                {
                    if (discounts[j].IsPercent) { p = p - p * discounts[j].Amount / 100; }
                    else { p = p - discounts[j].Amount; }
                }
            }
            if (p < 0) { p = 0; }
            total = total + p;
        }
        return total;
    }
}
EOF

git init -q -b main
git add -A
git -c user.name=Orders -c user.email=orders@example.invalid -c commit.gpgsign=false \
  commit -q -m "Add order pricing"
