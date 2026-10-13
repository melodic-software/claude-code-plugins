#!/usr/bin/env bash
# Print the absolute path of a Python interpreter that runs, or exit non-zero.
# For callers whose shell is not bash (the go-faster preamble under a zsh Bash
# tool): they run this file with bash instead of sourcing harness-lib.sh.
set -uo pipefail
# shellcheck source=harness-lib.sh
source "${BASH_SOURCE[0]%/*}/harness-lib.sh"
harness_require_python
printf '%s\n' "$HARNESS_PYTHON"
