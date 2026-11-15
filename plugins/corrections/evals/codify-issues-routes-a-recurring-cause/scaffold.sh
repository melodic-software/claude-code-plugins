#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
cp "$here/../fixtures/closed-issues.jsonl" closed-issues.jsonl
