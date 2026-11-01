#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p reports
sed "/^branch:/d" "$here/../fixtures/findings-one-per-rung.md" >reports/detector-findings.md
git checkout -q --detach
