#!/usr/bin/env bash
# Public entry surface for the ai-briefing build-pipeline suite. The Node
# package under output/build/ is skill-private; external consumers (CI, docs)
# invoke this facade instead of reaching into it.
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
