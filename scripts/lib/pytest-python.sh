# shellcheck shell=bash

PYTEST_PYTHON_SETUP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/setup-env.sh"

pytest_python::bin_dir() {
  local bin=$1/bin
  [[ -d $1/Scripts ]] && bin=$1/Scripts
  printf '%s\n' "$bin"
}

pytest_python::venv_python() {
  printf '%s\n' "$(pytest_python::bin_dir "$1")/python"
}

pytest_python::imports_pytest() {
  "$1" -I -c 'import pytest' >/dev/null 2>&1
}

pytest_python::main_checkout() {
  local common main
  main=$(pwd -P)
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) &&
    [[ ${common##*/} == .git ]] && main=${common%/*}
  printf '%s\n' "$main"
}

pytest_python::find_venv() {
  local venv py
  for venv in ${SETUP_ENV_VENV:+"$SETUP_ENV_VENV"} "$(pwd -P)/.work/venv" "$(pytest_python::main_checkout)/.work/venv"; do
    py=$(pytest_python::venv_python "$venv")
    if [[ -x $py ]] && pytest_python::imports_pytest "$py"; then
      printf '%s\n' "$venv"
      return 0
    fi
  done
  return 1
}

pytest_python::venv_bin() {
  local venv
  venv=$(pytest_python::find_venv) && pytest_python::bin_dir "$venv"
}

pytest_python::resolve() {
  local top venv py setup=$PYTEST_PYTHON_SETUP
  if venv=$(pytest_python::find_venv); then
    pytest_python::venv_python "$venv"
    return 0
  fi
  if pytest_python::imports_pytest python3; then
    echo python3
    return 0
  fi
  top=$(pwd -P)
  venv=${SETUP_ENV_VENV:-$(pytest_python::main_checkout)/.work/venv}
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
