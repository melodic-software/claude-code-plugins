#!/usr/bin/env bash
# The exercised-scope repo: app.py on main, scenario boundary (committed).
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-exercised.sh" boundary committed
mkdir -p .work
sha="$(git rev-parse HEAD)"
{
  printf '%s\n' "${sha}"
  printf 'app.py\t7\t7\tcomparison-inversion\t    if amount > DISCOUNT_THRESHOLD:\t    if amount <= DISCOUNT_THRESHOLD:\tkilled\n'
  printf 'app.py\t8\t8\tstatement-removal\t        amount = amount * (1 - DISCOUNT_RATE)\t        pass\tsurvived\n'
  printf 'app.py\t9\t9\tstatement-removal\t    amount = amount * (1 + TAX_RATE)\t    pass\tkilled\n'
  printf 'app.py\t10\t10\tstatement-removal\t    return round(amount, 2)\t    pass\tkilled\n'
} >.work/before.tsv
sed -i '9s/.*/    amount = amount * 1.25/' app.py
git commit -q -am "fix: tax at 25 percent"
