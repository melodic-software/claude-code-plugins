#!/usr/bin/env bash
# Commits both files clean, then leaves an uncommitted edit to cmd/worker.go only.
set -euo pipefail
fixtures="$(dirname "${BASH_SOURCE[0]}")/../fixtures"
bash "$fixtures/acr-seed.sh" acr-legacy.py=lib/legacy.py acr-worker-v1.go=cmd/worker.go
cp "$fixtures/acr-worker-v2.go.txt" cmd/worker.go
