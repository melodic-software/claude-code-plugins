#!/usr/bin/env bash
# Writes three Fabrikam repositories under repos/ in the current directory, which must be the
# eval's empty workspace: repos/orders-portal, repos/billing-api and repos/inventory-sync, each
# built by fabrikam-repo.sh in its scan mode (caches, build output and node_modules to reclaim).
# fabrikam-repo.sh keeps its own guards: it refuses the root, the home directory, a directory that
# is already a repository, and any enclosing repository outside the eval run.
set -euo pipefail
fixture="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/fabrikam-repo.sh"
here="$(pwd -P)"
case "${here}" in
/ | "${HOME:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
if [[ -e repos ]]; then
  echo "refusing to scaffold: $(pwd -P)/repos already exists" >&2
  exit 3
fi
for repo in orders-portal billing-api inventory-sync; do
  mkdir -p "repos/${repo}"
  (cd "repos/${repo}" && bash "${fixture}" scan)
done
