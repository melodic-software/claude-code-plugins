#!/usr/bin/env bash
# Stages a two-version shop app (tags v1 and v2) and the findings.json of a map
# pass on each. Planted across the passes: checkout breaks in v2 (NEW), the cart
# total stays wrong and shows at a second entry point (PRE-EXISTING), search is
# fixed (GONE), and orders was blocked in the second pass (not checked, never
# GONE).
set -euo pipefail

git_c() { git -c user.name=dev -c user.email=dev@example.invalid "$@"; }

mkdir -p src
cat >src/cart.js <<'JS'
export const total = (items) => items.reduce((sum, item) => sum + item.price, 0);
JS
cat >src/search.js <<'JS'
export const render = (hits) => hits.map((hit) => hit.title.slice(0, 7)).join("\u0000");
JS
cat >src/checkout.js <<'JS'
export const pay = (cart) => ({ status: "paid", amount: cart.total });
JS
printf '{ "name": "shop", "version": "1.0.0" }\n' >package.json
git init -q -b main
git_c add -A
git_c commit -q -m "shop 1.0.0"
git tag v1

cat >src/search.js <<'JS'
export const render = (hits) => hits.map((hit) => hit.title).join("\n");
JS
cat >src/checkout.js <<'JS'
export const pay = (cart) => {
  if (!cart.currency) throw new Error("currency is required");
  return { status: "paid", amount: cart.total };
};
JS
printf '{ "name": "shop", "version": "1.1.0" }\n' >package.json
git_c add -A
git_c commit -q -m "shop 1.1.0"
git tag v2

mkdir -p runs/pass1 runs/pass2
cat >runs/pass1/findings.json <<'JSON'
{
  "pass": {
    "build": "shop@1.0.0",
    "entries": [
      { "feature": "checkout", "part": null, "entry_point": "Pay button", "outcome": "passed", "reason": null, "wall_time_seconds": 41, "tokens": 18200, "unmeasured_reason": null },
      { "feature": "cart", "part": null, "entry_point": "Cart page", "outcome": "failed", "reason": null, "wall_time_seconds": 37, "tokens": 16900, "unmeasured_reason": null },
      { "feature": "search", "part": null, "entry_point": "Search box", "outcome": "failed", "reason": null, "wall_time_seconds": 29, "tokens": 12400, "unmeasured_reason": null },
      { "feature": "orders", "part": null, "entry_point": "Orders page", "outcome": "failed", "reason": null, "wall_time_seconds": 18, "tokens": 9100, "unmeasured_reason": null }
    ]
  },
  "findings": [
    { "id": "c4a7e2d19b3f0a68", "feature": "cart", "part": null, "kind": "result-not-met", "where": "2", "entry_points": ["Cart page"], "severity": "medium", "label": "stated", "evidence": ["cart/report.md"] },
    { "id": "5e9b1c3a7d2f4e80", "feature": "search", "part": null, "kind": "garbled-output", "where": "1", "entry_points": ["Search box"], "severity": "low", "label": "unstated", "evidence": ["search/report.md"] },
    { "id": "9d0f6b2e8a1c3574", "feature": "orders", "part": null, "kind": "crash", "where": "run", "entry_points": ["Orders page"], "severity": "critical", "label": "unstated", "evidence": ["orders/report.md"] }
  ]
}
JSON
cat >runs/pass2/findings.json <<'JSON'
{
  "pass": {
    "build": "shop@1.1.0",
    "entries": [
      { "feature": "checkout", "part": null, "entry_point": "Pay button", "outcome": "failed", "reason": null, "wall_time_seconds": 44, "tokens": 19100, "unmeasured_reason": null },
      { "feature": "cart", "part": null, "entry_point": "Cart page", "outcome": "failed", "reason": null, "wall_time_seconds": 52, "tokens": 23800, "unmeasured_reason": null },
      { "feature": "cart", "part": null, "entry_point": "Mini cart", "outcome": "failed", "reason": null, "wall_time_seconds": null, "tokens": null, "unmeasured_reason": "measured on Cart page" },
      { "feature": "search", "part": null, "entry_point": "Search box", "outcome": "passed", "reason": null, "wall_time_seconds": 26, "tokens": 11800, "unmeasured_reason": null },
      { "feature": "orders", "part": null, "entry_point": "Orders page", "outcome": "not checked", "reason": "blocked: orders service unreachable", "wall_time_seconds": 6, "tokens": 2300, "unmeasured_reason": null }
    ]
  },
  "findings": [
    { "id": "3f1a9c0e7b2d4851", "feature": "checkout", "part": null, "kind": "error", "where": "3", "entry_points": ["Pay button"], "severity": "high", "label": "unstated", "evidence": ["checkout/report.md"] },
    { "id": "c4a7e2d19b3f0a68", "feature": "cart", "part": null, "kind": "result-not-met", "where": "2", "entry_points": ["Cart page", "Mini cart"], "severity": "medium", "label": "stated", "evidence": ["cart/report.md"] }
  ]
}
JSON

printf '/.*\nruns/\n' >>.git/info/exclude
