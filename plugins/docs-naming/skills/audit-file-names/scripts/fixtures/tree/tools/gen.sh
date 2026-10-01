#!/usr/bin/env bash
# The fixture's stand-in for a real regenerator: it rebuilds build/out.json from
# the tracked file names, so a suite can prove the realign ran it rather than
# text-editing the record.
set -uo pipefail

root="${1:-.}"
samples="$(git -C "$root" ls-files -- 'docs/*.md' | sed 's/.*/"&"/' | paste -sd, -)"
printf '{\n  "generated_on": "regenerated",\n  "samples": [%s]\n}\n' "$samples" >"$root/build/out.json"
printf 'regenerated build/out.json\n'
