#!/usr/bin/env bash
# Makes the eval workspace its own git repository for a discipline setup case, with AGENTS.md
# binding docs/conventions as the convention home, and seeds docs/conventions/discipline.yaml.
# fresh: no discipline.yaml. existing: a tracked file holding lever_scope: non-trivial under a
# comment line. invalid: a tracked file holding lever_scope: always.
set -euo pipefail
set -o noclobber
mode="${1:?mode: fresh, existing or invalid}"

here="$(pwd -P)"
case "${here}" in
/ | "${HOME:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac

# The eval workspace sits inside the run's temporary home, which is itself a repository, so a
# repository above the workspace is expected there. Allow only that one; refuse a workspace that
# is already a repository and any other enclosing repository.
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
case "${mode}" in
fresh | existing | invalid) ;;
*)
  echo "unknown mode: ${mode}" >&2
  exit 2
  ;;
esac
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false \
    -c user.name='Fabrikam Fixture' -c user.email='fixture@fabrikam.example' "$@"
}
g -c init.defaultBranch=main init -q --template=
if [[ "$(git rev-parse --show-toplevel)" != "${here}" ]]; then
  echo "git did not create a repository here: ${PWD}" >&2
  exit 3
fi
mkdir -p docs/conventions
printf '# orders-service\n\nFabrikam order intake service.\n' >README.md
printf '# Conventions\n\nTeam settings for this repository.\n' >docs/conventions/README.md
cat >AGENTS.md <<'MD'
# orders-service

<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `docs/conventions`; read the topic doc there
before changing a governed surface.
<!-- END GENERATED: convention-home -->
MD
case "${mode}" in
existing) printf '# Owned by the platform team.\nlever_scope: non-trivial\n' >docs/conventions/discipline.yaml ;;
invalid) printf 'lever_scope: always\n' >docs/conventions/discipline.yaml ;;
*) ;;
esac
g add -A
g commit -q -m "orders-service fixture"
