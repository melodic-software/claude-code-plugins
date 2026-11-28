#!/usr/bin/env bash
set -euo pipefail
seed="$(dirname "${BASH_SOURCE[0]}")/../fixtures/su-seed.sh"
bash "$seed" su-readme.md=README.md su-app.py=src/web/app.py su-legacy-policy.yaml=docs/conventions/code-tidying.yaml
bash "$seed" --no-commit su-legacy-policy.local.yaml=docs/conventions/code-tidying.local.yaml
