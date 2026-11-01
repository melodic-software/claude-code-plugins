#!/usr/bin/env bash
# The harbor monorepo files with no git repository around them.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/harbor-repo.sh" --no-git
