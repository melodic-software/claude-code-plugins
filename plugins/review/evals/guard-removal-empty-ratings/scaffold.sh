#!/usr/bin/env bash
# main averages star ratings with an early return for a product that has no reviews yet;
# the branch folds the function into one expression and drops that return.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

cat >ratings.py <<'PY'
def average_rating(reviews):
    if not reviews:
        return 0.0
    total = sum(review["stars"] for review in reviews)
    return round(total / len(reviews), 1)
PY

cat >product_page.py <<'PY'
import json
import sys

from ratings import average_rating


def render(product):
    return "%s: %.1f stars" % (product["name"], average_rating(product["reviews"]))


if __name__ == "__main__":
    with open(sys.argv[1]) as handle:
        for product in json.load(handle):
            print(render(product))
PY

cat >products.json <<'JSON'
[
  {"name": "Desk lamp", "reviews": [{"stars": 4}, {"stars": 5}]},
  {"name": "Cable tray", "reviews": []}
]
JSON

git add .
git commit -q -m "feat: product page with average rating"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b refactor/ratings
cat >ratings.py <<'PY'
def average_rating(reviews):
    return round(sum(review["stars"] for review in reviews) / len(reviews), 1)
PY
git commit -q -am "refactor: simplify average_rating to one expression"
