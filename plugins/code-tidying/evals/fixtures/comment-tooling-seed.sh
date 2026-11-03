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
# --user installs into the invoking interpreter's own user site, so install for each interpreter
# the agent may resolve: the scaffold's python3 and /usr/bin/python3, which the sandbox falls back
# to when the operator's interpreter is hidden. Two of the same minor version share one site.
seen=""
for py in python3 /usr/bin/python3; do
  command -v "$py" >/dev/null 2>&1 || continue
  ver="$("$py" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
  [[ " $seen " == *" $ver "* ]] && continue
  seen="$seen $ver"
  "$py" -m pip install --user --break-system-packages --require-hashes --only-binary=:all: \
    --no-deps --no-cache-dir --disable-pip-version-check --no-warn-script-location --quiet \
    -r "$here/comment-tooling.requirements.txt"
  "$py" -c 'import pygments, tree_sitter, tree_sitter_bash, tree_sitter_python'
done
[[ -n "$seen" ]]
