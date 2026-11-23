#!/usr/bin/env bash
set -euo pipefail
fixtures="$(dirname "${BASH_SOURCE[0]}")/../fixtures"
bash "$fixtures/acr-seed.sh" acr-legacy.py=lib/legacy.py acr-worker-v1.go=cmd/worker.go
cp "$fixtures/acr-worker-v2.go.txt" cmd/worker.go
