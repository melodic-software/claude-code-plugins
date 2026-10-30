#!/usr/bin/env bash
# Seeds the eval workspace with the find skill's disconnected-admin-export fixture.
set -euo pipefail

mkdir -p evals/fixtures
cp -R "$(dirname "${BASH_SOURCE[0]}")/../../skills/find/evals/fixtures/disconnected-admin-export" evals/fixtures/
