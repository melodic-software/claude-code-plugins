#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p scripts tests/fixtures
cat >README.md <<'EOF'
# app

The proxy keeps its data under `D:\data\ccproxy`.
EOF
cat >scripts/provision.ps1 <<'EOF'
param(
  [string]$DataRoot = "D:\data\ccproxy"
)
New-Item -ItemType Directory -Force -Path $DataRoot | Out-Null
EOF
cat >CHANGELOG.md <<'EOF'
# Changelog

## 1.2.0

- Data moved to `D:\data\ccproxy`.
EOF
cat >PLAN.md <<'EOF'
# Plan: proxy data volume

Status: approved

1. Create `D:\data\ccproxy` on the data volume.
EOF
cat >tests/fixtures/config.json <<'EOF'
{ "dataRoot": "D:\\data\\ccproxy" }
EOF
git add . && git commit -q -m "feat: keep the proxy data on the D volume"
