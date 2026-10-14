#!/usr/bin/env bash
# Seeds the eval workspace with the quiz-me skill's auth-middleware-change fixture.
set -euo pipefail

mkdir -p evals/fixtures
cp -R "$(dirname "${BASH_SOURCE[0]}")/../../skills/quiz-me/evals/fixtures/auth-middleware-change" evals/fixtures/
