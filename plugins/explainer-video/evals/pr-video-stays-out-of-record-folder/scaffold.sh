#!/usr/bin/env bash
# The markdown record the prompt asks to turn into a video.
set -euo pipefail
mkdir -p docs/topics/caching
cat >docs/topics/caching/README.md <<'MD'
# Caching

A read checks the cache first. A miss loads the value from the store and writes it to the cache.
A write updates the store and removes the cached value, so the next read loads the new one.
MD
