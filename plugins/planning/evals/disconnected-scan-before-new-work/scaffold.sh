#!/usr/bin/env bash
# Seeds the eval workspace with the brainstorm skill's disconnected-scan fixture, suffix kept.
set -euo pipefail

mkdir -p evals/fixtures
cp -R "$(dirname "${BASH_SOURCE[0]}")/../../skills/brainstorm/evals/fixtures/disconnected-scan" evals/fixtures/
