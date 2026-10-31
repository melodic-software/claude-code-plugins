#!/usr/bin/env bash
# Seeds a narrative design note carrying an em dash, filler, stacked hedges and chat residue.
set -euo pipefail

mkdir -p docs
cat > docs/build.md <<'MD'
# Why we moved the build to a single runner

It is worth noting that the old build ran on three runners — and the cache could potentially
be out of sync between them, which might possibly explain the flaky tests.

Moving to one runner cut the median build from 14 minutes to 9. The cost is that two builds
now queue behind each other at peak hours.

I hope this helps! Let me know if you have any questions.
MD
