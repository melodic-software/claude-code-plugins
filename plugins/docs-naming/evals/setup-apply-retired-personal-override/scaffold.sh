#!/usr/bin/env bash
# No team YAML, an ignored personal YAML, and an old .claude/docs-hygiene.local.json with one more exempt_paths entry.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fn-repo.sh" setup-retired-personal
