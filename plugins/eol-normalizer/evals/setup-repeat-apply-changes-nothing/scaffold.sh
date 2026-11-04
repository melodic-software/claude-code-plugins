#!/usr/bin/env bash
# A repository whose eol=lf rule governs every text path, so check finds nothing to fix.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/repo.sh" '* text=auto eol=lf'
