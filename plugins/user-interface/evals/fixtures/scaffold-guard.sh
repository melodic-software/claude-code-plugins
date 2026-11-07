#!/usr/bin/env bash
# Refuses to scaffold anywhere but an eval run's empty workspace: the root, the real or current
# home directory, or a workspace that already holds any of the paths named as arguments.
set -euo pipefail
here="$(pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${HOME:-/}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
for target in "$@"; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2
    exit 3
  fi
done
