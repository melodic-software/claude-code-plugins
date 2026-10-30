#!/usr/bin/env bash
# Seeds every state of both shared fixture repositories, one directory each.
set -euo pipefail
seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh"
for state in bare conventions-only converged legacy; do
  bash "$seed" tarnquill "$state" "tarnquill-$state"
done
for state in bare conventions-only converged; do
  bash "$seed" brackenfold "$state" "brackenfold-$state"
done
