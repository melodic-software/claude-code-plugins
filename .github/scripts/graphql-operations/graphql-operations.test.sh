#!/usr/bin/env bash
# test-scope: .github/*.cjs .github/*.mjs .github/*.sh .github/*.bash .github/workflows/*.yml .github/actions/*/action.yml
# test-scope: .github/actionlint.yaml .github/dependabot.yml .github/actions/resolve-config/fixtures/*.yaml .github/scripts/intake-triage/reentry-eval/cases/*/case.yaml
# test-scope: plugins/*.js plugins/*.cjs plugins/*.mjs plugins/*.sh plugins/*.yml plugins/*.yaml plugins/*.py .github/*.py
# Owns graphql-operations.test.cjs, which reads every tracked source under
# .github/ and plugins/ and loads graphql from the root node_modules, so CI
# runs it in test-bash after the root npm ci. Under .github/ the YAML scope is
# the workflows, composite actions, and the config and fixture files the
# selection audit traced it reading; other .github YAML stays a no-suite class.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/graphql-operations.test.cjs"
