#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../output/build"

case "${1:-all}" in
install) npm ci ;;
test) npm test ;;
all)
  npm ci
  npm test
  ;;
*)
  echo "usage: run-tests.sh [install|test|all]" >&2
  exit 2
  ;;
esac
