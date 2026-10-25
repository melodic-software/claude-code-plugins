#!/usr/bin/env bash
# Stages the k36-cart-total project plus a shop.py command line with no
# commands yet, and sets first_test in the team layer: user-flow by default,
# or the value of FIRST_TEST (write-first-unit passes unit).
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../k36-cart-total/scaffold.sh"

cat >shop.py <<'PY'
import sys


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    print("usage: shop.py total <cart-file>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
PY

mkdir -p docs/conventions
printf 'first_test: %s\n' "${FIRST_TEST:-user-flow}" >docs/conventions/testing.yaml
git -c user.name=eval -c user.email=eval@example.invalid add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "Add the shop command line"
