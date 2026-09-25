#!/usr/bin/env bash
# Public entry for the course-digest extraction suite; CI and docs call this
# facade instead of reaching into the skill-private extraction/ package.
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
