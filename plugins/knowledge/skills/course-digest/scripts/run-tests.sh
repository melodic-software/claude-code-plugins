#!/usr/bin/env bash
# Public entry for the course-digest extraction suite; CI and docs call this
# facade instead of reaching into the skill-private extraction/ package.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: run-tests.sh [install|build|test|all]

  install  npm ci
  build    npm run build
  test     npm test
  all      install, build, then test (default)

exit codes: 0 success; 2 unknown subcommand; otherwise the failing npm step's status
EOF
}

cd "$(dirname "${BASH_SOURCE[0]}")/../extraction"

case "${1:-all}" in
-h | --help) usage ;;
install) npm ci ;;
build) npm run build ;;
test) npm test ;;
all)
  npm ci
  npm run build
  npm test
  ;;
*)
  echo "run-tests.sh: unknown subcommand '$1'" >&2
  usage >&2
  exit 2
  ;;
esac
