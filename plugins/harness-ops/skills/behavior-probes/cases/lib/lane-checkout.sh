#!/usr/bin/env bash
# lane-checkout.sh <dir>: <dir> as a git checkout holding notes.txt, the
# in-checkout file the lane-permissions controls search and read.
set -euo pipefail
cd "$1"
git init -q
printf 'lane-probe-marker\n' >notes.txt
