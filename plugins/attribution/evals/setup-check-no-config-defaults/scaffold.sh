#!/usr/bin/env bash
# A committed repository with no attribution config in any layer.
set -euo pipefail

here="$(pwd -P)"
case "${here}" in
/ | "${HOME:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
# The eval workspace sits inside the run's temporary home, itself a repository: allow only that one.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  tmp="$(cd "${TMPDIR:-/nonexistent}" 2>/dev/null && pwd -P || true)"
  if [[ "${top}" == "${here}" ]]; then
    echo "refusing to scaffold: ${here} is already a repository" >&2
    exit 3
  fi
  run="$(dirname "${tmp:-/}")"
  if [[ -z "${tmp}" || "$(basename "${tmp}")" != tmp || "$(basename "${run}")" != claude-eval-* || "${top}" != "${run}/home" || "${here}/" != "${top}/"* ]]; then
    echo "refusing to scaffold inside ${top}, a repository outside TMPDIR (${TMPDIR:-unset})" >&2
    exit 3
  fi
fi
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES

git init -q -b main .
printf '# Widget service\n\nInternal notes for the widget service.\n' >README.md
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm seed
