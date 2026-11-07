#!/usr/bin/env bash
# Seeds the eval workspace with the auth-middleware-change fixture.
set -euo pipefail

mkdir -p evals/fixtures
cp -R "$(dirname "${BASH_SOURCE[0]}")/../fixtures/auth-middleware-change" evals/fixtures/
