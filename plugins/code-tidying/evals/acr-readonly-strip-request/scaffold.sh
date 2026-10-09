#!/usr/bin/env bash
exec bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/acr-seed.sh" acr-cache.ts=src/cache.ts
