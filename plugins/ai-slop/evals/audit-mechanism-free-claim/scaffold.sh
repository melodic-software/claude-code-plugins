#!/usr/bin/env bash
# Seeds one doc with a feeling-word claim beside a measured one.
set -euo pipefail

mkdir -p docs
cat > docs/cli.md <<'MD'
# Why we picked this CLI

The CLI feels snappy and modern, and working with it is a joy.

The CLI starts in 80 ms on a cold cache and reads its settings from one `cli.toml` file.
MD
