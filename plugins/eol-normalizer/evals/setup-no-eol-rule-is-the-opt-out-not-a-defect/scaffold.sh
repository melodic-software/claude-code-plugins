#!/usr/bin/env bash
# A repository with no .gitattributes, so no eol= rule governs any path.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/repo.sh"
