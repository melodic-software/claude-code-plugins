#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
cp "$here/../fixtures/excerpts-one-session.jsonl" excerpts.jsonl
