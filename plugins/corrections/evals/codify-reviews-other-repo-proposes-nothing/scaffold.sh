#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
git remote add origin https://github.com/acme/web.git
grep '"author":"frank"' "$here/../fixtures/review-comments.jsonl" >review-comments.jsonl
