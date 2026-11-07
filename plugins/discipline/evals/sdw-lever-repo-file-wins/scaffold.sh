#!/usr/bin/env bash
# Seed docs/conventions/discipline.yaml with lever_scope: deterministic (the repository layer, over a non-trivial user option).
set -euo pipefail

here="$(pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${HOME:-/}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
if [[ -e docs ]]; then
  echo "refusing to scaffold: ${here}/docs already exists" >&2
  exit 3
fi

mkdir -p docs/conventions
printf 'lever_scope: deterministic\n' >docs/conventions/discipline.yaml
