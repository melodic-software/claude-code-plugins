#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
cp "$here/../fixtures/review-comments.jsonl" review-comments.jsonl
