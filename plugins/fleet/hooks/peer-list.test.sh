#!/usr/bin/env bash
set -uo pipefail
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test --test-concurrency=4 "$(dirname "${BASH_SOURCE[0]}")/peer-list.test.mjs"
