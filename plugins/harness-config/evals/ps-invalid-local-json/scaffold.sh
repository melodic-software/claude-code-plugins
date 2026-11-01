#!/usr/bin/env bash
# The quay repo with project rules and a local settings file that is not valid JSON.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" state-broken
