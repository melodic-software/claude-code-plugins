#!/usr/bin/env bash
# Public entry surface for the course-digest extraction suite. The Node
# package under extraction/ is skill-private; external consumers (CI, docs)
# invoke this facade instead of reaching into it.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../extraction"

case "${1:-all}" in
install) npm ci ;;
build) npm run build ;;
test) npm test ;;
all)
  npm ci
  npm run build
  npm test
  ;;
*)
  echo "usage: run-tests.sh [install|build|test|all]" >&2
  exit 2
  ;;
esac
