#!/usr/bin/env bash
# Seeds one doc with a formulaic challenges closer and a dated closing line.
set -euo pipefail

mkdir -p docs
cat > docs/status.md <<'MD'
# Project status

The indexer rewrite landed in October. It cut the nightly build from 40 minutes to 11.

Despite its small team, the project faces challenges in keeping up with new file formats, and
its future will depend on attracting more contributors.

## Next release

Version 3.2 ships on 14 January with the streaming parser enabled by default.
MD
