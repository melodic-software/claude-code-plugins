#!/usr/bin/env bash
# Installs pygments and tree-sitter with its grammars into the run's user site, so the agent's
# python3 imports them and change-shape.py can certify a deletion. The eval sandbox hides the
# operator's home, with any interpreter or package installed there, and has no network for an
# install of its own; the scaffold shares the run's HOME with the agent and has the network.
# Hash-pinned wheels only, so no build code runs. Exits non-zero when the import still fails,
# so no run is scored that could only propose deletions.
# Usage: comment-tooling-seed.sh
set -euo pipefail

here="$(dirname "${BASH_SOURCE[0]}")"
# --user installs into the invoking interpreter's own user site. The scaffold's python3 must take
# the tooling: a failure there fails the run. /usr/bin/python3, the sandbox's fallback when the
# operator's interpreter is hidden, is best-effort: a failure there only warns, and the in-sandbox
# probe-environment case catches a fallback that never got it. The pinned tree-sitter wheels cover
# CPython 3.11, 3.12 and 3.14 only (.github/requirements-ci.txt), so another minor fails at the
# install. The 3.12 wheel is Linux x64 only, for the hosted eval runner's system Python.
install() {
  "$1" -m pip install --user --break-system-packages --require-hashes --only-binary=:all: \
    --no-deps --no-cache-dir --disable-pip-version-check --no-warn-script-location --quiet \
    -r "$here/comment-tooling.requirements.txt" &&
    "$1" -c 'import pygments, tree_sitter, tree_sitter_bash, tree_sitter_python'
}
minor() { "$1" -c 'import sys; print("%d.%d" % sys.version_info[:2])'; }

install python3
[[ -x /usr/bin/python3 ]] || exit 0
own="$(minor python3)"
# shellcheck disable=SC2310 # best-effort by design: a fallback that does not run is skipped
fallback="$(minor /usr/bin/python3)" || {
  echo "comment-tooling-seed: /usr/bin/python3 does not run; skipping the fallback" >&2
  exit 0
}
[[ "$fallback" != "$own" ]] || exit 0
# shellcheck disable=SC2310 # best-effort by design: a failure only warns
install /usr/bin/python3 ||
  echo "comment-tooling-seed: /usr/bin/python3 $fallback did not take the tooling (wheels cover 3.11, 3.12 and 3.14); continuing" >&2
