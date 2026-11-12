#!/usr/bin/env bash
# test-scope: .github/*.cjs .github/*.mjs .github/*.sh .github/*.bash .github/*.yml .github/*.yaml
# test-scope: plugins/*.js plugins/*.cjs plugins/*.mjs plugins/*.sh plugins/*.yml plugins/*.yaml plugins/*.py .github/*.py
# Owns graphql-operations.test.cjs, which reads every tracked source under
# .github/ and plugins/, YAML config and fixtures included, and loads graphql
# from the root node_modules, so CI runs it in test-bash after the root npm ci.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/graphql-operations.test.cjs"
