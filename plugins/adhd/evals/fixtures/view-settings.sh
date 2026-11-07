#!/usr/bin/env bash
# Seeds the rendered-views state a clarify case reads through the shared medium resolver.
# team-artifact: the workspace becomes its own git repository with a tracked
# docs/conventions/rendered-views.yaml setting artifact.
# retired-terminal: $HOME/.claude/rendered-views.md sets terminal, and no other setting exists.
set -euo pipefail
set -o noclobber
mode="${1:?mode: team-artifact or retired-terminal}"

here="$(pwd -P)"
case "${here}" in
/ | "${HOME:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac

case "${mode}" in
team-artifact)
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
  printf 'medium: artifact\n' >docs/conventions/rendered-views.yaml
  printf '# billing-service\n\nFabrikam billing service.\n' >README.md
  g add -A
  g commit -q -m "billing-service fixture"
  ;;
retired-terminal)
  # A file under $HOME is written only when $HOME is not the real home of the user running this.
  real="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6 || true)"
  if [[ -z "${real}" || -z "${HOME:-}" || "$(cd "${HOME}" && pwd -P)" == "$(cd "${real}" 2>/dev/null && pwd -P)" ]]; then
    echo "refusing to write under HOME=${HOME:-unset}: it is the real home or the real home is unknown" >&2
    exit 3
  fi
  mkdir -p "${HOME}/.claude"
  printf 'medium: terminal\n' >"${HOME}/.claude/rendered-views.md"
  ;;
*)
  echo "unknown mode: ${mode}" >&2
  exit 2
  ;;
esac
