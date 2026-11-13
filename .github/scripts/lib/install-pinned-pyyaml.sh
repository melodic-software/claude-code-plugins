#!/usr/bin/env bash
# install-pinned-pyyaml.sh: install the hash-pinned PyYAML from the
# requirements-ci.txt beside this script's tree, its `pyyaml==` block alone.
# On a failed install it prints its one argument as a warning and exits 1.
#
#   bash .base/.github/scripts/lib/install-pinned-pyyaml.sh '<warning text>'

requirements="$(dirname "${BASH_SOURCE[0]}")/../../requirements-ci.txt"
: "${RUNNER_TEMP:?}"
awk '/^pyyaml==/ { keep = 1 } keep { print } keep && !/\\$/ { exit }' \
  "$requirements" >"$RUNNER_TEMP/pyyaml-requirements.txt"
python3 -m pip install --disable-pip-version-check --only-binary=:all: \
  --require-hashes --requirement "$RUNNER_TEMP/pyyaml-requirements.txt" || {
  echo "::warning::$1"
  exit 1
}
