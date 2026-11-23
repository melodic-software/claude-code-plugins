#!/usr/bin/env bash
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/check-workflow-template-size.test.mjs"
