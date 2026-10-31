#!/usr/bin/env bash
# Commits src/cart.py on main, then leaves an uncommitted count_items change with an obvious cleanup and no lines file.
set -euo pipefail

git init -q
git symbolic-ref HEAD refs/heads/main
mkdir -p src
cat >src/cart.py <<'EOF'
def cart_total(items):
    return sum(item.price for item in items)
EOF
git add src/cart.py
git -c user.name=dev -c user.email=dev@example.invalid -c commit.gpgsign=false commit -q -m "add cart total"
cat >>src/cart.py <<'EOF'


def count_items(items):
    count = 0
    for item in items:
        # increment the counter
        count = count + 1
    return count
EOF
