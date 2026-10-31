#!/usr/bin/env bash
# Commits src/order-schema.ts on main, adds an uncommitted src/orders.ts with a needless alias, a debug log and a swallowing catch, and writes the lines file naming all 13 of its lines.
set -euo pipefail

git init -q
git symbolic-ref HEAD refs/heads/main
mkdir -p src
cat >src/order-schema.ts <<'EOF'
export type Order = { id: string; total: number };

export function parseOrder(raw: { id: string; total: number }): Order {
  return { id: raw.id, total: raw.total };
}
EOF
git add src/order-schema.ts
git -c user.name=dev -c user.email=dev@example.invalid -c commit.gpgsign=false commit -q -m "add order schema"
cat >src/orders.ts <<'EOF'
import { parseOrder, type Order } from "./order-schema";

export async function loadOrders(url: string): Promise<Order[]> {
  try {
    const response = await fetch(url);
    const payload = await response.json();
    const body = payload;
    console.log("here");
    return [parseOrder(body)];
  } catch {
    return [];
  }
}
EOF
printf '1\t13\tsrc/orders.ts\n' >changed-lines.tsv
