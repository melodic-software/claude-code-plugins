#!/usr/bin/env bash
# Seeds the shared batch-simplify fixture repository (see ../fixtures/bs-seed.sh for the
# dated history and which file each scope resolves to).
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/bs-seed.sh" --dirty
