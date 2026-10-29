#!/usr/bin/env bash
# Seeds the bare brackenfold fixture into the workspace and commits it on main.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh" brackenfold bare
