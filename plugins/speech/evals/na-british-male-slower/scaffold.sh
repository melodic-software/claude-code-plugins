#!/usr/bin/env bash
# The script the prompt names.
set -euo pipefail
mkdir -p docs
printf '%s\n' 'Binary search halves the range at every step.' 'It stops when one item is left.' > docs/script.txt
