#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=harness-lib.sh
source "${BASH_SOURCE[0]%/*}/harness-lib.sh"
harness_require_python
printf '%s\n' "$HARNESS_PYTHON"
