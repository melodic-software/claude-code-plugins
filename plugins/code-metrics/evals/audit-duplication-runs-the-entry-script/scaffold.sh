#!/usr/bin/env bash
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/main
body() {
  printf '%s\n' "def $1(rows):" '    total = 0' '    for row in rows:' '        if row.get("active"):' '            total += row.get("amount", 0) * row.get("rate", 1)' '        else:' '            total -= row.get("refund", 0)' '    return round(total, 2)'
}
body summarize >orders.py
git add orders.py
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
body summarize_invoices >invoices.py
