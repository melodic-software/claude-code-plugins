#!/usr/bin/env bash
# Makes the eval workspace its own git repository holding the rendered-views state a visualize case
# reads through the shared medium resolver.
# team-file: a tracked docs/conventions/rendered-views.yaml setting file.
# personal-file: an untracked, gitignored docs/conventions/rendered-views.local.yaml setting file,
# and no team file.
set -euo pipefail
set -o noclobber
mode="${1:?mode: team-file or personal-file}"
case "${mode}" in
team-file | personal-file) ;;
*) echo "unknown mode: ${mode}" >&2 && exit 2 ;;
esac

here="$(pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${HOME:-/}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
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
for target in docs README.md .gitignore; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2
    exit 3
  fi
done

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
printf '# release-service\n\nFabrikam release service.\n' >README.md
mkdir -p docs/conventions
case "${mode}" in
team-file)
  printf 'medium: file\n' >docs/conventions/rendered-views.yaml
  g add README.md docs/conventions/rendered-views.yaml
  ;;
*) # personal-file; the mode was checked above
  printf 'docs/conventions/rendered-views.local.yaml\n' >.gitignore
  printf 'medium: file\n' >docs/conventions/rendered-views.local.yaml
  g add README.md .gitignore
  ;;
esac
g commit -q -m "release-service fixture"
