#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p .work/reviews/fixture
cp "$here/../fixtures/findings-one-per-rung.md" .work/reviews/fixture/findings.md
