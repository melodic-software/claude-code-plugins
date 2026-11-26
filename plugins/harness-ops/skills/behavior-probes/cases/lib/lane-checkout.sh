#!/usr/bin/env bash
set -euo pipefail
cd "$1"
git init -q
printf 'lane-probe-marker\n' >notes.txt
