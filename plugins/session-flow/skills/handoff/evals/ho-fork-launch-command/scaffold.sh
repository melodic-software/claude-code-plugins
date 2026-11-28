#!/usr/bin/env bash
set -euo pipefail

git -C "$PWD" init -q -b main
mkdir -p .work
printf '*\n' > .work/.gitignore
printf '# Guide\n\n[Setup](setup.md)\n' > guide.md
