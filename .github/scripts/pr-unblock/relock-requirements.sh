#!/usr/bin/env bash
set -euo pipefail

dir=${1:?usage: relock-requirements.sh <dir>}
command="uv pip compile requirements.in --universal --generate-hashes --python-version 3.12 -o requirements.txt"

uv=${RELOCK_UV:-}
if [[ -z $uv ]]; then
  venv=$(mktemp -d)
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes --only-binary :all: --no-deps \
    --requirement "${RELOCK_REQUIREMENTS:-$(dirname "$0")/../../requirements-relock.txt}"
  uv=$venv/bin/uv
fi

read -ra flags <<<"${command#uv pip compile }"
UV_PYTHON_DOWNLOADS=never "$uv" pip compile --quiet --no-config --directory "$dir" "${flags[@]}" --custom-compile-command "$command"
