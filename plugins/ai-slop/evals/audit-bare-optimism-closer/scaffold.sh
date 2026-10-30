#!/usr/bin/env bash
# Seeds one doc whose specific paragraph ends in a bare optimism closer.
set -euo pipefail

mkdir -p docs
cat > docs/cache.md <<'MD'
# Build cache

The shared build cache went live on 3 March. It holds the last 30 days of artifacts, and a cold
CI build now restores in 90 seconds instead of six minutes.

The future looks bright.
MD
