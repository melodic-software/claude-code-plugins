#!/usr/bin/env bash
# fixture-market with notes-hooks and draw both installed.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fixture-market.sh" both
