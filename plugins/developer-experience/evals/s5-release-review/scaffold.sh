#!/usr/bin/env bash
# Seeds the converged brackenfold fixture into the workspace.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh" brackenfold converged
