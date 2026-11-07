#!/usr/bin/env bash
# A git repository tracking discipline.yaml with an invalid lever_scope.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/su-repo.sh" invalid
