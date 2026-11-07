#!/usr/bin/env bash
# Sourced by a testing scaffold. Clears the inherited git environment, then defines:
#   ws_init <branch> [<path>...]  refuse to scaffold anywhere but an eval run's workspace (the
#                                 root, the real or current home, a workspace inside any repository
#                                 but the run's own temporary home, or one already holding a named
#                                 path), then make the workspace its own repository on <branch>
#   g <git args>                  git with a fixture identity, no hooks and no signing
#   ws_origin                     a bare origin inside the workspace whose HEAD names the current
#                                 branch, pushed and hidden from status
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false \
    -c user.name='Contoso Fixture' -c user.email='fixture@contoso.example' "$@"
}

ws_init() {
  local branch="${1:?branch}" here real_home top tmp run target
  shift
  here="$(pwd -P)"
  real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
  case "${here}" in
  / | "${HOME:-/}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
  *) ;;
  esac
  # The eval workspace sits inside the run's temporary home, which is itself a repository, so a
  # repository above the workspace is expected there. Allow only that one; refuse a workspace that
  # is already a repository and any other enclosing repository.
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
  for target in "$@"; do
    if [[ -e "${target}" ]]; then
      echo "refusing to scaffold: ${here}/${target} already exists" >&2
      exit 3
    fi
  done
  GIT_CEILING_DIRECTORIES="$(dirname "${here}")"
  export GIT_CEILING_DIRECTORIES
  g -c "init.defaultBranch=${branch}" init -q --template=
  if [[ "$(git rev-parse --show-toplevel)" != "${here}" ]]; then
    echo "git did not create a repository here: ${here}" >&2
    exit 3
  fi
  # The workspace holds harness dotfiles; hide untracked files so only the fixture's changes show.
  g config status.showUntrackedFiles no
}

ws_origin() {
  local branch
  branch="$(git branch --show-current)"
  mkdir -p .git/info
  printf '.remote.git/\n' >>.git/info/exclude
  g init -q --bare --template= .remote.git
  g -C .remote.git symbolic-ref HEAD "refs/heads/${branch}"
  g remote add origin "${PWD}/.remote.git"
  g push -q origin "${branch}"
  g remote set-head origin "${branch}"
}
