#!/usr/bin/env bash

requirements="$(dirname "${BASH_SOURCE[0]}")/../../requirements-ci.txt"
: "${RUNNER_TEMP:?}"
awk '/^pyyaml==/ { keep = 1 } keep { print } keep && !/\\$/ { exit }' \
  "$requirements" >"$RUNNER_TEMP/pyyaml-requirements.txt"
python3 -m pip install --disable-pip-version-check --only-binary=:all: \
  --require-hashes --requirement "$RUNNER_TEMP/pyyaml-requirements.txt" || {
  echo "::warning::$1"
  exit 1
}
