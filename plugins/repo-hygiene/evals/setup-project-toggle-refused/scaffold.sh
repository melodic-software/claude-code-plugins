#!/usr/bin/env bash
# orders-portal with a project .claude/settings.json.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fabrikam-repo.sh" setup
