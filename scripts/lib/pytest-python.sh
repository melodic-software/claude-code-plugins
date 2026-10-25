# shellcheck shell=bash
# The interpreter that runs this repository's pytest suites, one choice for
# scripts/run-test-file.sh and scripts/selection-audit.sh. Sourced, never
# executed; call it from the checkout's root.
#
#   py=$(pytest_python::resolve)
#
# Prints the first that applies:
#   1. the python of a scripts/setup-env.sh venv that imports pytest:
#      SETUP_ENV_VENV, else .work/venv in this checkout, else .work/venv in
#      the main checkout, which every worktree of the clone shares;
#   2. python3, when it imports pytest;
#   3. off CI, when this checkout has setup-env's inputs: the venv after one
#      setup-env.sh run, at SETUP_ENV_VENV or the main checkout's .work/venv,
#      under a lock so parallel callers build it once. setup-env has no
#      Python-only step, so the run also refreshes ShellCheck and node_modules;
#      its output goes to stderr;
#   4. python3, so pytest's own error says what is missing.
# CI installs its own Python (setup-env puts the venv on GITHUB_PATH), so
# step 3 never runs under CI or GITHUB_ACTIONS.

PYTEST_PYTHON_SETUP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/setup-env.sh"

pytest_python::venv_python() {
  local bin=$1/bin
  [[ -d $1/Scripts ]] && bin=$1/Scripts
  printf '%s\n' "$bin/python"
}

pytest_python::imports_pytest() {
  "$1" -I -c 'import pytest' >/dev/null 2>&1
}

pytest_python::resolve() {
  local top main common venv py setup=$PYTEST_PYTHON_SETUP
  top=$(pwd -P)
  main=$top
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) &&
    [[ ${common##*/} == .git ]] && main=${common%/*}
  for venv in ${SETUP_ENV_VENV:+"$SETUP_ENV_VENV"} "$top/.work/venv" "$main/.work/venv"; do
    py=$(pytest_python::venv_python "$venv")
    if [[ -x $py ]] && pytest_python::imports_pytest "$py"; then
      printf '%s\n' "$py"
      return 0
    fi
  done
  if pytest_python::imports_pytest python3; then
    echo python3
    return 0
  fi
  venv=${SETUP_ENV_VENV:-$main/.work/venv}
  py=$(pytest_python::venv_python "$venv")
  if [[ -z ${CI:-}${GITHUB_ACTIONS:-} && -f $setup && -f .python-version && -f .github/requirements-ci.txt ]] &&
    mkdir -p "${venv%/*}"; then
    echo "pytest-python: python3 has no pytest; building $venv with scripts/setup-env.sh" >&2
    if command -v flock >/dev/null; then
      SETUP_ENV_VENV=$venv flock "$venv.lock" bash "$setup" --root "$top" >&2
    else
      SETUP_ENV_VENV=$venv bash "$setup" --root "$top" >&2
    fi
    if [[ -x $py ]] && pytest_python::imports_pytest "$py"; then
      printf '%s\n' "$py"
      return 0
    fi
    echo "pytest-python: setup-env did not leave pytest in $venv; using python3" >&2
  fi
  echo python3
}
