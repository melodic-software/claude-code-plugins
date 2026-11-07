#!/usr/bin/env bash
# Sourced by a toolchain scaffold. Clears the inherited git environment, then defines:
#   eval_repo_init <branch> [<path>...]  refuse to scaffold anywhere but an eval run's workspace
#                                        (the root, the real or current home, a workspace inside
#                                        any repository but the run's own temporary home, or one
#                                        that already holds a named path), then make the workspace
#                                        its own repository on <branch>
#   g <git args>                         git with a fixture identity, no hooks and no signing
#   eval_repo_origin                     a bare origin inside the workspace whose HEAD names the
#                                        current branch, pushed and hidden from status
#   eval_logger                          tools/run.sh, which appends its arguments as one line to
#                                        the ignored .calls.log and exits 0
#   eval_eco <name> <globs> <phase>...   a tracked .claude/ecosystems/<name>.yaml whose listed
#                                        phases (build, test, check, fix, code-fix) run
#                                        `bash tools/run.sh <name> <phase> ...`; the rest are null
#   eval_eco_off <name>...               a tracked config per name with `enabled: false`
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false \
    -c user.name='Fabrikam Fixture' -c user.email='fixture@fabrikam.example' "$@"
}

eval_repo_init() {
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
  # The workspace holds harness dotfiles; hide untracked files so only the fixture's own changes show.
  g config status.showUntrackedFiles no
}

eval_repo_origin() {
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

eval_logger() {
  mkdir -p tools
  cat >tools/run.sh <<'EOF'
#!/usr/bin/env bash
# The repository's check runner: tools/run.sh <ecosystem> <phase> [<file>...]. Every phase checks the
# named files (all tracked files when none are named) for merge-conflict markers, trailing
# whitespace and a missing final newline, and fails on any. Each call is appended to .calls.log, the
# runner's audit trail.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"
printf '%s\n' "$*" >>.calls.log
eco="$1" phase="$2"
shift 2
if [[ $# -eq 0 ]]; then
  mapfile -t files < <(git ls-files)
  set -- "${files[@]}"
fi
bad=0
for f in "$@"; do
  [[ -f "${f}" ]] || { echo "${f}: no such file" >&2; bad=1; continue; }
  if grep -nE '^(<<<<<<<|>>>>>>>)|[[:blank:]]$' "${f}" >&2; then bad=1; fi
  if [[ -s "${f}" && -n "$(tail -c1 "${f}")" ]]; then echo "${f}: no final newline" >&2; bad=1; fi
done
[[ ${bad} -eq 0 ]] || { echo "${eco} ${phase}: FAIL" >&2; exit 1; }
echo "${eco} ${phase}: $# file(s) checked, ok"
EOF
  printf '.calls.log\n' >>.gitignore
}

eval_eco() {
  local name="${1:?name}" globs="${2:?globs}" phase key value
  shift 2
  mkdir -p .claude/ecosystems
  {
    printf 'globs: %s\n' "${globs}"
    for key in build test check fix code-fix; do
      value=null
      for phase in "$@"; do
        if [[ "${phase}" == "${key}" ]]; then
          value="\"bash tools/run.sh ${name} ${key}"
          [[ "${key}" == test ]] || value+=" <files>"
          value+="\""
        fi
      done
      printf '%s-cmd: %s\n' "${key}" "${value}"
    done
    printf 'install-hint: "bash ships with the OS"\n'
  } >".claude/ecosystems/${name}.yaml"
}

eval_eco_off() {
  local name
  mkdir -p .claude/ecosystems
  for name in "$@"; do
    printf 'globs: ["*.%s-disabled"]\nenabled: false\nbuild-cmd: null\ntest-cmd: null\ncheck-cmd: null\nfix-cmd: null\ncode-fix-cmd: null\n' \
      "${name}" >".claude/ecosystems/${name}.yaml"
  done
}
