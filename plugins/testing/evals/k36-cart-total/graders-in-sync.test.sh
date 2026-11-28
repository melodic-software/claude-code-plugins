#!/usr/bin/env bash
# test-scope: plugins/testing/evals/k36-cart-total*/graders/* plugins/testing/evals/k36-cart-total*/samples/*
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TWIN="$HERE/../k36-cart-total-named"

for dir in graders samples; do
  if ! diff -r "$HERE/$dir" "$TWIN/$dir"; then
    echo "FAIL: k36-cart-total/$dir and k36-cart-total-named/$dir differ" >&2
    exit 1
  fi
done
echo "PASS: k36 graders and samples match"
