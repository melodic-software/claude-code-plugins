#!/usr/bin/env bash
# Seeds a doc where each filler phrase shares its sentence with a plain-word row's flagged word.
set -euo pipefail

mkdir -p docs
cat > docs/cache.md <<'MD'
# Cache helper

In order to leverage the shared cache, each worker opens one connection at startup.

It is worth noting that the helper can facilitate retries when the cache is cold.

Due to the fact that numerous jobs share the cache, its size limit is 512 MB.
MD
