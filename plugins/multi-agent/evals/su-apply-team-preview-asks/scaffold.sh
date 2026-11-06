#!/usr/bin/env bash
# A git repository with no multi-agent layer, so the team layer is writable and absent.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/workspace.sh" repo
