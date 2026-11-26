#!/usr/bin/env bash
set -uo pipefail

root="${1:-.}"
samples="$(git -C "$root" ls-files -- 'docs/*.md' | sed 's/.*/"&"/' | paste -sd, -)"
printf '{\n  "generated_on": "regenerated",\n  "samples": [%s]\n}\n' "$samples" >"$root/build/out.json"
printf 'regenerated build/out.json\n'
