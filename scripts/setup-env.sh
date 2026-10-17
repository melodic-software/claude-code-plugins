#!/usr/bin/env bash
# Install what this repository's tests and lane work need, on demand:
#   - Python at .python-version in a venv, with pytest and the rest of the
#     hash-pinned wheels in .github/requirements-ci.txt (as pr-require-checks.yml
#     installs them);
#   - the locked Node packages (npm ci at the root and in
#     .github/standards/runner-policy);
#   - Playwright's Chromium, only with --playwright or SETUP_ENV_PLAYWRIGHT=1
#     (https://playwright.dev/docs/ci: install browsers on each run, no cache).
#
#   bash scripts/setup-env.sh [--playwright] [--root DIR]
#
# Re-running is cheap: each step records the hash of the file it installed
# from and skips while that hash matches. The venv goes to SETUP_ENV_VENV, else
# <root>/.work/venv. Under GitHub Actions the venv and node_modules/.bin are
# added to GITHUB_PATH for later steps.
set -euo pipefail

playwright=${SETUP_ENV_PLAYWRIGHT:-0}
root=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --playwright) playwright=1 ;;
    --root)
      root=${2:?setup-env: --root needs a directory}
      shift
      ;;
    -h | --help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "setup-env: unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done
root=${root:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
cd "$root"

hash_of() {
  if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

# Python.
want=$(tr -d '[:space:]' <.python-version)
venv=${SETUP_ENV_VENV:-$root/.work/venv}
bin=$venv/bin
[[ -d "$venv/Scripts" ]] && bin=$venv/Scripts
key="$want $(hash_of .github/requirements-ci.txt)"
if [[ -f "$venv/.setup-env" ]] && [[ "$(cat "$venv/.setup-env")" = "$key" ]]; then
  echo "setup-env: Python $want venv is current: $venv"
else
  py=""
  for candidate in "python$want" python3 python; do
    if command -v "$candidate" >/dev/null &&
      "$candidate" -c "import sys; sys.exit('%d.%d' % sys.version_info[:2] != '$want')" 2>/dev/null; then
      py=$candidate
      break
    fi
  done
  if [[ -n "$py" ]]; then
    "$py" -m venv --clear "$venv"
  elif command -v uv >/dev/null; then
    uv venv --quiet --seed --clear --python "$want" "$venv"
  else
    echo "setup-env: no Python $want on PATH and no uv to fetch one" >&2
    exit 1
  fi
  [[ -d "$venv/Scripts" ]] && bin=$venv/Scripts
  "$bin/python" -m pip install --quiet --only-binary=:all: --require-hashes \
    --requirement .github/requirements-ci.txt
  printf '%s\n' "$key" >"$venv/.setup-env"
  echo "setup-env: installed .github/requirements-ci.txt into $venv"
fi

# Node.
for dir in . .github/standards/runner-policy; do
  key=$(hash_of "$dir/package-lock.json")
  stamp=$dir/node_modules/.setup-env
  if [[ -f "$stamp" ]] && [[ "$(cat "$stamp")" = "$key" ]]; then
    echo "setup-env: $dir/node_modules is current"
  else
    npm ci --prefix "$dir"
    printf '%s\n' "$key" >"$stamp"
  fi
done

# Playwright: --with-deps installs the browser's system libraries and needs sudo.
if [[ "$playwright" = 1 ]]; then
  if sudo -n true 2>/dev/null; then
    node node_modules/playwright/cli.js install --with-deps chromium
  else
    node node_modules/playwright/cli.js install chromium
  fi
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "$bin" "$root/node_modules/.bin" >>"$GITHUB_PATH"
fi
