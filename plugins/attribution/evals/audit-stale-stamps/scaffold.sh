#!/usr/bin/env bash
# Three docs with verification stamps: one ISO stamp far past the window, one dated today, one in month-name form.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/stamps-repo.sh"
